#include "../tweak/ResolverCore.hpp"
#include "../shared/Firmware.h"
#include "../vendor/cjson/cJSON.h"
#include <fstream>
#include <algorithm>
#include <iostream>
#include <cstring>
#include <cassert>
#include <memory>
using namespace shresolve;
struct Buffer {
    Address address;
    std::vector<uint8_t> bytes;
};
static std::string text(const std::string &p) {
    std::ifstream f(p, std::ios::binary);
    return std::string(std::istreambuf_iterator<char>(f), {});
}
static Address number(cJSON *j, const char *k) {
    return std::stoull(cJSON_GetObjectItem(j, k)->valuestring, nullptr, 16);
}
int main(int argc, char **argv) {
    assert(SHRuntimeAbiLayoutCompatible(8, 16, 32));
    assert(!SHRuntimeAbiLayoutCompatible(4, 16, 32));
    assert(!SHRuntimeAbiLayoutCompatible(8, 24, 32));
    assert(!SHRuntimeAbiLayoutCompatible(8, 16, 48));
    std::cout << std::unitbuf;
    assert(argc == 2);
    std::string root = argv[1];
    auto json = text(root + "/image.json");
    auto meta =
        std::unique_ptr<cJSON, decltype(&cJSON_Delete)>(cJSON_Parse(json.c_str()), cJSON_Delete);
    assert(meta);
    std::vector<Buffer> buffers;
    auto clean = [](Address a) { return a & 0x7fffffffffULL; };
    auto reader = [&](Address a, void *p, size_t n) {
        for (auto &b : buffers)
            if (a >= b.address && n <= b.bytes.size() && a - b.address <= b.bytes.size() - n) {
                memcpy(p, b.bytes.data() + a - b.address, n);
                return true;
            }
        return false;
    };
    auto image = [&](const char *key) {
        Image out;
        auto *j = cJSON_GetObjectItem(meta.get(), key);
        out.name = key;
        out.base = number(j, "base");
        out.read = reader;
        out.clean = clean;
        cJSON *q;
        cJSON_ArrayForEach(q, cJSON_GetObjectItem(j, "ranges")) {
            Address a = number(q, "address");
            auto data = text(root + "/" + cJSON_GetObjectItem(q, "file")->valuestring);
            buffers.push_back({a, std::vector<uint8_t>(data.begin(), data.end())});
            out.ranges.push_back({a, data.size(), false});
            cJSON *s;
            cJSON_ArrayForEach(s, cJSON_GetObjectItem(q, "sections")) {
                unsigned flags = (unsigned)cJSON_GetObjectItem(s, "flags")->valuedouble;
                if (flags & 0x80000400u)
                    out.ranges.push_back({number(s, "address"),
                                          (size_t)cJSON_GetObjectItem(s, "size")->valuedouble,
                                          true});
            }
        }
        cJSON_ArrayForEach(q, cJSON_GetObjectItem(j, "functions"))
            out.functions.push_back(std::stoull(q->valuestring, nullptr, 16));
        return out;
    };
    Image cc = image("cc"), dr = image("driver");
    cJSON *q;
    cJSON_ArrayForEach(q, cJSON_GetObjectItem(meta.get(), "patches")) {
        Address a = number(q, "address");
        std::string h = cJSON_GetObjectItem(q, "hex")->valuestring;
        for (auto &b : buffers)
            if (a >= b.address && a + 16 <= b.address + b.bytes.size())
                for (int i = 0; i < 16; i++)
                    b.bytes[a - b.address + i] = std::stoi(h.substr(i * 2, 2), nullptr, 16);
    }
    // Main executable's original text is available separately, before any test hooks.
    auto original = text(root + "/../CommCenter.device");
    if (original.size() > 0x803a84)
        for (auto &b : buffers)
            if (cc.base + 0x803a74 >= b.address && cc.base + 0x803a84 <= b.address + b.bytes.size())
                memcpy(b.bytes.data() + cc.base + 0x803a74 - b.address, original.data() + 0x803a74,
                       16);
    std::vector<Symbol> symbols;
    cJSON_ArrayForEach(q, cJSON_GetObjectItem(meta.get(), "symbols"))
        symbols.push_back({number(q, "address"), cJSON_GetObjectItem(q, "name")->valuestring});
    auto p = resolve(cc, dr, symbols, number(meta.get(), "ready"));
    for (auto &x : p.values)
        std::cout << x.first << "=" << std::hex << x.second << std::dec << " ["
                  << p.sources[x.first] << "]\n";
    for (auto &e : p.errors)
        std::cout << "ERROR " << e << "\n";
    assert(p.complete);
    assert(p.signaturesValidated);
    // Firmware identities are diagnostics, not permission to use a matching plan.
    Image unseenCC = cc, unseenDriver = dr;
    unseenCC.uuid = "previously-unseen-commcenter";
    unseenDriver.uuid = "previously-unseen-driver";
    auto unseen = resolve(unseenCC, unseenDriver, symbols, number(meta.get(), "ready"));
    assert(unseen.complete && unseen.signaturesValidated && unseen.values == p.values);
    auto wrongSignature = symbols;
    for (auto &s : wrongSignature) {
        if (s.name.find("block in") == std::string::npos &&
            s.name.find("sendSimApdu_command(") != std::string::npos) {
            auto at = s.name.find("function<void (bool)>");
            assert(at != std::string::npos);
            s.name.replace(at, strlen("function<void (bool)>"), "function<void (int)>");
        }
    }
    auto wrong = resolve(cc, dr, wrongSignature, number(meta.get(), "ready"));
    assert(!wrong.complete && !wrong.signaturesValidated && !wrong.errors.empty());
    assert(p.values.at("sender") == cc.base + 0x7e4568);
    assert(p.values.at("simState") == cc.base + 0x11c3c10);
    assert(p.values.at("controllerVtable") == cc.base + 0x175fb78);
    assert(p.values.at("completion") == cc.base + 0x803a74);
    assert(p.values.at("simVector") == 0xa8 && p.values.at("logicalSlot") == 0x24);
    assert(p.simContainer && p.simContainer->storage == shlayout::EntryStorage::Indirect &&
           p.simContainer->stride == 16 && p.simContainer->pointee == 0);
    auto strippedCommand = symbols;
    strippedCommand.erase(std::remove_if(strippedCommand.begin(), strippedCommand.end(),
                                         [](const auto &s) {
                                             return s.name.find("block in") == std::string::npos &&
                                                    s.name.find("sendSimApdu_command(") !=
                                                        std::string::npos;
                                         }),
                          strippedCommand.end());
    auto stripped = resolve(cc, dr, strippedCommand, number(meta.get(), "ready"));
    // An out-of-line command must not be misidentified as an inlined continuation.
    assert(!stripped.complete);

    assert(p.values.at("driverStart") == dr.base + 0x168858);
    assert(p.values.at("driverCommand") == dr.base + 0x1693e0);
    assert(p.values.at("driverClose") == dr.base + 0x16a7a4);
    assert(p.values.at("encoder") == dr.base + 0x169bb8);
    assert(p.values.at("response") == dr.base + 0x16a43c);
    assert(p.values.at("qmi") == dr.base + 0x16a214);
    assert(p.values.at("encoderChannel") == 0x30 && p.values.at("responseSlot") == 0x30 &&
           p.values.at("responseChannel") == 0x34 && p.values.at("qmiError") == 4);
    auto bad = symbols;
    bad.erase(std::remove_if(
                  bad.begin(), bad.end(),
                  [](auto &s) { return s.name.find("sendSimApdu_start(") != std::string::npos; }),
              bad.end());
    assert(!resolve(cc, dr, bad, number(meta.get(), "ready")).complete);

    assert(!resolve(cc, dr, {}, number(meta.get(), "ready")).complete);
    assert(!resolve(cc, dr, symbols, 0).complete);
    auto ambiguous = symbols;
    auto entry = *std::find_if(symbols.begin(), symbols.end(), [](auto &s) {
        return s.name.find("sendSimApdu_start(") != std::string::npos &&
               s.name.find("block in") == std::string::npos;
    });
    entry.address = p.values.at("driverClose");
    ambiguous.push_back(entry);
    assert(!resolve(cc, dr, ambiguous, number(meta.get(), "ready")).complete);
    auto interior = symbols;
    for (auto &s : interior)
        if (s.name.find("sendSimApdu_start(") != std::string::npos)
            s.address += 4;
    assert(!resolve(cc, dr, interior, number(meta.get(), "ready")).complete);
    Image missing = cc;
    missing.read = [](Address, void *, size_t) { return false; };
    assert(!resolve(missing, dr, symbols, number(meta.get(), "ready")).complete);
    // Rebase code and all recorded image pointers by a new page-aligned ASLR slide.
    const Address slide = 0x20000000, ready = number(meta.get(), "ready");
    for (auto &b : buffers) {
        for (size_t i = 0; i + 8 <= b.bytes.size(); i += 8) {
            Address raw = 0;
            memcpy(&raw, b.bytes.data() + i, 8);
            Address value = clean(raw);
            if (cc.contains(value) || dr.contains(value) || value == ready) {
                value += slide;
                memcpy(b.bytes.data() + i, &value, 8);
            }
        }
        b.address += slide;
    }
    auto rebase = [&](Image m) {
        m.base += slide;
        for (auto &r : m.ranges)
            r.address += slide;
        for (auto &f : m.functions)
            f += slide;
        return m;
    };
    auto relocatedSymbols = symbols;
    for (auto &s : relocatedSymbols)
        s.address += slide;
    auto rebased = resolve(rebase(cc), rebase(dr), relocatedSymbols, ready + slide);
    for (auto &e : rebased.errors)
        std::cout << "REBASE ERROR " << e << "\n";
    assert(rebased.complete);
    for (auto &value : p.values)
        assert(rebased.values.at(value.first) ==
               value.second + ((cc.contains(value.second) || dr.contains(value.second) ||
                                value.second == ready)
                                   ? slide
                                   : 0));
    // Bound traversal, cycles, absent pointers and two distinct candidates.
    std::vector<Address> heap(256);
    const Address base = 0x100000, table = 0x200000;
    auto readHeap = [&](Address a, void *out, size_t n) {
        if (a < base || n > heap.size() * 8 || a - base > heap.size() * 8 - n)
            return false;
        memcpy(out, (uint8_t *)heap.data() + a - base, n);
        return true;
    };
    auto identity = [](Address a) { return a; };
    heap[7] = base + 64 * 8;
    heap[64] = base + 64 * 8;
    heap[69] = base + 128 * 8;
    heap[128] = table;
    assert(findController(base, table, readHeap, identity) == base + 128 * 8);
    heap[70] = base + 160 * 8;
    heap[160] = table;
    assert(!findController(base, table, readHeap, identity));
    heap[70] = 0;
    heap[128] = 0;
    assert(!findController(base, table, readHeap, identity));
    assert(!findController(0, table, readHeap, identity));
    std::cout
        << "PASS: real image, ASLR relocation, missing/ambiguous/interior symbols, unreadable image, bounded/cyclic/ambiguous object graph\n";
}
