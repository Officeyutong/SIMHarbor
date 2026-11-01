#pragma once
#include "SimContainer.hpp"
#include <optional>
#include <cstdint>
#include <functional>
#include <map>
#include <string>
#include <vector>
namespace shresolve {
using Address = uint64_t;
struct Range {
    Address address;
    size_t size;
    bool code;
};
struct Image {
    std::string name, uuid;
    Address base = 0;
    std::vector<Range> ranges;
    std::vector<Address> functions;
    std::function<bool(Address, void *, size_t)> read;
    std::function<Address(Address)> clean;
    bool contains(Address, size_t = 1) const;
    bool code(Address) const;
    Address pointer(Address) const;
    std::string string(Address, size_t = 2048) const;
};
struct Symbol {
    Address address;
    std::string name;
};
struct Plan {
    std::map<std::string, Address> values;
    std::map<std::string, std::string> sources;
    std::vector<std::string> errors;
    std::optional<shlayout::SimContainer> simContainer;
    bool complete = false;
    bool signaturesValidated = false;
    void set(const std::string &, Address, const std::string &);
};
// Analyze bounded traversal paths and require object/slot/state dataflow evidence.
std::vector<shlayout::SimContainer> discoverSimContainers(const Image &, Address worker,
                                                          Address state, Address ready);
Plan resolve(const Image &cc, const Image &driver, const std::vector<Symbol> &, Address ready);
// Safe object discovery is separate from static code analysis and sends no commands.
Address findController(Address map, Address vtable,
                       const std::function<bool(Address, void *, size_t)> &,
                       const std::function<Address(Address)> &);
} // namespace shresolve
