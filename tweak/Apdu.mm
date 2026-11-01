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
#import "RuntimeResolver.hpp"
using Vec = std::vector<uint8_t>;
using Fn = std::function<void(bool)>;
static std::shared_ptr<SHFirmware> firmware;
static shresolve::Plan resolved;
static uintptr_t location(const char *key) { return resolved.values.at(key); }
static std::atomic<void *> registryMap{nullptr};
static std::atomic<void *> iface{nullptr}, driver{nullptr};
static std::atomic<int> phase{0}, channel{-1}; // idle/opening/open/tx/closing
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
static void signalDone() { dispatch_semaphore_signal(event); }
static void commandHook(void *self, int s, uint8_t c, uint8_t ins, Vec &v, const Fn &cb) {
    if (phase == 1 && s == slot) {
        driver = self;
        channel = c;
        responseVector = &v;
    }
    commandOrig(self, s, c, ins, v, cb);
}
static void encodeHook(void *b, Vec &v) {
    encodeOrig(b, v);
    if (phase == 3 && *((uint8_t *)b + location("encoderChannel")) == channel) {
        std::lock_guard<std::mutex> g(mu);
        if (!pending.empty()) {
            v = pending;
            pending.clear();
        }
    }
}
static void responseHook(void *b, const Vec &v) {
    if (phase == 3 && *(int *)((char *)b + location("responseSlot")) == slot &&
        *((uint8_t *)b + location("responseChannel")) == channel) {
        std::lock_guard<std::mutex> g(mu);
        raw = v;
    }
    responseOrig(b, v);
}
static void qmiHook(void *b, void *r) {
    if (phase == 3)
        qmiError = *(int *)((char *)r + location("qmiError"));
    qmiOrig(b, r);
}
static void closeHook(void *self, int s, uint8_t c, bool ok, const Fn &cb) {
    int p = phase;
    if ((p == 1 || p == 3) && self == driver && s == slot && c == channel) {
        if (!retained)
            retained = cb;
        phase = 2;
        signalDone();
        return;
    }
    closeOrig(self, s, c, ok, cb);
}
static void completionHook(void *self, bool *ok) {
    completionOrig(self, ok);
    if (phase == 4) {
        phase = 0;
        signalDone();
    } else if (phase == 1) {
        phase = 0;
        signalDone();
    }
}
static void *(*serviceMapOrig)(void *);
static void *(*serviceMapMutableOrig)(void *);
static void *serviceMapHook(void *self) {
    void *m = serviceMapOrig(self);
    registryMap = m;
    return m;
}
static void *serviceMapMutableHook(void *self) {
    void *m = serviceMapMutableOrig(self);
    registryMap = m;
    return m;
}
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
template <typename T> static T signedFn(uintptr_t p) {
    return (T)ptrauth_sign_unauthenticated((void *)p, ptrauth_key_function_pointer, 0);
}
static bool awaitDone() {
    return dispatch_semaphore_wait(event, dispatch_time(DISPATCH_TIME_NOW, 25 * NSEC_PER_SEC)) == 0;
}
static bool closeSession() {
    if (phase == 0)
        return true;
    if (phase != 2 || !retained)
        return false;
    phase = 4;
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
static NSDictionary *fail(NSString *s) {
    return @{@"ok" : @NO, @"error" : s};
}
static NSArray *availableSlots() {
    if (!ensureInterface())
        return nil;
    auto fw = std::atomic_load(&firmware);
    uintptr_t span[2] = {};
    if (!SHReadMemory((uintptr_t)iface.load() + location("simVector"), span, sizeof span) ||
        !span[0] || span[1] < span[0] || (span[1] - span[0]) % sizeof(std::shared_ptr<void>) ||
        span[1] - span[0] > 16 * sizeof(std::shared_ptr<void>))
        return nil;
    std::vector<shslots::Slot> raw, assigned;
    for (uintptr_t p = span[0]; p < span[1]; p += sizeof(std::shared_ptr<void>)) {
        uintptr_t si = 0;
        int logical = 0, hardware = 0;
        if (!SHReadMemory(p, &si, 8) || !si ||
            !SHReadMemory(si + location("logicalSlot"), &logical, 4))
            return nil;
        if (logical <= 0) {
            raw.push_back({logical, 0, false});
            continue;
        }
        if (!SHReadMemory(si + fw->hardwareSlot.load(), &hardware, 4))
            return nil;
        using State = int (*)(void *);
        using Ready = bool (*)(int);
        bool ready =
            signedFn<Ready>(location("isReady"))(signedFn<State>(location("simState"))((void *)si));
        raw.push_back({logical, hardware, ready});
    }
    if (!shslots::assigned(raw, assigned))
        return nil;
    NSMutableArray *result = [NSMutableArray array];
    for (const auto &entry : assigned)
        [result addObject:@{
            @"logicalSlot" : @(entry.logical),
            @"hardwareSlot" : @(entry.hardware),
            @"simReady" : @(entry.ready)
        }];
    return result;
}
static bool slotInfo(int requested, int &hardware, bool &ready) {
    int matches = 0;
    for (NSDictionary *entry in availableSlots()) {
        if ([entry[@"logicalSlot"] intValue] == requested) {
            hardware = [entry[@"hardwareSlot"] intValue];
            ready = [entry[@"simReady"] boolValue];
            matches++;
        }
    }
    return matches == 1;
}
static NSDictionary *handle(NSDictionary *q) {
    NSString *op = q[@"op"];
    if ([op isEqual:@"resolver"]) {
        if (compatible)
            ensureInterface();
        return @{@"ok" : @YES, @"report" : SHResolverReport(std::atomic_load(&firmware))};
    }
    if ([op isEqual:@"slots"]) {
        if (!compatible)
            return fail(
                @"Runtime compatibility checks did not pass. Open Firmware resolver for details. No card command was sent.");
        NSArray *slots = availableSlots();
        return slots
                   ? @{@"ok" : @YES,
                       @"slots" : slots,
                       @"phase" : @(phase.load())}
                   : fail(@"Card service is initializing. Try again later.");
    }
    if ([op isEqual:@"status"]) {
        int hw = 0;
        bool simReady = false;
        int requested =
            [q[@"slot"] isKindOfClass:NSNumber.class] ? [q[@"slot"] intValue] : logicalSlot;
        if (requested < 1) {
            NSArray *entries = compatible ? availableSlots() : nil;
            requested = [entries.firstObject[@"logicalSlot"] intValue];
        }
        bool available = compatible && slotInfo(requested, hw, simReady);
        return @{
            @"ok" : @YES,
            @"compatible" : @(compatible.load()),
            @"ready" : @(available),
            @"phase" : @(phase.load()),
            @"logicalSlot" : @(requested),
            @"hardwareSlot" : @(hw),
            @"simReady" : @(simReady),
            @"resolver" : SHResolverReport(std::atomic_load(&firmware))
        };
    }
    if (!compatible)
        return fail(
            @"Runtime compatibility checks did not pass. Open Firmware resolver for details. No card command was sent.");
    if ([op isEqual:@"close"])
        return closeSession()
                   ? @{@"ok" : @YES}
                   : fail(@"Channel close did not complete. Do not repeat the operation.");
    if ([op isEqual:@"open"]) {
        if (phase != 0)
            return fail(@"The card is busy.");
        if (!ensureInterface())
            return fail(@"Card service is initializing. Try again later.");
        NSData *d = SHUnhex(q[@"aid"]);
        if (![SHHex(d) isEqual:@"a0000005591010ffffffff8900000100"])
            return fail(@"Only the eUICC management application is supported.");
        int requested = [q[@"slot"] intValue];
        if (![q[@"slot"] isKindOfClass:NSNumber.class] || requested < 1)
            return fail(@"Select a physical SIM slot.");
        bool ready = false;
        int hardware = 0;
        if (!slotInfo(requested, hardware, ready))
            return fail(@"SIM slot not found. Wait for initialization and refresh.");
        logicalSlot = requested;
        slot = hardware;
        if (!ready) {
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
            retained = [](bool) {
                if (!directSession)
                    return;
                if (phase == 3) {
                    phase = 2;
                    signalDone();
                } else if (phase == 1 || phase == 4) {
                    phase = 0;
                    signalDone();
                }
            };
            Vec aid((uint8_t *)d.bytes, (uint8_t *)d.bytes + d.length);
            using Start = void (*)(void *, int, const Vec &, void (^)(int, uint8_t), const Fn &);
            phase = 1;
            void (^opened)(int, uint8_t) = ^(int, uint8_t c) {
                channel = c;
                phase = 2;
                signalDone();
            };
            signedFn<Start>(location("driverStart"))(driver, hardware, aid, opened, retained);
            if (!awaitDone())
                return fail(@"Management channel open timed out.");
            if (phase != 2) {
                retained = {};
                directResponse.reset();
                directSession = false;
                return fail(
                    @"Unable to open the card management application. Check that the card is inserted.");
            }
            return @{
                @"ok" : @YES,
                @"channel" : @(channel.load()),
                @"logicalSlot" : @(logicalSlot),
                @"hardwareSlot" : @(slot)
            };
        }
        auto aid = std::make_shared<Vec>((uint8_t *)d.bytes, (uint8_t *)d.bytes + d.length);
        auto out = std::make_shared<Vec>();
        Fn cb = [](bool) {};
        using Sender =
            void (*)(void *, int, std::shared_ptr<Vec>, uint8_t, std::shared_ptr<Vec>, Fn);
        phase = 1;
        signedFn<Sender>(location("sender"))(iface, logicalSlot, aid, 0xc0, out, cb);
        if (!awaitDone())
            return fail(@"Channel open timed out. Wait for service recovery.");
        if (phase != 2)
            return fail(@"Unable to open ISD-R. Check that the card supports eUICC.");
        return @{
            @"ok" : @YES,
            @"channel" : @(channel.load()),
            @"logicalSlot" : @(logicalSlot),
            @"hardwareSlot" : @(slot)
        };
    }
    if ([op isEqual:@"transmit"]) {
        if (phase != 2 || !retained)
            return fail(@"The channel is not open.");
        NSData *d = SHUnhex(q[@"hex"]);
        if (d.length < 4 || d.length > 261)
            return fail(@"Invalid APDU length.");
        {
            std::lock_guard<std::mutex> g(mu);
            pending.assign((uint8_t *)d.bytes, (uint8_t *)d.bytes + d.length);
            raw.clear();
        }
        qmiError = 0;
        phase = 3;
        commandOrig(driver, slot, channel, 0xc0, *responseVector, retained);
        if (!awaitDone())
            return fail(@"Card response timed out. Do not repeat the write.");
        std::lock_guard<std::mutex> g(mu);
        if (qmiError || raw.size() < 2)
            return fail([NSString stringWithFormat:@"Card transport failed (%d).", qmiError]);
        return @{@"ok" : @YES, @"hex" : SHHex([NSData dataWithBytes:raw.data() length:raw.size()])};
    }
    return fail(@"Unknown request.");
}
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
            NSDictionary *hello = SHRead(fd);
            NSString *nonce = hello[@"nonce"];
            if (![nonce isKindOfClass:NSString.class] || nonce.length != 64 ||
                !SHWrite(fd, @{@"mac" : SHMAC(@"commcenter:", nonce)}) ||
                !SHSame(SHRead(fd)[@"mac"], SHMAC(@"app:", nonce))) {
                close(fd);
                sleep(2);
                continue;
            }
            t.tv_sec = 120;
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &t, sizeof t);
            while (1) {
                @autoreleasepool {
                    NSDictionary *q = SHRead(fd);
                    if (!q)
                        break;
                    NSDictionary *r = handle(q);
                    NSMutableDictionary *reply = [r mutableCopy];
                    reply[@"id"] = q[@"id"] ?: @"";
                    if (!SHWrite(fd, reply))
                        break;
                }
            }
            close(fd);
            if (phase == 2)
                closeSession();
            else if (phase == 1 || phase == 3) {
                if (awaitDone() && phase == 2)
                    closeSession();
            }
            sleep(2);
        }
    }
}
extern "C" void estk_apdu_start(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        event = dispatch_semaphore_create(0);
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            networkLoop();
        });
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
