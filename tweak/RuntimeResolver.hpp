#pragma once
#import <Foundation/Foundation.h>
#include "ResolverCore.hpp"
#include <atomic>
#include <memory>
struct SHFirmware {
    shresolve::Image cc, driver;
    shresolve::Plan plan;
    bool compiledAbiCompatible = false, abiCompatible = false;
    std::atomic<int> hookStage{0}; // not attempted / installing / installed / failed
    uint64_t analysisMilliseconds = 0, maxMeasuredFootprintBytes = 0;
    size_t driverSymbolCount = 0;
    uintptr_t getter = 0, mutableGetter = 0;
    std::string registryImage;
    std::atomic<size_t> driverMember{0}, hardwareSlot{0}, driverCandidates{0},
        hardwareCandidates{0};
    std::atomic<int> objectStage{0};
};
std::shared_ptr<SHFirmware> SHResolveFirmware();
bool SHReadMemory(uintptr_t, void *, size_t);
uintptr_t SHCleanPointer(uintptr_t);
bool SHInferObjectLayout(SHFirmware &, uintptr_t);
NSDictionary *SHResolverReport(const std::shared_ptr<SHFirmware> &);
