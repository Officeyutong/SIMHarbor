#include "../shared/ServerOID.hpp"
#include <cassert>
#include <fstream>
#include <iterator>
#include <vector>
static std::vector<uint8_t> read(const char *path) {
    std::ifstream f(path, std::ios::binary);
    assert(f);
    return {std::istreambuf_iterator<char>(f), {}};
}
int main(int argc, char **argv) {
    assert(argc == 7);
    auto matching = read(argv[1]), absent = read(argv[2]), duplicate = read(argv[3]),
         wrongLocation = read(argv[4]), critical = read(argv[5]), noSan = read(argv[6]);
    auto check = [](const std::vector<uint8_t> &v, const std::string &oid) {
        return shoid::matchesCertificate({v.data(), v.size()}, oid);
    };
    const std::string oid = "1.3.6.1.4.1.31746";
    assert(check(matching, oid));
    assert(!check(matching, "1.3.6.1.4.1.31747"));
    assert(!check(matching, "1.03.6.1.4.1.31746"));
    assert(!check(matching, "2.999999999999999999999999999999999999.1"));
    assert(!check(absent, oid));
    assert(!check(duplicate, oid));
    assert(!check(wrongLocation, oid));
    assert(check(critical, oid));
    assert(!check(noSan, oid));
    for (size_t n = 0; n < matching.size(); n++)
        assert(!shoid::matchesCertificate({matching.data(), n}, oid));
    matching.push_back(0);
    assert(!check(matching, oid));
    for (size_t n = 0; n + 1 < matching.size(); ++n) {
        auto changed = matching;
        changed[n] ^= 0x80;
        (void)check(changed, oid);
    }
}
