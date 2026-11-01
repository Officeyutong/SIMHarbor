// SIMHarbor native persistent APDU bridge. Runtime capability discovery.
#import <Foundation/Foundation.h>
#import <substrate.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <ptrauth.h>
#import <arpa/inet.h>
#import <dlfcn.h>
#import <sys/time.h>
#import <atomic>
#import <vector>
#import <memory>
#import <functional>
#import <mutex>
#import "SlotRouting.hpp"
#import "../shared/Wire.h"
#import "../shared/JSONFoundation.h"
using shjson::Operation;
using shjson::Reply;
#import "RuntimeResolver.hpp"
using Vec = std::vector<uint8_t>;
using Fn = std::function<void(bool)>;
static std::shared_ptr<SHFirmware> firmware;
static shresolve::Plan resolved;
// Read a required address or field offset from the validated discovery plan.
// Callers must wait for compatibility checks; there is no numerical fallback.
static uintptr_t location(const char *key) { return resolved.values.at(key); }
static std::atomic<void *> registryMap{nullptr};
static std::atomic<void *> iface{nullptr}, driver{nullptr};
// Session state machine (one retained management channel across all app requests):
//
//   Idle --open--> Opening --channel retained / direct opened callback--> Open
//   Open --transmit--> Transmitting --exchange completion--> Open
//   Open --explicit close / disconnect cleanup--> Closing --completion--> Idle
//   Opening --opening flow completes without a retained channel--> Idle
//
// Opening -> Open: closeHook defers the sender's automatic close, or the direct
// opened block records the channel. Transmitting -> Open: closeHook or the direct
// completion callback finishes the exchange while retaining the channel.
// Closing -> Idle and Opening -> Idle: completionHook or the direct completion
// callback finishes the corresponding flow. Callbacks store phase before signalDone.
// Open describes channel availability, not APDU success; SW1/SW2 is checked separately.
// Only Idle accepts open; only Open accepts transmit or a nontrivial close.
// A timeout does not roll back phase or prove that the card did not execute a command.
// Disconnect cleanup closes Open, or waits for Opening/Transmitting to reach Open
// before attempting close; it does not forcibly reset a busy or timed-out session.
// Phase values live in shared/Protocol.hpp and retain their existing numeric IPC encoding.
using shjson::Phase;
static std::atomic<Phase> phase{Phase::Idle};
static std::atomic<int> channel{-1};
static Vec *responseVector;
static Fn retained;
static Vec pending, raw;
static std::mutex mu;
static int slot = 0, qmiError;
static dispatch_semaphore_t event;
static int logicalSlot = 0;
static bool directSession = false;
static std::shared_ptr<Vec> directResponse;
static std::atomic<bool> compatible{false};
static void (*commandOrig)(void *, int, uint8_t, uint8_t, Vec &, const Fn &);
static void (*closeOrig)(void *, int, uint8_t, bool, const Fn &);
static void (*encodeOrig)(void *, Vec &);
static void (*responseOrig)(void *, const Vec &);
static void (*qmiOrig)(void *, void *);

