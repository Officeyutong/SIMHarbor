#pragma once
#include <cstddef>
#include <tuple>

namespace shlayout {
// Describes borrowed target memory, never a C++ container that this process owns.
enum class EntryStorage { Inline = 1, Indirect = 2 };
struct SimContainer {
    EntryStorage storage = EntryStorage::Indirect;
    size_t member = 0;
    size_t stride = 0;
    size_t pointee = 0;
    size_t logical = 0;
    auto key() const { return std::make_tuple(storage, member, stride, pointee, logical); }
    bool operator<(const SimContainer &other) const { return key() < other.key(); }
};
} // namespace shlayout
