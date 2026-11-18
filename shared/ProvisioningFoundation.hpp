#pragma once
#import <CoreTelephony/CTCellularPlanProvisioningRequest.h>
#include "JSONFoundation.h"
#include "Provisioning.hpp"

namespace shjson {
// Copy the native request before asynchronous transport. Do not log the fields.
inline bool fromNativeProvisioning(CTCellularPlanProvisioningRequest *request,
                                   ProvisioningRequest &out) {
    if (!request || ![request isKindOfClass:CTCellularPlanProvisioningRequest.class] ||
        ![request.address isKindOfClass:NSString.class])
        return false;
    NSMutableDictionary *fields = [@{@"address" : request.address} mutableCopy];
    NSArray *keys = @[ @"matchingID", @"confirmationCode", @"eid", @"iccid", @"oid" ];
    NSArray *values = @[
        request.matchingID ?: NSNull.null, request.confirmationCode ?: NSNull.null,
        request.EID ?: NSNull.null, request.ICCID ?: NSNull.null, request.OID ?: NSNull.null
    ];
    for (NSUInteger i = 0; i < keys.count; ++i)
        if (values[i] != NSNull.null)
            fields[keys[i]] = values[i];
    JSON json;
    return fromFoundation(fields, json) && read(json, out);
}
} // namespace shjson
