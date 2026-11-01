#pragma once
#include <algorithm>
#include <set>
#include <string>
#include <vector>

namespace shslots {
struct Slot {
    int logical, hardware;
    bool ready;
};
inline bool assigned(const std::vector<Slot> &raw, std::vector<Slot> &out) {
    out.clear();
    std::set<int> logicals, hardwareSlots;
    for (const auto &entry : raw) {
        // SimInfo can include unassigned placeholders, not just physical cards.
        if (entry.logical <= 0)
            continue;
        if (entry.hardware < 1 || entry.hardware > 3 || !logicals.insert(entry.logical).second ||
            !hardwareSlots.insert(entry.hardware).second) {
            out.clear();
            return false;
        }
        out.push_back(entry);
    }
    std::sort(out.begin(), out.end(),
              [](const Slot &a, const Slot &b) { return a.logical < b.logical; });
    return true;
}
} // namespace shslots
