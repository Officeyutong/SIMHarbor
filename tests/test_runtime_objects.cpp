#include "../tweak/RuntimeObjects.hpp"
#include <cassert>
#include <cstring>
#include <iostream>
#include <map>

using namespace shruntime;
struct FakeMemory {
    std::map<Address, uint8_t> bytes;
    size_t reads = 0;
    template <class T> void store(Address address, const T &value) {
        const auto *data = reinterpret_cast<const uint8_t *>(&value);
        for (size_t i = 0; i < sizeof value; ++i)
            bytes[address + i] = data[i];
    }
    bool read(Address address, void *out, size_t count) {
        ++reads;
        auto *data = static_cast<uint8_t *>(out);
        for (size_t i = 0; i < count; ++i) {
            auto byte = bytes.find(address + i);
            if (byte == bytes.end())
                return false;
            data[i] = byte->second;
        }
        return true;
    }
    MemoryReader reader() {
        return MemoryReader(
            [this](Address address, void *out, size_t count) { return read(address, out, count); });
    }
};
static void fieldFailures() {
    FakeMemory memory;
    auto reader = memory.reader();
    assert(!reader.read<uint64_t>(0));
    assert(!reader.read<uint64_t>(std::numeric_limits<Address>::max() - 3));
    assert(!reader.field<uint32_t>(std::numeric_limits<Address>::max() - 3, 8));
    assert(memory.reads == 0); // Invalid arithmetic must not reach the backing reader.
    memory.store<uint32_t>(0x10000, 42);
    assert(reader.read<uint32_t>(0x10000) == 42);
    assert(!reader.read<uint64_t>(0x10000)); // Partial copies are not successful snapshots.
    assert(!MemoryReader({}).read<uint32_t>(0x10000));
}
static void boundsAndPointers() {
    FakeMemory memory;
    ObjectView owner(memory.reader(), 0x10000);
    constexpr size_t offset = 32, stride = 24; // Supplied ABI stride, not host shared_ptr size.
    memory.store(0x10000 + offset, VectorBounds{0x11000, 0x11000 + 2 * stride});
    memory.store<Address>(0x11000, 0x12000);
    memory.store<Address>(0x11000 + stride, 0x13000);
    // Control-block words need not even be readable; only pointee words are inspected.
    auto vector = SharedPointerVectorView::open(owner, offset, stride);
    auto pointers = vector->pointees(memory.reader());
    assert(pointers && *pointers == std::vector<Address>({0x12000, 0x13000}));
    memory.store<Address>(0x11000 + stride, 0);
    assert(!vector->pointees(memory.reader()));
    memory.bytes.erase(0x11000);
    assert(!vector->pointees(memory.reader()));
    assert(!SharedPointerVectorView::open(owner, offset, 0));
    assert(!SharedPointerVectorView::open(owner, offset, sizeof(Address) - 1));
    for (VectorBounds bad :
         {VectorBounds{0, 0}, VectorBounds{0x11000, 0x10000}, VectorBounds{0x11000, 0x11001},
          VectorBounds{0x11000, 0x11000 + 17 * stride}}) {
        memory.store(0x10000 + offset, bad);
        assert(!SharedPointerVectorView::open(owner, offset, stride));
    }
    memory.store(0x10000 + offset, VectorBounds{0x11000, 0x11000});
    vector = SharedPointerVectorView::open(owner, offset, stride);
    assert(vector && vector->pointees(memory.reader())->empty());
    assert(!SharedPointerVectorView::open(owner, offset + 1, stride));
}
static void runtimeLayout(size_t logicalOffset, size_t hardwareOffset) {
    FakeMemory memory;
    ControllerLayout layout;
    layout.simVector = 48;
    layout.sharedPointerStride = 16;
    layout.driverMember = 80;
    layout.simInfo = {logicalOffset, hardwareOffset};
    memory.store(0x10000 + layout.simVector, VectorBounds{0x11000, 0x11030});
    memory.store<Address>(0x10000 + *layout.driverMember, 0x17000);
    for (int i = 0; i < 3; ++i)
        memory.store<Address>(0x11000 + i * 16, 0x12000 + i * 0x100);
    memory.store<int32_t>(0x12000 + logicalOffset, 0); // No hardware field: unassigned placeholder.
    memory.store<int32_t>(0x12100 + logicalOffset, 7);
    memory.store<int32_t>(0x12100 + hardwareOffset, 2);
    memory.store<int32_t>(0x12200 + logicalOffset, 4);
    memory.store<int32_t>(0x12200 + hardwareOffset, 1);
    ControllerView controller(memory.reader(), 0x10000, layout);
    assert(controller.driver() == 0x17000);
    auto infos = controller.simInfos();
    assert(infos && infos->size() == 3);
    std::vector<Address> probed;
    std::vector<shslots::Slot> raw;
    for (const auto &info : *infos) {
        auto snapshot = info.readSlot([&](Address object) {
            probed.push_back(object);
            return object == 0x12200;
        });
        assert(snapshot);
        raw.push_back(*snapshot);
    }
    assert(probed == std::vector<Address>({0x12100, 0x12200}));
    auto slots = shslots::filterAndValidateAssignedSlots(raw);
    assert(slots && slots->size() == 2 && (*slots)[0].logical == 4 && (*slots)[0].hardware == 1 &&
           (*slots)[0].ready && (*slots)[1].logical == 7 && !(*slots)[1].ready);
    assert(!(*infos)[1].readSlot({})); // Readiness callback is required for assigned nodes.
    memory.bytes.erase(0x12100 + hardwareOffset);
    assert(!(*infos)[1].readSlot([](Address) { return true; }));
    memory.store<Address>(0x10000 + *layout.driverMember, 0);
    assert(!controller.driver());
    layout.driverMember.reset();
    layout.simInfo.hardwareSlot.reset();
    ControllerView unresolved(memory.reader(), 0x10000, layout);
    assert(!unresolved.driver());
    auto unbound = unresolved.simInfos();
    assert(unbound && (*unbound)[0].readSlot({}));
    assert(!(*unbound)[1].readSlot([](Address) { return true; }));
    memory.store<Address>(0x11010, 0);
    assert(!controller.simInfos());
}
int main() {
    fieldFailures();
    boundsAndPointers();
    runtimeLayout(36, 32);
    runtimeLayout(72, 24);
    std::cout
        << "PASS: checked memory views, runtime offsets/stride, vector bounds, failed reads, unassigned-node handling and slot snapshots\n";
}
