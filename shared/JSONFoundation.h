#pragma once
#import <Foundation/Foundation.h>
#include "JSON.hpp"
#include <cmath>

inline NSString *SHString(const std::string &value) {
    return [[NSString alloc] initWithBytes:value.data()
                                    length:value.size()
                                  encoding:NSUTF8StringEncoding];
}
inline std::string SHStdString(NSString *value) {
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    return data.length ? std::string(static_cast<const char *>(data.bytes), data.length)
                       : std::string{};
}
namespace shjson {
// UIKit/NSError models stay Foundation objects; JSON encoding always uses nlohmann.
inline bool fromFoundation(id value, JSON &out, unsigned depth = 0) {
    if (depth > 64 || !value)
        return false;
    if (value == NSNull.null) {
        out = nullptr;
        return true;
    }
    if ([value isKindOfClass:NSString.class]) {
        out = SHStdString(value);
        return true;
    }
    if ([value isKindOfClass:NSNumber.class]) {
        if (CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID())
            out = [value boolValue];
        else if (strchr("CSILQ", [value objCType][0]))
            out = [value unsignedLongLongValue];
        else if (strchr("csilq", [value objCType][0]))
            out = [value longLongValue];
        else {
            double n = [value doubleValue];
            if (!std::isfinite(n))
                return false;
            out = n;
        }
        return true;
    }
    if ([value isKindOfClass:NSArray.class]) {
        out = JSON::array();
        for (id item in value) {
            JSON child;
            if (!fromFoundation(item, child, depth + 1))
                return false;
            out.push_back(std::move(child));
        }
        return true;
    }
    if ([value isKindOfClass:NSDictionary.class]) {
        out = JSON::object();
        for (id key in value) {
            if (![key isKindOfClass:NSString.class])
                return false;
            JSON child;
            if (!fromFoundation(value[key], child, depth + 1))
                return false;
            out[SHStdString(key)] = std::move(child);
        }
        return true;
    }
    return false;
}
inline id foundation(const JSON &value) {
    if (value.is_null())
        return NSNull.null;
    if (value.is_string())
        return SHString(value.get_ref<const std::string &>());
    if (value.is_boolean())
        return @(value.get<bool>());
    if (value.is_number_unsigned())
        return @(value.get<uint64_t>());
    if (value.is_number_integer())
        return @(value.get<int64_t>());
    if (value.is_number_float())
        return @(value.get<double>());
    if (value.is_array()) {
        NSMutableArray *items = [NSMutableArray array];
        for (const auto &item : value)
            [items addObject:foundation(item)];
        return items;
    }
    if (value.is_object()) {
        NSMutableDictionary *items = [NSMutableDictionary dictionary];
        for (const auto &item : value.items())
            items[SHString(item.key())] = foundation(item.value());
        return items;
    }
    return nil;
}
inline bool parseData(NSData *data, JSON &out, size_t maximum = 262143) {
    return parse(static_cast<const char *>(data.bytes), data.length, out, maximum);
}
} // namespace shjson
inline NSData *SHJSONData(id object, BOOL pretty = NO) {
    shjson::JSON value;
    if (!shjson::fromFoundation(object, value))
        return nil;
    auto text = shjson::dump(value, pretty);
    return [NSData dataWithBytes:text.data() length:text.size()];
}
