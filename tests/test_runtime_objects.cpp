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
    shlayout::SimContainer layout{shlayout::EntryStorage::Indirect, offset, stride, 0, 4};
    auto vector = SimContainerView::open(owner, layout);
    auto pointers = vector->pointees(memory.reader());
    assert(pointers && *pointers == std::vector<Address>({0x12000, 0x13000}));
    memory.store<Address>(0x11000 + stride, 0);
    assert(!vector->pointees(memory.reader()));
    memory.bytes.erase(0x11000);
    assert(!vector->pointees(memory.reader()));
    assert(!SimContainerView::open(owner, {shlayout::EntryStorage::Indirect, offset, 0, 0, 4}));
    assert(!SimContainerView::open(
        owner, {shlayout::EntryStorage::Indirect, offset, sizeof(Address) - 1, 0, 4}));
    for (VectorBounds bad :
         {VectorBounds{0, 0}, VectorBounds{0x11000, 0x10000}, VectorBounds{0x11000, 0x11001},
          VectorBounds{0x11000, 0x11000 + 17 * stride}}) {
        memory.store(0x10000 + offset, bad);
        assert(!SimContainerView::open(owner, layout));
    }
    memory.store(0x10000 + offset, VectorBounds{0x11000, 0x11000});
    vector = SimContainerView::open(owner, layout);
    assert(vector && vector->pointees(memory.reader())->empty());
    assert(!SimContainerView::open(owner,
                                   {shlayout::EntryStorage::Indirect, offset + 1, stride, 0, 4}));
}
// Inline objects must stay within the discovered entry extent; indirect entries
// may place their pointee word after other metadata.
static void adaptiveContainers() {
    FakeMemory memory;
    constexpr Address owner = 0x20000, begin = 0x21000;
    ControllerLayout layout;
    layout.container = {shlayout::EntryStorage::Inline, 248, 312, 0, 4};
    layout.simInfo.hardwareSlot = 0;
    memory.store(owner + 248, VectorBounds{begin, begin + 2 * 312});
    for (int i = 0; i < 2; ++i) {
        memory.store<int32_t>(begin + i * 312 + 4, i + 1);
        memory.store<int32_t>(begin + i * 312, 2 - i);
    }
    ControllerView controller(memory.reader(), owner, layout);
    auto infos = controller.simInfos();
    assert(infos && infos->size() == 2 && (*infos)[1].address() == begin + 312);
    assert((*infos)[0].logicalSlot() == 1 && (*infos)[1].hardwareSlot() == 1);
    // A readable word in the following entry must never become this object's field.
    memory.store<int32_t>(begin + 312, 99);
    const auto before = memory.reads;
    assert(!(*infos)[0].readField<int32_t>(312));
    assert(memory.reads == before);
    ObjectView view(memory.reader(), owner);
    auto bad = layout.container;
    bad.logical = 312;
    assert(!SimContainerView::open(view, bad));
    bad = {shlayout::EntryStorage::Indirect, 248, 24, 24, 4};
    assert(!SimContainerView::open(view, bad));
    layout.container = {shlayout::EntryStorage::Indirect, 248, 24, 8, 4};
    memory.store(owner + 248, VectorBounds{begin, begin + 24});
    memory.store<Address>(begin + 8, 0x22000);
    auto vector = SimContainerView::open(view, layout.container);
    assert(vector && vector->pointees(memory.reader())->at(0) == 0x22000);
    bool mutated = false;
    MemoryReader changing([&](Address address, void *out, size_t count) {
        bool ok = memory.read(address, out, count);
        if (address == begin + 8 && !mutated) {
            mutated = true;
            memory.store(owner + 248, VectorBounds{begin + 24, begin + 48});
        }
        return ok;
    });
    assert(!vector->pointees(changing)); // Reject a changed container snapshot.
}
static void runtimeLayout(size_t logicalOffset, size_t hardwareOffset) {
    FakeMemory memory;
    ControllerLayout layout;
    layout.container = {shlayout::EntryStorage::Indirect, 48, 16, 0, logicalOffset};
    layout.driverMember = 80;
    layout.simInfo = {logicalOffset, hardwareOffset};
    memory.store(0x10000 + layout.container.member, VectorBounds{0x11000, 0x11030});
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
    adaptiveContainers();
    runtimeLayout(36, 32);
    runtimeLayout(72, 24);
    runtimeLayout(4, 0);
    std::cout
        << "PASS: checked memory views, runtime offsets/stride, vector bounds, failed reads, unassigned-node handling and slot snapshots\n";
}