static void (*completionOrig)(void *, bool *);
// Wake a bridge request waiting for a driver callback to advance the session phase.
// The caller must update phase before signalling; the semaphore carries no result data.
static void signalDone() { dispatch_semaphore_signal(event); }
// Observe the opening command for the selected hardware slot and capture its live
// driver, channel and response-vector reference. The vector remains owned by the
// original session; always forward the command to preserve the driver's workflow.
static void commandHook(void *self, int s, uint8_t c, uint8_t ins, Vec &v, const Fn &cb) {
    if (phase.load() == Phase::Opening && s == slot) {
        driver = self;
        channel = c;
        responseVector = &v;
    }
    commandOrig(self, s, c, ins, v, cb);
}
// Let the original encoder build its APDU, then substitute the pending user bytes
// once during an active transmission on the captured channel. This hook checks the
// channel, not the hardware slot; pending is consumed under the shared buffer mutex.
static void encodeHook(void *b, Vec &v) {
    encodeOrig(b, v);
    if (phase.load() == Phase::Transmitting &&
        *((uint8_t *)b + location("encoderChannel")) == channel) {
        std::lock_guard<std::mutex> g(mu);
        if (!pending.empty()) {
            v = pending;
            pending.clear();
        }
    }
}
// Capture the complete card response, including SW1/SW2, only for the transmitting
// session's hardware slot and channel. Preserve normal driver processing afterward.
static void responseHook(void *b, const Vec &v) {
    if (phase.load() == Phase::Transmitting &&
        *(int *)((char *)b + location("responseSlot")) == slot &&
        *((uint8_t *)b + location("responseChannel")) == channel) {
        std::lock_guard<std::mutex> g(mu);
        raw = v;
    }
    responseOrig(b, v);
}
// Capture the driver's transport-result field separately from the card's status word.
// The current guard is the transmitting phase only, without slot/channel filtering.
static void qmiHook(void *b, void *r) {
    if (phase.load() == Phase::Transmitting)
        qmiError = *(int *)((char *)r + location("qmiError"));
    qmiOrig(b, r);
}
// Defer automatic close for our matching opening/transmitting session, retaining
// its completion callback so subsequent APDUs can reuse the channel. Report an open
// session to the waiter; unrelated closes and explicit closing pass through.
static void closeHook(void *self, int s, uint8_t c, bool ok, const Fn &cb) {
    const Phase p = phase.load();
    if ((p == Phase::Opening || p == Phase::Transmitting) && self == driver && s == slot &&
        c == channel) {
        if (!retained)
            retained = cb;
        phase.store(Phase::Open);
        signalDone();
        return;
    }
    closeOrig(self, s, c, ok, cb);
}
// Run the original high-level completion handler before updating bridge state.
// Wake explicit-close waiters, or opening waiters whose flow ended without a
// retained channel. Direct sessions use their own completion callback below.
static void completionHook(void *self, bool *ok) {
    completionOrig(self, ok);
    if (phase.load() == Phase::Closing) {
        phase.store(Phase::Idle);
        signalDone();
    } else if (phase.load() == Phase::Opening) {
        phase.store(Phase::Idle);
        signalDone();
    }
}
static void *(*serviceMapOrig)(void *);
static void *(*serviceMapMutableOrig)(void *);
// Observe the Registry service map returned to CommCenter without changing it.
// Bounded controller discovery happens later, outside this getter hook.
static void *serviceMapHook(void *self) {
    void *m = serviceMapOrig(self);
    registryMap = m;
    return m;
}
// Capture the same Registry map through the mutable getter when that export exists.
// Preserve the original return value and defer object inspection to ensureInterface.
static void *serviceMapMutableHook(void *self) {
    void *m = serviceMapMutableOrig(self);
    registryMap = m;
    return m;
}
// Reuse the cached controller, or discover one unique live controller from the
// captured Registry map and validate its driver/slot layout. Failure leaves iface
// unset so a later request can retry while CommCenter finishes initialization.
static bool ensureInterface() {
    if (iface)
        return true;
    auto fw = std::atomic_load(&firmware);
    if (!compatible || !fw)
        return false;
    fw->objectStage = registryMap.load() ? 1 : 0;
    uintptr_t object = shresolve::findController(
        (uintptr_t)registryMap.load(), location("controllerVtable"), SHReadMemory, SHCleanPointer);
    if (!object || !SHInferObjectLayout(*fw, object))
        return false;
    iface = (void *)object;
    return true;
}
// Construct a callable signed function pointer for a resolved entry point.
// Signing does not validate the address or private ABI; discovery and the caller's
// function type must already agree with the current driver implementation.
template <typename T> static T signedFn(uintptr_t p) {
    return (T)ptrauth_sign_unauthenticated((void *)p, ptrauth_key_function_pointer, 0);
}
// Wait up to 25 seconds for one asynchronous driver completion signal.
// A timeout neither resets the session nor proves that a card command did not run.
static bool awaitDone() {
    return dispatch_semaphore_wait(event, dispatch_time(DISPATCH_TIME_NOW, 25 * NSEC_PER_SEC)) == 0;
}
// Close an idle session trivially, or invoke the original close for an open session.
// Keep the retained callback and any owned response vector until completion is
// observed; a busy state or timeout returns failure without claiming session release.
static bool closeSession() {
    if (phase.load() == Phase::Idle)
        return true;
    if (phase.load() != Phase::Open || !retained)
        return false;
    phase.store(Phase::Closing);
    closeOrig(driver, slot, channel, true, retained);
    bool ok = awaitDone();
    if (ok) {
        retained = {};
        directResponse.reset();
        directSession = false;
        driver = nullptr;
        responseVector = nullptr;
        channel = -1;
    }
    return ok;
}
// Build an operation-level error reply. networkLoop adds the matching request ID.
static Reply fail(NSString *s) { return Reply::failure(SHStdString(s)); }
// Enumerate assigned logical/hardware slots from the validated live SimInfo vector.
// Bound memory reads, skip unassigned placeholders and reject ambiguous mappings.
// Return nullopt on discovery/read failure; an empty vector is a valid enumeration.
// Readiness is modem metadata, not proof that a slot contains a manageable eUICC.
static std::optional<std::vector<shjson::Slot>> availableSlots() {
    if (!ensureInterface())
        return std::nullopt;
    auto fw = std::atomic_load(&firmware);
    uintptr_t span[2] = {};
    if (!SHReadMemory((uintptr_t)iface.load() + location("simVector"), span, sizeof span) ||
        !span[0] || span[1] < span[0] || (span[1] - span[0]) % sizeof(std::shared_ptr<void>) ||
        span[1] - span[0] > 16 * sizeof(std::shared_ptr<void>))
        return std::nullopt;
    std::vector<shslots::Slot> raw, assigned;
    for (uintptr_t p = span[0]; p < span[1]; p += sizeof(std::shared_ptr<void>)) {
        uintptr_t si = 0;
        int logical = 0, hardware = 0;
        if (!SHReadMemory(p, &si, 8) || !si ||
            !SHReadMemory(si + location("logicalSlot"), &logical, 4))
            return std::nullopt;
        if (logical <= 0) {
            raw.push_back({logical, 0, false});
            continue;
        }
        if (!SHReadMemory(si + fw->hardwareSlot.load(), &hardware, 4))
            return std::nullopt;
        using State = int (*)(void *);
        using Ready = bool (*)(int);
        bool ready =
            signedFn<Ready>(location("isReady"))(signedFn<State>(location("simState"))((void *)si));
        raw.push_back({logical, hardware, ready});
    }
    if (!shslots::assigned(raw, assigned))
        return std::nullopt;
    std::vector<shjson::Slot> result;
    for (const auto &entry : assigned)
        result.push_back({entry.logical, entry.hardware, entry.ready});
    return result;
}
// Resolve exactly one assigned logical slot to its hardware ID and readiness flag.
// Output references are meaningful only when the lookup succeeds; never fall back
// to another card when the requested slot is absent or enumeration fails.
static bool slotInfo(int requested, int &hardware, bool &ready) {
    int matches = 0;
    auto slots = availableSlots();
    if (!slots)
        return false;
    for (const auto &entry : *slots) {
        if (entry.logicalSlot == requested) {
            hardware = entry.hardwareSlot;
            ready = entry.simReady;
            matches++;
        }
    }
    return matches == 1;
}
// Dispatch one authenticated app request against the single retained session.
// Resolver/status remain diagnostic when compatibility fails; slot enumeration sends
// no APDUs. Opening validates the ISD-R AID and slot, transmission returns raw card
// bytes, and closing releases the session. networkLoop serializes these requests.
static Reply handle(const shjson::Request &q) {
    Operation op = q.op;
    if (op == Operation::Resolver) {
        if (compatible)
            ensureInterface();
        return Reply::success(shjson::ResolverReply{SHResolverReport(std::atomic_load(&firmware))});
    }
    if (op == Operation::Slots) {
        if (!compatible)
            return fail(
                @"Runtime compatibility checks did not pass. Open Firmware resolver for details. No card command was sent.");
        auto slots = availableSlots();
        return slots ? Reply::success(shjson::SlotsReply{*slots, phase.load()})
                     : fail(@"Card service is initializing. Try again later.");
    }
    if (op == Operation::Status) {
        int hw = 0;
        bool simReady = false;
        int requested = q.slot.value_or(logicalSlot);
        if (requested < 1) {
            auto entries = compatible ? availableSlots() : std::nullopt;
            requested = entries && !entries->empty() ? entries->front().logicalSlot : 0;
        }
        bool available = compatible && slotInfo(requested, hw, simReady);
        return Reply::success(shjson::StatusReply{compatible.load(), available, phase.load(),
                                                  requested, hw, simReady,
                                                  SHResolverReport(std::atomic_load(&firmware))});
    }
    if (!compatible)
        return fail(
            @"Runtime compatibility checks did not pass. Open Firmware resolver for details. No card command was sent.");
    if (op == Operation::Close)
        return closeSession()
                   ? Reply::success()
                   : fail(@"Channel close did not complete. Do not repeat the operation.");
    if (op == Operation::Open) {
        if (phase.load() != Phase::Idle)
            return fail(@"The card is busy.");
        if (!ensureInterface())
            return fail(@"Card service is initializing. Try again later.");
        NSData *d = SHUnhex(SHString(q.aid));
        if (![SHHex(d) isEqual:@"a0000005591010ffffffff8900000100"])
            return fail(@"Only the eUICC management application is supported.");
        int requested = q.slot.value_or(0);
        if (requested < 1)
            return fail(@"Select a physical SIM slot.");
        bool ready = false;
        int hardware = 0;
        if (!slotInfo(requested, hardware, ready))
            return fail(@"SIM slot not found. Wait for initialization and refresh.");
        logicalSlot = requested;
        slot = hardware;
        if (!ready) {
            // An inactive SIM may still expose ISD-R through the direct driver path.
            // Own the response vector here instead of borrowing the sender's vector.
            uintptr_t rawDriver = 0;
            auto fw = std::atomic_load(&firmware);
            if (!SHReadMemory((uintptr_t)iface.load() + fw->driverMember.load(), &rawDriver, 8))
                return fail(@"Card driver is not ready.");
            driver = (void *)rawDriver;
            if (!driver)
                return fail(@"Card driver is not ready.");
            directSession = true;
            directResponse = std::make_shared<Vec>();
            responseVector = directResponse.get();
            // Direct-path completion keeps a transmitted channel open, or marks an
            // opening/closing flow finished. Ignore callbacks while no direct session
            // is retained.
            retained = [](bool) {
                if (!directSession)
                    return;
                if (phase.load() == Phase::Transmitting) {
                    phase.store(Phase::Open);
                    signalDone();
                } else if (phase.load() == Phase::Opening || phase.load() == Phase::Closing) {
                    phase.store(Phase::Idle);
                    signalDone();
                }
            };
            Vec aid((uint8_t *)d.bytes, (uint8_t *)d.bytes + d.length);
            using Start = void (*)(void *, int, const Vec &, void (^)(int, uint8_t), const Fn &);
            phase.store(Phase::Opening);
            // Record the channel allocated by the direct-open callback and wake open.
            void (^opened)(int, uint8_t) = ^(int, uint8_t c) {
                channel = c;
                phase.store(Phase::Open);
                signalDone();
            };
            signedFn<Start>(location("driverStart"))(driver, hardware, aid, opened, retained);
            if (!awaitDone())
                return fail(@"Management channel open timed out.");
            if (phase.load() != Phase::Open) {
                retained = {};
                directResponse.reset();
                directSession = false;
                return fail(
                    @"Unable to open the card management application. Check that the card is inserted.");
            }
            return Reply::success(shjson::OpenReply{channel.load(), logicalSlot, slot});
        }
        // The normal sender accepts an AID, not raw APDU bytes. Its command/close
        // hooks capture and retain the session needed by later transmit requests.
        auto aid = std::make_shared<Vec>((uint8_t *)d.bytes, (uint8_t *)d.bytes + d.length);
        auto out = std::make_shared<Vec>();
        // Satisfy the sender's user-completion interface; hooks track bridge state.
        Fn cb = [](bool) {};
        using Sender =
            void (*)(void *, int, std::shared_ptr<Vec>, uint8_t, std::shared_ptr<Vec>, Fn);
        phase.store(Phase::Opening);
        signedFn<Sender>(location("sender"))(iface, logicalSlot, aid, 0xc0, out, cb);
        if (!awaitDone())
            return fail(@"Channel open timed out. Wait for service recovery.");
        if (phase.load() != Phase::Open)
            return fail(@"Unable to open ISD-R. Check that the card supports eUICC.");
        return Reply::success(shjson::OpenReply{channel.load(), logicalSlot, slot});
    }
    if (op == Operation::Transmit) {
        if (phase.load() != Phase::Open || !retained)
            return fail(@"The channel is not open.");
        NSData *d = SHUnhex(SHString(q.hex));
        if (d.length < 4 || d.length > 261)
            return fail(@"Invalid APDU length.");
        {
            std::lock_guard<std::mutex> g(mu);
            pending.assign((uint8_t *)d.bytes, (uint8_t *)d.bytes + d.length);
            raw.clear();
        }
        qmiError = 0;
        phase.store(Phase::Transmitting);
        // Trigger the existing command path with 0xc0; encodeHook replaces the final
        // outgoing bytes with pending, so the actual APDU can have another INS.
        commandOrig(driver, slot, channel, 0xc0, *responseVector, retained);
        if (!awaitDone())
            return fail(@"Card response timed out. Do not repeat the write.");
        std::lock_guard<std::mutex> g(mu);
        if (qmiError || raw.size() < 2)
            return fail([NSString stringWithFormat:@"Card transport failed (%d).", qmiError]);
        return Reply::success(shjson::TransmitReply{
            SHStdString(SHHex([NSData dataWithBytes:raw.data() length:raw.size()]))});
    }
    return fail(@"Unknown request.");
}
// Maintain the extension's loopback client connection to the foreground app.
// Authenticate both peers with the build pairing key, dispatch requests sequentially
// and echo their IDs. On disconnect, attempt session cleanup before reconnecting;
// an in-flight command is never replayed merely because its socket reply was lost.
static void networkLoop() {
    while (1) {
        @autoreleasepool {
            int fd = socket(AF_INET, SOCK_STREAM, 0);
            int yes = 1;
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof yes);
            struct timeval t = {5, 0};
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &t, sizeof t);
            setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &t, sizeof t);
            struct sockaddr_in a = {0};
            a.sin_len = sizeof a;
            a.sin_family = AF_INET;
            a.sin_port = htons(SH_PORT);
            a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
            if (connect(fd, (struct sockaddr *)&a, sizeof a)) {
                close(fd);
                sleep(2);
                continue;
            }
            auto hello = shjson::readMessage<shjson::Challenge>(fd);
            auto nonce = hello ? SHString(hello->nonce) : nil;
            bool authenticated =
                hello && shjson::writeMessage(
                             fd, shjson::Authentication{SHStdString(SHMAC(@"commcenter:", nonce))});
            auto peer =
                authenticated ? shjson::readMessage<shjson::Authentication>(fd) : std::nullopt;
            if (!peer || !SHSame(SHString(peer->mac), SHMAC(@"app:", nonce))) {
                close(fd);
                sleep(2);
                continue;
            }
            t.tv_sec = 120;
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &t, sizeof t);
            while (1) {
                @autoreleasepool {
                    auto request = shjson::readMessage<shjson::Request>(fd);
                    if (!request)
                        break;
                    auto reply = handle(*request);
                    reply.id = request->id;
                    if (!shjson::writeMessage(fd, reply))
                        break;
                }
            }
            close(fd);
            if (phase.load() == Phase::Open)
                closeSession();
            else if (phase.load() == Phase::Opening || phase.load() == Phase::Transmitting) {
                if (awaitDone() && phase.load() == Phase::Open)
                    closeSession();
            }
            sleep(2);
        }
    }
}
// Initialize the bridge once, then run IPC and runtime discovery on background queues.
// Install hooks only for a complete ABI-compatible plan and publish compatibility
// only after required original pointers exist. Live-object checks still happen on
// requests; starting the bridge or resolving firmware does not itself send an APDU.
extern "C" void estk_apdu_start(void) {
    static dispatch_once_t once;
    // Share one semaphore, network loop and hook installation across all callers.
    dispatch_once(&once, ^{
        event = dispatch_semaphore_create(0);
        // Keep socket waits off CommCenter's calling thread and the resolver queue.
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            networkLoop();
        });
        // Discover and install asynchronously; diagnostics can be served meanwhile.
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            @autoreleasepool {
                auto fw = SHResolveFirmware();
                std::atomic_store(&firmware, fw);
                if (!fw->abiCompatible || !fw->plan.complete)
                    return;
                resolved = fw->plan;
                fw->hookStage = 1;
                MSHookFunction((void *)fw->getter, (void *)serviceMapHook,
                               (void **)&serviceMapOrig);
                if (fw->mutableGetter && fw->mutableGetter != fw->getter)
                    MSHookFunction((void *)fw->mutableGetter, (void *)serviceMapMutableHook,
                                   (void **)&serviceMapMutableOrig);
                MSHookFunction((void *)location("driverCommand"), (void *)commandHook,
                               (void **)&commandOrig);
                MSHookFunction((void *)location("encoder"), (void *)encodeHook,
                               (void **)&encodeOrig);
                MSHookFunction((void *)location("response"), (void *)responseHook,
                               (void **)&responseOrig);
                MSHookFunction((void *)location("qmi"), (void *)qmiHook, (void **)&qmiOrig);
                MSHookFunction((void *)location("driverClose"), (void *)closeHook,
                               (void **)&closeOrig);
                MSHookFunction((void *)location("completion"), (void *)completionHook,
                               (void **)&completionOrig);
                bool installed = serviceMapOrig && commandOrig && encodeOrig && responseOrig &&
                                 qmiOrig && closeOrig && completionOrig &&
                                 (!fw->mutableGetter || fw->mutableGetter == fw->getter ||
                                  serviceMapMutableOrig);
                fw->hookStage = installed ? 2 : 3;
                compatible = installed;
            }
        });
    });
}
