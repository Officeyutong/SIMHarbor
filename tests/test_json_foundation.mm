#import "../shared/JSONFoundation.h"
#include "../shared/Protocol.hpp"
#include <cstring>
extern "C" int SHJSONCheck(void) {
    @autoreleasepool {
        NSDictionary *fixture = @{
            @"boolean" : @YES,
            @"signed" : @(-7),
            @"unsigned" : @(UINT64_MAX),
            @"unicode" : @"English / 中文",
            @"null" : NSNull.null,
            @"array" : @[ @1, @"two" ]
        };
        shjson::JSON value;
        if (!shjson::fromFoundation(fixture, value) || !value["boolean"].is_boolean() ||
            !value["unsigned"].is_number_unsigned() ||
            value["unsigned"].get<uint64_t>() != UINT64_MAX)
            return 1;
        NSData *data = SHJSONData(fixture, YES);
        shjson::JSON decoded;
        if (!shjson::parseData(data, decoded) || ![shjson::foundation(decoded) isEqual:fixture])
            return 2;
        NSString *nul = SHString(std::string("a\0b", 3));
        if (SHStdString(nul) != std::string("a\0b", 3))
            return 3;
        shjson::Reply reply = shjson::Reply::success(
            shjson::SlotsReply{{{1, 1, true}, {2, 2, false}}, shjson::Phase::Idle});
        reply.id = "fixture";
        shjson::Reply received;
        if (!shjson::readReply(shjson::JSON(reply), shjson::Operation::Slots, received) ||
            !shjson::body<shjson::SlotsReply>(std::optional<shjson::Reply>(received)))
            return 4;
        if (SHJSONData(@{@"unsupported" : NSSet.set}) || SHJSONData(@{@"nonfinite" : @(NAN)}))
            return 5;
        printf(
            "PASS: nlohmann 3.12.0 Foundation conversion, boolean/integer fidelity, Unicode, embedded NUL, typed replies and invalid values (fixtures only)\n");
        return 0;
    }
}
