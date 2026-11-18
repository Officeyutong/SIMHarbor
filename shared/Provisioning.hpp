#pragma once
#include "JSON.hpp"

namespace shjson {
// Native installation fields; a missing optional field remains absent on the wire.
struct ProvisioningRequest {
    std::string address;
    std::optional<std::string> matchingID, confirmationCode, eid, iccid, oid;
};
inline void to_json(JSON &j, const ProvisioningRequest &request) {
    j = {{"address", request.address}};
    if (request.matchingID)
        j["matchingID"] = *request.matchingID;
    if (request.confirmationCode)
        j["confirmationCode"] = *request.confirmationCode;
    if (request.eid)
        j["eid"] = *request.eid;
    if (request.iccid)
        j["iccid"] = *request.iccid;
    if (request.oid)
        j["oid"] = *request.oid;
}
inline bool read(const JSON &j, ProvisioningRequest &out) {
    ProvisioningRequest parsed;
    if (!field(j, "address", parsed.address) || parsed.address.empty() ||
        parsed.address.size() > 253 ||
        parsed.address.find_first_of("/:@?# $\r\n\t") != std::string::npos ||
        parsed.address.find('\0') != std::string::npos ||
        !field(j, "matchingID", parsed.matchingID, false) ||
        !field(j, "confirmationCode", parsed.confirmationCode, false) ||
        !field(j, "eid", parsed.eid, false) || !field(j, "iccid", parsed.iccid, false) ||
        !field(j, "oid", parsed.oid, false))
        return false;
    for (const auto *value :
         {&parsed.matchingID, &parsed.confirmationCode, &parsed.eid, &parsed.iccid, &parsed.oid})
        if (*value && ((*value)->empty() || (*value)->size() > 512 ||
                       (*value)->find('\0') != std::string::npos))
            return false;
    out = std::move(parsed);
    return true;
}
} // namespace shjson
