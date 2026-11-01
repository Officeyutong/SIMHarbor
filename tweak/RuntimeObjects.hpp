#pragma once
#include "SlotRouting.hpp"
#include <cstdint>
#include <functional>
#include <limits>
#include <optional>
#include <type_traits>
#include <utility>
#include <vector>

namespace shruntime {
using Address = uintptr_t;

// Copy trivially-copyable snapshots through an injected reader. No foreign C++
// object is constructed, copied, retained or destroyed by this adapter.
class MemoryReader {
  public:
    using Read = std::function<bool(Address, void *, size_t)>;
    explicit MemoryReader(Read read) : read_(std::move(read)) {}

    template <class T> std::optional<T> read(Address address) const {
        static_assert(std::is_trivially_copyable_v<T>, "Only memory snapshots may be read");
        if (!read_ || !address || sizeof(T) > std::numeric_limits<Address>::max() - address)
            return std::nullopt;
        T value{};
        if (!read_(address, &value, sizeof value))
            return std::nullopt;
        return value;
    }

    template <class T> std::optional<T> field(Address object, size_t offset) const {
        if (!object || offset > std::numeric_limits<Address>::max() - object)
            return std::nullopt;
        return read<T>(object + offset);
    }

  private:
    Read read_;
};

// A borrowed address plus a checked reader, not an owning private-class instance.
class ObjectView {
  public:
    ObjectView(MemoryReader memory, Address address)
        : memory_(std::move(memory)), address_(address) {}
    Address address() const { return address_; }

    template <class T> std::optional<T> readField(size_t offset) const {
        return memory_.field<T>(address_, offset);
    }
    std::optional<Address> pointerField(size_t offset) const {
        auto pointer = readField<Address>(offset);
        return pointer && *pointer ? pointer : std::nullopt;
    }

  protected:
    MemoryReader memory_;
    Address address_;
};

// Only the discovered begin/end words are copied, not a std::vector object.
struct VectorBounds {
    Address begin = 0, end = 0;
};

class SharedPointerVectorView {
  public:
    static std::optional<SharedPointerVectorView> open(const ObjectView &owner, size_t offset,
                                                       size_t stride, size_t maximumEntries = 16) {
        auto bounds = owner.readField<VectorBounds>(offset);
        if (!bounds || !bounds->begin || bounds->end < bounds->begin || stride < sizeof(Address))
            return std::nullopt;
        Address bytes = bounds->end - bounds->begin;
        if (bytes % stride || bytes / stride > maximumEntries)
            return std::nullopt;
        return SharedPointerVectorView(*bounds, stride);
    }

    // Read only the pointee word of each shared_ptr entry. Never call shared_ptr
    // methods or touch its control block. The caller supplies the checked ABI stride.
    std::optional<std::vector<Address>> pointees(const MemoryReader &memory) const {
        std::vector<Address> result;
        result.reserve((bounds_.end - bounds_.begin) / stride_);
        for (Address entry = bounds_.begin; entry < bounds_.end; entry += stride_) {
            auto pointer = memory.read<Address>(entry);
            if (!pointer || !*pointer)
                return std::nullopt;
            result.push_back(*pointer);
        }
        return result;
    }

  private:
    SharedPointerVectorView(VectorBounds bounds, size_t stride)
        : bounds_(bounds), stride_(stride) {}
    VectorBounds bounds_;
    size_t stride_;
};

struct SimInfoLayout {
    size_t logicalSlot = 0;
    std::optional<size_t> hardwareSlot;
};
struct ControllerLayout {
    size_t simVector = 0;
    size_t sharedPointerStride = 0;
    size_t maximumSimInfos = 16;
    std::optional<size_t> driverMember;
    SimInfoLayout simInfo;
};

class SimInfoView : public ObjectView {
  public:
    using ReadinessProbe = std::function<bool(Address)>;
    SimInfoView(MemoryReader memory, Address address, SimInfoLayout layout)
        : ObjectView(std::move(memory), address), layout_(layout) {}

    std::optional<int32_t> logicalSlot() const { return readField<int32_t>(layout_.logicalSlot); }
    std::optional<int32_t> hardwareSlot() const {
        return layout_.hardwareSlot ? readField<int32_t>(*layout_.hardwareSlot) : std::nullopt;
    }
    // Produce raw metadata for routing validation. Unassigned nodes need neither
    // a hardware-field read nor a private readiness call, matching the modem model.
    std::optional<shslots::Slot> readSlot(const ReadinessProbe &isReady) const {
        auto logical = logicalSlot();
        if (!logical)
            return std::nullopt;
        if (*logical <= 0)
            return shslots::Slot{*logical, 0, false};
        auto hardware = hardwareSlot();
        if (!hardware || !isReady)
            return std::nullopt;
        return shslots::Slot{*logical, *hardware, isReady(address_)};
    }

  private:
    SimInfoLayout layout_;
};

class ControllerView : public ObjectView {
  public:
    ControllerView(MemoryReader memory, Address address, ControllerLayout layout)
        : ObjectView(std::move(memory), address), layout_(layout) {}

    std::optional<std::vector<SimInfoView>> simInfos() const {
        auto vector = SharedPointerVectorView::open(
            *this, layout_.simVector, layout_.sharedPointerStride, layout_.maximumSimInfos);
        if (!vector)
            return std::nullopt;
        auto pointers = vector->pointees(memory_);
        if (!pointers)
            return std::nullopt;
        std::vector<SimInfoView> result;
        result.reserve(pointers->size());
        for (Address pointer : *pointers)
            result.emplace_back(memory_, pointer, layout_.simInfo);
        return result;
    }
    std::optional<Address> driver() const {
        return layout_.driverMember ? pointerField(*layout_.driverMember) : std::nullopt;
    }

  private:
    ControllerLayout layout_;
};
} // namespace shruntime
