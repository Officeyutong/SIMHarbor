#pragma once
#include <algorithm>
#include <set>
#include <optional>
#include <vector>

namespace shslots {
struct Slot {
    int logical, hardware;
    bool ready;
};
// Drop unassigned placeholders, reject ambiguous/invalid hardware mappings and
// sort by logical ID. An empty vector is valid; nullopt means validation failed.
inline std::optional<std::vector<Slot>>
filterAndValidateAssignedSlots(const std::vector<Slot> &raw) {
    std::vector<Slot> out;
    std::set<int> logicals, hardwareSlots;
    for (const auto &entry : raw) {
        // SimInfo can include unassigned placeholders, not just physical cards.
        if (entry.logical <= 0)
            continue;
        if (entry.hardware < 1 || entry.hardware > 3 || !logicals.insert(entry.logical).second ||
            !hardwareSlots.insert(entry.hardware).second) {
            return std::nullopt;
        }
        out.push_back(entry);
    }
    std::sort(out.begin(), out.end(),
              [](const Slot &a, const Slot &b) { return a.logical < b.logical; });
    return out;
}
} // namespace shslots
