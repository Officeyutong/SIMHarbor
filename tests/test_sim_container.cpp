#include "../tweak/ResolverCore.hpp"
#include <cassert>
#include <cstring>
#include <iostream>

using namespace shresolve;
// Construct tiny AArch64 functions without executing any target instruction.
// Vary object representation, stride and dataflow independently of firmware.
static std::vector<uint32_t> traversal(bool indirect, unsigned member, unsigned stride,
                                       unsigned logical, unsigned pointee = 0) {
    return {0xa9400000u | ((member / 8) << 15) | (9 << 10) | (22 << 5) | 8,
            0xeb09011f, // cmp x8, x9
            0x54000140, // b.eq return
            indirect ? 0xf9400117u | ((pointee / 8) << 10) : 0xd503201fu,
            0xb940000au | ((logical / 4) << 10) | ((indirect ? 23 : 8) << 5),
            0x6b15015f, // cmp w10, w21
            0x54000060, // b.eq found
            0x91000108u | (stride << 10),
            0x17fffff9, // b bounds comparison
            indirect ? 0xaa1703e0u : 0xaa0803e0u,
            0x94000000u | ((0x200 - 40) / 4),
            0x94000000u | ((0x300 - 44) / 4),
            0xd65f03c0};
}
static std::vector<shlayout::SimContainer> analyze(const std::vector<uint32_t> &code,
                                                   Address state = 0x1200, Address ready = 0x1300) {
    Image image;
    image.base = 0x1000;
    image.ranges = {{image.base, code.size() * 4, true}};
    image.functions = {image.base, image.base + code.size() * 4};
    image.clean = [](Address address) { return address; };
    image.read = [&](Address address, void *out, size_t count) {
        if (address < image.base || count > code.size() * 4 ||
            address - image.base > code.size() * 4 - count)
            return false;
        memcpy(out, reinterpret_cast<const uint8_t *>(code.data()) + address - image.base, count);
        return true;
    };
    return discoverSimContainers(image, image.base, state, ready);
}
int main() {
    for (bool indirect : {false, true}) {
        auto result = analyze(traversal(indirect, 248, indirect ? 24 : 312, indirect ? 36 : 4, 8));
        assert(result.size() == 1);
        const auto &layout = result[0];
        assert(layout.member == 248 && layout.logical == (indirect ? 36 : 4));
        assert(layout.stride == (indirect ? 24 : 312));
        assert(layout.storage ==
               (indirect ? shlayout::EntryStorage::Indirect : shlayout::EntryStorage::Inline));
        assert(layout.pointee == (indirect ? 8 : 0));
    }
    auto valid = traversal(true, 168, 16, 36);
    assert(analyze(valid).size() == 1);
    assert(analyze(valid, 0x1400).empty());         // Wrong getter identity.
    assert(analyze(valid, 0x1200, 0x1400).empty()); // Missing readiness consumer.
    for (auto replacement : {0xaa1603e0u, 0x2a1703e0u}) {
        auto bad = valid;
        bad[9] = replacement; // Wrong object / truncated pointer.
        assert(analyze(bad).empty());
    }
    auto clobbered = valid;
    clobbered[3] = 0xd2800008; // mov x8, #0
    assert(analyze(clobbered).empty());
    auto noEquality = valid;
    noEquality[5] = 0xd503201f;
    assert(analyze(noEquality).empty());
    auto noBoundsBranch = valid;
    noBoundsBranch[2] = 0xd503201f;
    assert(analyze(noBoundsBranch).empty());
    auto noLoop = valid;
    noLoop[8] = 0xd65f03c0;
    assert(analyze(noLoop).empty());
    assert(analyze(traversal(true, 168, 0, 36)).empty());
    assert(analyze(traversal(true, 168, 12, 36)).empty());
    assert(analyze(traversal(true, 168, 8, 36, 8)).empty());
    assert(analyze(traversal(false, 248, 16, 16)).empty());
    assert(analyze({}).empty());
    std::cout
        << "PASS: ARM64 container dataflow, inline/indirect layouts, changed stride/pointee, clobbers and incomplete proofs\n";
}
