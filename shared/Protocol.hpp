#pragma once
#include "JSON.hpp"
#include <variant>
#include <set>

namespace shjson {
// Stable numeric wire values shared by app status checks and the transport state machine.
enum class Phase : int { Idle = 0, Opening = 1, Open = 2, Transmitting = 3, Closing = 4 };
inline void to_json(JSON &j, Phase phase) { j = static_cast<int>(phase); }
inline bool read(const JSON &j, Phase &out) {
    int value;
    if (!read(j, value) || value < 0 || value > 4)
        return false;
    out = static_cast<Phase>(value);
    return true;
}
enum class Operation { Invalid, Resolver, Slots, Status, Open, Transmit, Close };
NLOHMANN_JSON_SERIALIZE_ENUM(Operation, {{Operation::Invalid, nullptr},
                                         {Operation::Resolver, "resolver"},
                                         {Operation::Slots, "slots"},
                                         {Operation::Status, "status"},
                                         {Operation::Open, "open"},
                                         {Operation::Transmit, "transmit"},
                                         {Operation::Close, "close"}})
inline bool read(const JSON &j, Operation &out) {
    if (!j.is_string())
        return false;
    from_json(j, out);
    return out != Operation::Invalid;
}
inline bool validHex(const std::string &value, size_t minimum, size_t maximum) {
    if (value.size() < minimum || value.size() > maximum || value.size() % 2)
        return false;
    return std::all_of(value.begin(), value.end(), [](unsigned char c) {
        return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
    });
}
struct Challenge {
    std::string nonce;
};
struct Authentication {
    std::string mac;
};
NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE_ONLY_SERIALIZE(Challenge, nonce)
NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE_ONLY_SERIALIZE(Authentication, mac)
inline bool read(const JSON &j, Challenge &out) {
    return SH_JSON_REQUIRED(nonce) && validHex(out.nonce, 64, 64);
}
inline bool read(const JSON &j, Authentication &out) {
    return SH_JSON_REQUIRED(mac) && validHex(out.mac, 64, 64);
}
struct Slot {
    int logicalSlot = 0, hardwareSlot = 0;
    bool simReady = false;
};
NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE_ONLY_SERIALIZE(Slot, logicalSlot, hardwareSlot, simReady)
inline bool read(const JSON &j, Slot &out) {
    return SH_JSON_REQUIRED(logicalSlot) && out.logicalSlot > 0 && SH_JSON_REQUIRED(hardwareSlot) &&
           out.hardwareSlot >= 1 && out.hardwareSlot <= 3 && SH_JSON_REQUIRED(simReady);
}
struct ResolverValue {
    std::variant<std::string, uint64_t> value;
    std::string source;
    std::optional<std::string> imageOffset;
};
inline void to_json(JSON &j, const ResolverValue &out) {
    j = {{"source", out.source}};
    std::visit([&](const auto &value) { j["value"] = value; }, out.value);
    if (out.imageOffset)
        j["imageOffset"] = *out.imageOffset;
}
inline bool read(const JSON &j, ResolverValue &out) {
    if (!j.is_object() || !j.contains("value"))
        return false;
    const auto &value = j.at("value");
    if (value.is_string())
        out.value = value.get_ref<const std::string &>();
    else {
        uint64_t number;
        if (!read(value, number))
            return false;
        out.value = number;
    }
    return SH_JSON_REQUIRED(source) && SH_JSON_OPTIONAL(imageOffset);
}
struct ResolverDetails {
    uint64_t analysisMilliseconds = 0, maxMeasuredFootprintBytes = 0, driverSymbolCount = 0;
    std::string commcenterUUID, driverUUID, registryImage;
    bool abiCompatible = false, compiledAbiCompatible = false, signaturesValidated = false;
    int hookStage = 0;
    uint64_t sharedPtrBytes = 0, functionBytes = 0;
    bool codeResolved = false;
    int objectDiscoveryStage = 0;
    std::string objectDiscovery;
    uint64_t driverCandidates = 0, hardwareCandidates = 0;
    bool objectLayoutResolved = false;
    std::map<std::string, ResolverValue> values;
    std::vector<std::string> errors;
    std::string policy;
};
NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE_ONLY_SERIALIZE(
    ResolverDetails, analysisMilliseconds, maxMeasuredFootprintBytes, driverSymbolCount,
    commcenterUUID, driverUUID, registryImage, abiCompatible, compiledAbiCompatible,
    signaturesValidated, hookStage, sharedPtrBytes, functionBytes, codeResolved,
    objectDiscoveryStage, objectDiscovery, driverCandidates, hardwareCandidates,
    objectLayoutResolved, values, errors, policy)
inline bool read(const JSON &j, ResolverDetails &out) {
    return SH_JSON_REQUIRED(analysisMilliseconds) && SH_JSON_REQUIRED(maxMeasuredFootprintBytes) &&
           SH_JSON_REQUIRED(driverSymbolCount) && SH_JSON_REQUIRED(commcenterUUID) &&
           SH_JSON_REQUIRED(driverUUID) && SH_JSON_REQUIRED(registryImage) &&
           SH_JSON_REQUIRED(abiCompatible) && SH_JSON_REQUIRED(compiledAbiCompatible) &&
           SH_JSON_REQUIRED(signaturesValidated) && SH_JSON_REQUIRED(hookStage) &&
           out.hookStage >= 0 && out.hookStage <= 3 && SH_JSON_REQUIRED(sharedPtrBytes) &&
           SH_JSON_REQUIRED(functionBytes) && SH_JSON_REQUIRED(codeResolved) &&
           SH_JSON_REQUIRED(objectDiscoveryStage) && SH_JSON_REQUIRED(objectDiscovery) &&
           SH_JSON_REQUIRED(driverCandidates) && SH_JSON_REQUIRED(hardwareCandidates) &&
           SH_JSON_REQUIRED(objectLayoutResolved) && SH_JSON_REQUIRED(values) &&
           SH_JSON_REQUIRED(errors) && SH_JSON_REQUIRED(policy);
}
struct ResolverReport {
    std::string state = "initializing", engine = "Module-scoped CoreSymbolication + Capstone";
    std::optional<ResolverDetails> details;
};
inline void to_json(JSON &j, const ResolverReport &out) {
    j = out.details ? JSON(*out.details) : JSON::object();
    j["state"] = out.state;
    j["engine"] = out.engine;
}
inline bool read(const JSON &j, ResolverReport &out) {
    if (!SH_JSON_REQUIRED(state) || !SH_JSON_REQUIRED(engine))
        return false;
    if (out.state == "initializing") {
        out.details.reset();
        return true;
    }
    ResolverDetails details;
    if (!read(j, details))
        return false;
    out.details = std::move(details);
    return true;
}
struct Request {
    std::string id;
    Operation op = Operation::Invalid;
    std::optional<int> slot;
    std::string aid, hex;
    static Request make(Operation op) {
        Request r;
        r.op = op;
        return r;
    }
    static Request open(int slot, std::string aid) {
        auto r = make(Operation::Open);
        r.slot = slot;
        r.aid = std::move(aid);
        return r;
    }
    static Request transmit(std::string hex) {
        auto r = make(Operation::Transmit);
        r.hex = std::move(hex);
        return r;
    }
    static Request status(int slot) {
        auto r = make(Operation::Status);
        r.slot = slot;
        return r;
    }
};
inline void to_json(JSON &j, const Request &out) {
    j = {{"id", out.id}, {"op", out.op}};
    if (out.slot)
        j["slot"] = *out.slot;
    if (out.op == Operation::Open)
        j["aid"] = out.aid;
    if (out.op == Operation::Transmit)
        j["hex"] = out.hex;
}
inline bool read(const JSON &j, Request &out) {
    if (!SH_JSON_REQUIRED(id) || out.id.empty() || out.id.size() > 128 ||
        out.id.find('\0') != std::string::npos || !SH_JSON_REQUIRED(op) || !SH_JSON_OPTIONAL(slot))
        return false;
    if (out.op == Operation::Open &&
        (!out.slot || *out.slot < 1 || !SH_JSON_REQUIRED(aid) || !validHex(out.aid, 2, 512)))
        return false;
    if (out.op == Operation::Status && out.slot && *out.slot < 1)
        return false;
    return out.op != Operation::Transmit || (SH_JSON_REQUIRED(hex) && validHex(out.hex, 8, 522));
}
struct ResolverReply {
    ResolverReport report;
};
struct SlotsReply {
    std::vector<Slot> slots;
    Phase phase = Phase::Idle;
};
struct StatusReply {
    bool compatible = false, ready = false;
    Phase phase = Phase::Idle;
    int logicalSlot = 0, hardwareSlot = 0;
    bool simReady = false;
    ResolverReport resolver;
};
struct OpenReply {
    int channel = -1, logicalSlot = 0, hardwareSlot = 0;
};
struct TransmitReply {
    std::string hex;
};
NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE_ONLY_SERIALIZE(ResolverReply, report)
NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE_ONLY_SERIALIZE(SlotsReply, slots, phase)
NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE_ONLY_SERIALIZE(StatusReply, compatible, ready, phase,
                                                  logicalSlot, hardwareSlot, simReady, resolver)
NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE_ONLY_SERIALIZE(OpenReply, channel, logicalSlot, hardwareSlot)
NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE_ONLY_SERIALIZE(TransmitReply, hex)
inline bool read(const JSON &j, ResolverReply &out) { return SH_JSON_REQUIRED(report); }
inline bool read(const JSON &j, SlotsReply &out) {
    if (!SH_JSON_REQUIRED(slots) || !SH_JSON_REQUIRED(phase) || out.slots.size() > 16)
        return false;
    std::set<int> logical, hardware;
    for (const auto &slot : out.slots)
        if (!logical.insert(slot.logicalSlot).second || !hardware.insert(slot.hardwareSlot).second)
            return false;
    return true;
}
inline bool read(const JSON &j, StatusReply &out) {
    return SH_JSON_REQUIRED(compatible) && SH_JSON_REQUIRED(ready) && SH_JSON_REQUIRED(phase) &&
           SH_JSON_REQUIRED(logicalSlot) && out.logicalSlot >= 0 &&
           SH_JSON_REQUIRED(hardwareSlot) && out.hardwareSlot >= 0 && out.hardwareSlot <= 3 &&
           SH_JSON_REQUIRED(simReady) && SH_JSON_REQUIRED(resolver) &&
           (!out.ready || (out.compatible && out.logicalSlot > 0 && out.hardwareSlot > 0));
}
inline bool read(const JSON &j, OpenReply &out) {
    return SH_JSON_REQUIRED(channel) && out.channel >= 0 && out.channel <= 19 &&
           SH_JSON_REQUIRED(logicalSlot) && out.logicalSlot > 0 && SH_JSON_REQUIRED(hardwareSlot) &&
           out.hardwareSlot >= 1 && out.hardwareSlot <= 3;
}
inline bool read(const JSON &j, TransmitReply &out) {
    return SH_JSON_REQUIRED(hex) && validHex(out.hex, 4, 131076);
}
using Payload =
    std::variant<std::monostate, ResolverReply, SlotsReply, StatusReply, OpenReply, TransmitReply>;
struct Reply {
    std::string id;
    bool ok = false;
    std::string error;
    Payload payload;
    template <class T> static Reply success(T body) {
        Reply r;
        r.ok = true;
        r.payload = std::move(body);
        return r;
    }
    static Reply success() {
        Reply r;
        r.ok = true;
        return r;
    }
    static Reply failure(std::string message) {
        Reply r;
        r.error = std::move(message);
        return r;
    }
};
template <class T> const T *body(const std::optional<Reply> &reply) {
    return reply && reply->ok ? std::get_if<T>(&reply->payload) : nullptr;
}
inline void to_json(JSON &j, const Reply &out) {
    j = {{"id", out.id}, {"ok", out.ok}};
    if (!out.ok) {
        j["error"] = out.error;
        return;
    }
    std::visit(
        [&](const auto &payload) {
            using T = std::decay_t<decltype(payload)>;
            if constexpr (!std::is_same_v<T, std::monostate>)
                j.update(JSON(payload));
        },
        out.payload);
}
inline bool readReply(const JSON &j, Operation op, Reply &out) {
    if (!SH_JSON_REQUIRED(id) || out.id.empty() || !SH_JSON_REQUIRED(ok))
        return false;
    out.payload = std::monostate{};
    out.error.clear();
    if (!out.ok)
        return SH_JSON_REQUIRED(error);
    switch (op) {
#define SH_REPLY_CASE(operation, type)                                                             \
    case Operation::operation: {                                                                   \
        type body;                                                                                 \
        if (!read(j, body))                                                                        \
            return false;                                                                          \
        out.payload = std::move(body);                                                             \
        return true;                                                                               \
    }
        SH_REPLY_CASE(Resolver, ResolverReply)
        SH_REPLY_CASE(Slots, SlotsReply)
        SH_REPLY_CASE(Status, StatusReply)
        SH_REPLY_CASE(Open, OpenReply)
        SH_REPLY_CASE(Transmit, TransmitReply)
#undef SH_REPLY_CASE
    case Operation::Close:
        out.payload = std::monostate{};
        return true;
    default:
        return false;
    }
}
struct Article {
    std::string id, title, summary, body;
};
NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE_ONLY_SERIALIZE(Article, id, title, summary, body)
inline bool read(const JSON &j, Article &out) {
    return SH_JSON_REQUIRED(id) && SH_JSON_REQUIRED(title) && SH_JSON_OPTIONAL(summary) &&
           SH_JSON_REQUIRED(body);
}
struct StatusCodeData {
    std::optional<std::string> subjectCode, reasonCode, subjectIdentifier, message;
};
NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE_ONLY_SERIALIZE(StatusCodeData, subjectCode, reasonCode,
                                                  subjectIdentifier, message)
inline bool read(const JSON &j, StatusCodeData &out) {
    return SH_JSON_OPTIONAL(subjectCode) && SH_JSON_OPTIONAL(reasonCode) &&
           SH_JSON_OPTIONAL(subjectIdentifier) && SH_JSON_OPTIONAL(message);
}
struct ExecutionStatus {
    std::string status;
    std::optional<StatusCodeData> statusCodeData;
};
NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE_ONLY_SERIALIZE(ExecutionStatus, status, statusCodeData)
inline bool read(const JSON &j, ExecutionStatus &out) {
    return SH_JSON_REQUIRED(status) && SH_JSON_OPTIONAL(statusCodeData);
}
struct HTTPHeader {
    std::optional<ExecutionStatus> functionExecutionStatus;
};
NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE_ONLY_SERIALIZE(HTTPHeader, functionExecutionStatus)
inline bool read(const JSON &j, HTTPHeader &out) {
    return SH_JSON_OPTIONAL(functionExecutionStatus);
}
struct HTTPEnvelope {
    std::optional<HTTPHeader> header;
};
inline bool read(const JSON &j, HTTPEnvelope &out) { return SH_JSON_OPTIONAL(header); }
} // namespace shjson
