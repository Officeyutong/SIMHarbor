#pragma once
#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <string>
#include <vector>

// Extract only the registeredID inside the X.509 subjectAltName extension.
// This is an identity comparison, not certificate signature verification.
namespace shoid {
struct View {
    const uint8_t *data;
    size_t size;
};
struct Node {
    uint8_t tag;
    View value;
};
inline bool take(View &v, Node &out) {
    if (v.size < 2 || (v.data[0] & 31) == 31)
        return false;
    uint8_t tag = v.data[0], first = v.data[1];
    size_t head = 2, n = 0;
    if (!(first & 128))
        n = first;
    else {
        size_t count = first & 127;
        if (!count || count > sizeof(size_t) || count > v.size - head || v.data[head] == 0)
            return false;
        for (size_t i = 0; i < count; ++i) {
            if (n > (std::numeric_limits<size_t>::max() >> 8))
                return false;
            n = (n << 8) | v.data[head++];
        }
        if (n < 128)
            return false;
    }
    if (n > v.size - head)
        return false;
    out = {tag, {v.data + head, n}};
    v.data += head + n;
    v.size -= head + n;
    return true;
}
inline bool one(View v, uint8_t tag, View &content) {
    Node n{};
    if (!take(v, n) || n.tag != tag || v.size)
        return false;
    content = n.value;
    return true;
}
inline bool expectedOID(const std::string &text, std::vector<uint8_t> &out) {
    std::vector<uint64_t> arcs;
    size_t start = 0;
    while (start < text.size()) {
        size_t end = text.find('.', start);
        if (end == std::string::npos)
            end = text.size();
        if (end == start || (end - start > 1 && text[start] == '0'))
            return false;
        uint64_t x = 0;
        for (size_t i = start; i < end; ++i) {
            if (text[i] < '0' || text[i] > '9')
                return false;
            unsigned d = unsigned(text[i] - '0');
            if (x > (std::numeric_limits<uint64_t>::max() - d) / 10)
                return false;
            x = x * 10 + d;
        }
        arcs.push_back(x);
        if (arcs.size() > 64)
            return false;
        if (end == text.size())
            break;
        start = end + 1;
        if (start == text.size())
            return false;
    }
    if (arcs.size() < 2 || arcs[0] > 2 || (arcs[0] < 2 && arcs[1] > 39) ||
        arcs[1] > std::numeric_limits<uint64_t>::max() - 80)
        return false;
    auto append = [&](uint64_t x) {
        uint8_t buf[10];
        size_t n = 0;
        do {
            buf[n++] = uint8_t(x & 127);
            x >>= 7;
        } while (x);
        while (n) {
            --n;
            out.push_back(buf[n] | (n ? 128 : 0));
        }
    };
    out.clear();
    append(arcs[0] * 40 + arcs[1]);
    for (size_t i = 2; i < arcs.size(); ++i)
        append(arcs[i]);
    return true;
}
inline bool matchesCertificate(View certificate, const std::string &expected) {
    std::vector<uint8_t> oid;
    if (!expectedOID(expected, oid) || certificate.size > 65536)
        return false;
    View outer{};
    if (!one(certificate, 0x30, outer))
        return false;
    Node tbs{}, signatureAlgorithm{}, signature{};
    if (!take(outer, tbs) || tbs.tag != 0x30 || !take(outer, signatureAlgorithm) ||
        signatureAlgorithm.tag != 0x30 || !take(outer, signature) || signature.tag != 0x03 ||
        outer.size)
        return false;
    View body = tbs.value;
    Node n{};
    if (!take(body, n))
        return false;
    if (n.tag == 0xa0 && !take(body, n))
        return false;
    if (n.tag != 0x02)
        return false;
    for (unsigned i = 0; i < 5; i++)
        if (!take(body, n) || n.tag != 0x30)
            return false;
    bool extensionsSeen = false, sanSeen = false, matched = false;
    while (body.size) {
        if (!take(body, n))
            return false;
        if (n.tag == 0x81 || n.tag == 0x82)
            continue;
        if (n.tag != 0xa3 || extensionsSeen)
            return false;
        extensionsSeen = true;
        View extensions{};
        if (!one(n.value, 0x30, extensions))
            return false;
        while (extensions.size) {
            Node ext{}, id{}, value{};
            if (!take(extensions, ext) || ext.tag != 0x30)
                return false;
            View parts = ext.value;
            if (!take(parts, id) || id.tag != 0x06 || !take(parts, value))
                return false;
            if (value.tag == 0x01 && !take(parts, value))
                return false;
            if (value.tag != 0x04 || parts.size)
                return false;
            static const uint8_t sanOID[] = {0x55, 0x1d, 0x11};
            if (id.value.size != sizeof sanOID ||
                !std::equal(id.value.data, id.value.data + id.value.size, sanOID))
                continue;
            if (sanSeen)
                return false;
            sanSeen = true;
            View names{};
            if (!one(value.value, 0x30, names))
                return false;
            unsigned registered = 0;
            while (names.size) {
                Node name{};
                if (!take(names, name))
                    return false;
                if (name.tag == 0x88) {
                    ++registered;
                    matched = name.value.size == oid.size() &&
                              std::equal(oid.begin(), oid.end(), name.value.data);
                }
            }
            if (registered != 1)
                return false;
        }
    }
    return extensionsSeen && sanSeen && matched;
}
} // namespace shoid
