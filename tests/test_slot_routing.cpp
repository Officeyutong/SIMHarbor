#include "../tweak/SlotRouting.hpp"
#include <cassert>
#include <iostream>

int main() {
    std::vector<shslots::Slot> out;
    assert(shslots::assigned({{0, 3, false}, {2, 2, true}, {1, 1, true}}, out));
    assert(out.size() == 2 && out[0].logical == 1 && out[0].hardware == 1 && out[1].logical == 2);
    assert(shslots::assigned({{0, 0, false}, {7, 2, false}, {4, 1, true}}, out));
    assert(out.size() == 2 && out[0].logical == 4 && out[0].hardware == 1 && out[1].logical == 7 &&
           out[1].hardware == 2 && !out[1].ready);
    assert(!shslots::assigned({{1, 1, true}, {1, 2, true}}, out) && out.empty());
    assert(!shslots::assigned({{1, 2, true}, {2, 2, true}}, out) && out.empty());
    assert(!shslots::assigned({{1, 0, true}}, out) && out.empty());
    assert(shslots::assigned({{0, 3, false}}, out) && out.empty());
    std::cout
        << "PASS: reserved/unassigned nodes, dynamic logical IDs, hardware mapping, inactive slots and ambiguity rejection\n";
}
