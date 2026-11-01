#include "../tweak/SlotRouting.hpp"
#include <cassert>
#include <iostream>

int main() {
    using shslots::filterAndValidateAssignedSlots;
    auto slots = filterAndValidateAssignedSlots({{0, 3, false}, {2, 2, true}, {1, 1, true}});
    assert(slots && slots->size() == 2 && (*slots)[0].logical == 1 && (*slots)[0].hardware == 1 &&
           (*slots)[1].logical == 2);
    slots = filterAndValidateAssignedSlots({{0, 0, false}, {7, 2, false}, {4, 1, true}});
    assert(slots && slots->size() == 2 && (*slots)[0].logical == 4 && (*slots)[0].hardware == 1 &&
           (*slots)[1].logical == 7 && (*slots)[1].hardware == 2 && !(*slots)[1].ready);
    assert(!filterAndValidateAssignedSlots({{1, 1, true}, {1, 2, true}}));
    assert(!filterAndValidateAssignedSlots({{1, 2, true}, {2, 2, true}}));
    assert(!filterAndValidateAssignedSlots({{1, 0, true}}));
    slots = filterAndValidateAssignedSlots({{0, 3, false}});
    assert(slots && slots->empty());
    slots = filterAndValidateAssignedSlots({});
    assert(slots && slots->empty());
    std::cout
        << "PASS: reserved/unassigned nodes, dynamic logical IDs, hardware mapping, inactive slots and ambiguity rejection\n";
}
