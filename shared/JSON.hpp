#pragma once
#include "../vendor/nlohmann/json.hpp"
#include <limits>
#include <map>
#include <set>
#include <optional>
#include <string>
#include <vector>

namespace shjson {
using JSON = nlohmann::json;
// Validate before get/get_ref: malformed input is rejected without exception unwinding.
inline bool read(const JSON &j, std::string &out) {
    if (!j.is_string())
        return false;
    out = j.get_ref<const std::string &>();
    return true;
}
inline bool read(const JSON &j, bool &out) {
    if (!j.is_boolean())
        return false;
    out = j.get<bool>();
    return true;
}
inline bool read(const JSON &j, int &out) {
    if (j.is_number_unsigned()) {
        auto n = j.get<uint64_t>();
        if (n > uint64_t(std::numeric_limits<int>::max()))
            return false;
        out = int(n);
        return true;
    }
    if (!j.is_number_integer())
        return false;
    auto n = j.get<int64_t>();
    if (n < std::numeric_limits<int>::min() || n > std::numeric_limits<int>::max())
        return false;
    out = int(n);
    return true;
}
inline bool read(const JSON &j, uint64_t &out) {
    if (!j.is_number_integer() || (!j.is_number_unsigned() && j.get<int64_t>() < 0))
        return false;
    out = j.get<uint64_t>();
    return true;
}
inline bool read(const JSON &j, JSON &out) {
    out = j;
    return true;
}
template <class T> bool read(const JSON &j, std::optional<T> &out) {
    if (j.is_null()) {
        out.reset();
        return true;
    }
    T value{};
    if (!read(j, value))
        return false;
    out = std::move(value);
    return true;
}
template <class T> bool read(const JSON &j, std::vector<T> &out) {
    if (!j.is_array())
        return false;
    std::vector<T> values;
    values.reserve(j.size());
    for (const auto &element : j) {
        T value{};
        if (!read(element, value))
            return false;
        values.push_back(std::move(value));
    }
    out = std::move(values);
    return true;
}
template <class T> bool read(const JSON &j, std::map<std::string, T> &out) {
    if (!j.is_object())
        return false;
    std::map<std::string, T> values;
    for (const auto &element : j.items()) {
        T value{};
        if (!read(element.value(), value))
            return false;
        values.emplace(element.key(), std::move(value));
    }
    out = std::move(values);
    return true;
}
template <class T> bool field(const JSON &j, const char *key, T &out, bool required = true) {
    if (!j.is_object())
        return false;
    auto item = j.find(key);
    if (item == j.end()) {
        if (required)
            return false;
        out = T{};
        return true;
    }
    return read(*item, out);
}
// Bound nesting before invoking the DOM parser, including inside discarded/unknown fields.
inline bool parse(const char *data, size_t size, JSON &out, size_t maximum = 262143) {
    if (!data || size > maximum)
        return false;
    unsigned depth = 0;
    bool quoted = false, escaped = false;
    for (size_t i = 0; i < size; ++i) {
        char c = data[i];
        if (quoted) {
            if (escaped)
                escaped = false;
            else if (c == '\\')
                escaped = true;
            else if (c == '"')
                quoted = false;
        } else if (c == '"')
            quoted = true;
        else if (c == '{' || c == '[') {
            if (++depth > 64)
                return false;
        } else if (c == '}' || c == ']') {
            if (!depth)
                return false;
            --depth;
        }
    }
    if (quoted || depth)
        return false;
    bool duplicate = false;
    std::vector<std::set<std::string>> keys;
    auto callback = [&](int, JSON::parse_event_t event, JSON &parsed) {
        if (event == JSON::parse_event_t::object_start)
            keys.emplace_back();
        else if (event == JSON::parse_event_t::key &&
                 !keys.back().insert(parsed.get_ref<const std::string &>()).second)
            duplicate = true;
        else if (event == JSON::parse_event_t::object_end)
            keys.pop_back();
        return true;
    };
    auto value = JSON::parse(data, data + size, callback, false);
    if (value.is_discarded() || duplicate)
        return false;
    out = std::move(value);
    return true;
}
inline std::string dump(const JSON &j, bool pretty = false) {
    return j.dump(pretty ? 2 : -1, ' ', false, JSON::error_handler_t::replace);
}
#define SH_JSON_REQUIRED(member) ::shjson::field(j, #member, out.member)
#define SH_JSON_OPTIONAL(member) ::shjson::field(j, #member, out.member, false)
} // namespace shjson
