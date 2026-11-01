#import "RuntimeResolver.hpp"
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach/mach.h>
#import <mach/vm_map.h>
#import "../shared/Firmware.h"
#import <ptrauth.h>
#import <dlfcn.h>
#include <algorithm>
#include <cstring>
#include <set>
using namespace shresolve;
uintptr_t SHCleanPointer(uintptr_t p) {
    return (uintptr_t)ptrauth_strip((void *)p, ptrauth_key_function_pointer) &
           0x7fffffffffffffffULL;
}
bool SHReadMemory(uintptr_t a, void *out, size_t n) {
    if (a < 0x10000 || !n || n > 65536 || a + n < a)
        return false;
    vm_size_t read = 0;
    return vm_read_overwrite(mach_task_self(), a, n, (vm_address_t)out, &read) == KERN_SUCCESS &&
           read == n;
}
static std::string hex(const uint8_t *p, size_t n) {
    std::string s;
    const char *h = "0123456789abcdef";
    for (size_t i = 0; i < n; i++) {
        s += h[p[i] >> 4];
        s += h[p[i] & 15];
    }
    return s;
}
static Image image(uint32_t index) {
    Image m;
    m.name = _dyld_get_image_name(index);
    m.base = (Address)_dyld_get_image_header(index);
    intptr_t slide = _dyld_get_image_vmaddr_slide(index);
    const mach_header_64 *h = (const mach_header_64 *)m.base;
    if (h->magic != MH_MAGIC_64 || h->ncmds > 1024 || h->sizeofcmds > 1024 * 1024)
        return m;
    auto *c = (const load_command *)(h + 1);
    Address link = 0;
    uint32_t functionOff = 0, functionSize = 0;
    for (uint32_t j = 0; j < h->ncmds; j++) {
        if (c->cmdsize < 8 || (uintptr_t)c + c->cmdsize > m.base + sizeof(*h) + h->sizeofcmds)
            return Image{};
        if (c->cmd == LC_UUID)
            m.uuid = hex(((const uuid_command *)c)->uuid, 16);
        if (c->cmd == LC_SEGMENT_64) {
            auto *s = (const segment_command_64 *)c;
            if (!strcmp(s->segname, "__LINKEDIT"))
                link = s->vmaddr + slide - s->fileoff;
            else if (s->vmsize && s->vmsize <= 64 * 1024 * 1024 && (s->initprot & VM_PROT_READ)) {
                m.ranges.push_back({s->vmaddr + slide, (size_t)s->vmsize, false});
                auto *sec = (const section_64 *)(s + 1);
                if (sizeof(*s) + (uint64_t)s->nsects * sizeof(*sec) > c->cmdsize)
                    return Image{};
                for (uint32_t k = 0; k < s->nsects; k++)
                    if (sec[k].flags & (S_ATTR_PURE_INSTRUCTIONS | S_ATTR_SOME_INSTRUCTIONS))
                        m.ranges.push_back({sec[k].addr + slide, (size_t)sec[k].size, true});
            }
        }
        if (c->cmd == LC_FUNCTION_STARTS) {
            auto *s = (const linkedit_data_command *)c;
            functionOff = s->dataoff;
            functionSize = s->datasize;
        }
        c = (const load_command *)((const char *)c + c->cmdsize);
    }
    if (link && functionSize && functionSize < 4 * 1024 * 1024) {
        std::vector<uint8_t> bytes(functionSize);
        vm_size_t n = 0;
        if (vm_read_overwrite(mach_task_self(), link + functionOff, functionSize,
                              (vm_address_t)bytes.data(), &n) == KERN_SUCCESS &&
            n == functionSize) {
            Address current = m.base;
            size_t p = 0;
            while (p < bytes.size()) {
                Address delta = 0;
                int shift = 0;
                uint8_t b = 0;
                do {
                    if (p >= bytes.size() || shift >= 63) {
                        p = bytes.size();
                        break;
                    }
                    b = bytes[p++];
                    delta |= Address(b & 127) << shift;
                    shift += 7;
                } while (b & 128);
                if (!delta || current + delta < current)
                    break;
                current += delta;
                if (m.code(current))
                    m.functions.push_back(current);
            }
        }
    }
    auto ranges = m.ranges;
    m.read = [ranges](Address a, void *out, size_t n) {
        for (auto &r : ranges)
            if (a >= r.address && n <= r.size && a - r.address <= r.size - n) {
                memcpy(out, (void *)a, n);
                return true;
            }
        return false;
    };
    m.clean = SHCleanPointer;
    return m;
}
// Module-scoped CoreSymbolication avoids Gum's process-wide symbol cache. The
// opaque two-pointer reference/range ABI matches Frida's Darwin symbolicator.
struct SHCSRef {
    void *data;
    void *obj;
};
struct SHCSRange {
    uint64_t location, length;
};
static std::vector<Symbol> driverSymbols(const Image &driver) {
    std::vector<Symbol> result;
    void *library =
        dlopen("/System/Library/PrivateFrameworks/CoreSymbolication.framework/CoreSymbolication",
               RTLD_LAZY | RTLD_LOCAL);
    if (!library)
        return result;
    auto create = (SHCSRef (*)(task_t))dlsym(library, "CSSymbolicatorCreateWithTask");
    auto owner = (SHCSRef (*)(SHCSRef, uint64_t, uint64_t))dlsym(
        library, "CSSymbolicatorGetSymbolOwnerWithAddressAtTime");
    auto each = (int (*)(SHCSRef, int (^)(SHCSRef)))dlsym(library, "CSSymbolOwnerForeachSymbol");
    auto name = (const char *(*)(SHCSRef))dlsym(library, "CSSymbolGetName");
    auto range = (SHCSRange (*)(SHCSRef))dlsym(library, "CSSymbolGetRange");
    auto isNull = (unsigned char (*)(SHCSRef))dlsym(library, "CSIsNull");
    auto release = (void (*)(SHCSRef))dlsym(library, "CSRelease");
    if (create && owner && each && name && range && isNull && release) {
        SHCSRef symbols = create(mach_task_self());
        if (!isNull(symbols)) {
            SHCSRef module = owner(symbols, driver.base, 0x8000000000000000ULL);
            if (!isNull(module)) {
                auto *output = &result;
                auto *image = &driver;
                each(module, ^(SHCSRef symbol) {
                    const char *n = name(symbol);
                    if (n && strstr(n, "sendSimApdu")) {
                        Address address = SHCleanPointer(range(symbol).location);
                        if (image->code(address) &&
                            std::binary_search(image->functions.begin(), image->functions.end(),
                                               address))
                            output->push_back({address, n});
                    }
                    return 0;
                });
            }
            release(symbols);
        }
    }
    dlclose(library);
    return result;
}
static uint64_t footprint() {
    task_vm_info_data_t info = {};
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    return task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count) == KERN_SUCCESS
               ? info.phys_footprint
               : 0;
}
static bool registryExport(uintptr_t address, std::string &ownerName) {
    if (!address || (address & 3))
        return false;
    Dl_info symbol = {};
    if (!dladdr((void *)address, &symbol) || !symbol.dli_fbase)
        return false;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        if ((const void *)_dyld_get_image_header(i) != symbol.dli_fbase)
            continue;
        Image owner = image(i);
        if (!owner.code(address))
            return false;
        bool start = std::binary_search(owner.functions.begin(), owner.functions.end(), address);
        bool exportedStart =
            symbol.dli_saddr && SHCleanPointer((uintptr_t)symbol.dli_saddr) == address;
        if (!start && !exportedStart)
            return false;
        const char *last = strrchr(owner.name.c_str(), '/');
        ownerName = last ? last + 1 : owner.name;
        return true;
    }
    return false;
}
std::shared_ptr<SHFirmware> SHResolveFirmware() {
    auto fw = std::make_shared<SHFirmware>();
    double begin = CFAbsoluteTimeGetCurrent();
    fw->maxMeasuredFootprintBytes = footprint();
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        const char *last = strrchr(name, '/');
        last = last ? last + 1 : name;
        if (!strcmp(last, "CommCenter"))
            fw->cc = image(i);
        if (!strcmp(last, "libCommCenterMCommandDrivers.dylib"))
            fw->driver = image(i);
    }
    fw->compiledAbiCompatible = SHRuntimeAbiLayoutCompatible(
        sizeof(void *), sizeof(std::shared_ptr<void>), sizeof(std::function<void(bool)>));
    fw->getter = SHCleanPointer((uintptr_t)dlsym(RTLD_DEFAULT, "_ZNK8Registry13getServiceMapEv"));
    fw->mutableGetter =
        SHCleanPointer((uintptr_t)dlsym(RTLD_DEFAULT, "_ZN8Registry13getServiceMapEv"));
    if (!fw->getter)
        fw->getter = fw->mutableGetter;
    if (!fw->compiledAbiCompatible) {
        fw->plan.errors.push_back(
            "Compiled C++ object layout is incompatible with the ARM64 adapter");
        return fw;
    }
    if (!fw->cc.base || !fw->driver.base || !fw->getter) {
        fw->plan.errors.push_back("Required image or Registry export is missing");
        return fw;
    }
    if (((const mach_header_64 *)fw->cc.base)->cputype != CPU_TYPE_ARM64 ||
        ((const mach_header_64 *)fw->driver.base)->cputype != CPU_TYPE_ARM64) {
        fw->plan.errors.push_back("Loaded images are not ARM64");
        return fw;
    }
    std::string mutableOwner;
    bool mutableValid = registryExport(fw->mutableGetter, mutableOwner);
    if (!registryExport(fw->getter, fw->registryImage)) {
        if (!mutableValid) {
            fw->plan.errors.push_back(
                "No Registry getter has a valid owning image and function/export boundary");
            return fw;
        }
        fw->getter = fw->mutableGetter;
        fw->registryImage = mutableOwner;
    }
    if (!mutableValid)
        fw->mutableGetter = 0;
    std::vector<Symbol> symbols = driverSymbols(fw->driver);
    fw->driverSymbolCount = symbols.size();
    fw->maxMeasuredFootprintBytes = std::max(fw->maxMeasuredFootprintBytes, footprint());
    Address ready =
        SHCleanPointer((uintptr_t)dlsym(RTLD_DEFAULT, "_ZN10subscriber10isSimReadyENS_8SimStateE"));
    fw->plan = resolve(fw->cc, fw->driver, symbols, ready);
    fw->abiCompatible = fw->compiledAbiCompatible && fw->plan.signaturesValidated;
    fw->analysisMilliseconds = (CFAbsoluteTimeGetCurrent() - begin) * 1000;
    fw->maxMeasuredFootprintBytes = std::max(fw->maxMeasuredFootprintBytes, footprint());
    return fw;
}
static std::string typeName(uintptr_t object) {
    uintptr_t v = 0, t = 0, n = 0;
    if (!SHReadMemory(object, &v, 8))
        return {};
    v = SHCleanPointer(v);
    if (v < 8 || !SHReadMemory(v - 8, &t, 8))
        return {};
    t = SHCleanPointer(t);
    if (!SHReadMemory(t + sizeof(void *), &n, 8))
        return {};
    n = SHCleanPointer(n);
    char bytes[256] = {};
    if (!SHReadMemory(n, bytes, sizeof(bytes)))
        return {};
    size_t length = strnlen(bytes, sizeof(bytes));
    if (length == sizeof(bytes))
        return {};
    return std::string(bytes, length);
}
bool SHInferObjectLayout(SHFirmware &fw, uintptr_t object) {
    if (!fw.plan.complete || !object)
        return false;
    fw.objectStage = 2;
    std::vector<size_t> drivers;
    for (size_t off = sizeof(void *); off < 512; off += sizeof(void *)) {
        uintptr_t p = 0;
        if (SHReadMemory(object + off, &p, 8) &&
            typeName(SHCleanPointer(p)) == "N10subscriber19EURSimCommandDriverE")
            drivers.push_back(off);
    }
    fw.driverCandidates = drivers.size();
    if (drivers.size() != 1) {
        fw.objectStage = 3;
        return false;
    }
    fw.objectStage = 4;
    uintptr_t span[2] = {};
    if (!SHReadMemory(object + fw.plan.values.at("simVector"), span, sizeof span) || !span[0] ||
        span[1] < span[0] || (span[1] - span[0]) % sizeof(std::shared_ptr<void>) ||
        span[1] - span[0] > 16 * sizeof(std::shared_ptr<void>))
        return false;
    size_t count = (span[1] - span[0]) / sizeof(std::shared_ptr<void>);
    if (!count)
        return false;
    std::vector<uintptr_t> infos;
    for (size_t i = 0; i < count; i++) {
        uintptr_t p = 0;
        if (!SHReadMemory(span[0] + i * sizeof(std::shared_ptr<void>), &p, 8) || !p)
            return false;
        infos.push_back(p);
    }
    std::vector<size_t> hardware;
    for (size_t off = 0; off < 128; off += sizeof(int)) {
        if (off == fw.plan.values.at("logicalSlot"))
            continue;
        std::set<int> slots;
        bool valid = true;
        for (uintptr_t p : infos) {
            int value = 0;
            if (!SHReadMemory(p + off, &value, sizeof value) || value < 1 || value > 3 ||
                !slots.insert(value).second) {
                valid = false;
                break;
            }
        }
        if (valid)
            hardware.push_back(off);
    }
    fw.hardwareCandidates = hardware.size();
    if (hardware.size() != 1) {
        fw.objectStage = 6;
        return false;
    }
    fw.driverMember = drivers[0];
    fw.hardwareSlot = hardware[0];
    fw.objectStage = 7;
    return true;
}
shjson::ResolverReport SHResolverReport(const std::shared_ptr<SHFirmware> &fw) {
    shjson::ResolverReport report;
    if (!fw)
        return report;
    report.state = fw->plan.complete ? "resolved" : "unresolved";
    report.engine = "CoreSymbolication (driver only) + Frida Capstone 5";
    report.details.emplace();
    auto &details = *report.details;
    for (const auto &value : fw->plan.values) {
        bool address = value.second > 4096;
        uintptr_t origin = fw->cc.contains(value.second)       ? fw->cc.base
                           : fw->driver.contains(value.second) ? fw->driver.base
                                                               : 0;
        char text[32];
        snprintf(text, sizeof text, address ? "0x%llx" : "+0x%llx",
                 (unsigned long long)value.second);
        shjson::ResolverValue entry;
        entry.value = text;
        auto source = fw->plan.sources.find(value.first);
        entry.source = source == fw->plan.sources.end() ? "unresolved" : source->second;
        if (origin) {
            snprintf(text, sizeof text, "0x%llx", (unsigned long long)(value.second - origin));
            entry.imageOffset = text;
        }
        details.values.emplace(value.first, std::move(entry));
    }
    details.values["driverMember"] = {
        fw->driverMember.load(), "Unique live pointer with EURSimCommandDriver RTTI", std::nullopt};
    details.values["hardwareSlot"] = {fw->hardwareSlot.load(),
                                      "Unique hardware-slot field across live SimInfo nodes",
                                      std::nullopt};
    details.errors = fw->plan.errors;
    if (fw->hookStage.load() == 3)
        details.errors.push_back(
            "Transport hook installation did not produce all required original functions");
    details.objectDiscovery = "Waiting for the Registry service map";
    switch (fw->objectStage.load()) {
    case 1:
        details.objectDiscovery = "Waiting for a unique live controller";
        break;
    case 2:
        details.objectDiscovery = "Inspecting the live driver pointer";
        break;
    case 3:
        details.objectDiscovery = "Live driver pointer is missing or ambiguous";
        break;
    case 4:
        details.objectDiscovery = "SIM information vector is not ready or could not be validated";
        break;
    case 6:
        details.objectDiscovery = "Hardware-slot field is missing or ambiguous";
        break;
    case 7:
        details.objectDiscovery = "Live object layout validated";
        break;
    }
    details.analysisMilliseconds = fw->analysisMilliseconds;
    details.maxMeasuredFootprintBytes = fw->maxMeasuredFootprintBytes;
    details.driverSymbolCount = fw->driverSymbolCount;
    details.commcenterUUID = fw->cc.uuid;
    details.driverUUID = fw->driver.uuid;
    details.registryImage = fw->registryImage;
    details.abiCompatible = fw->abiCompatible;
    details.compiledAbiCompatible = fw->compiledAbiCompatible;
    details.signaturesValidated = fw->plan.signaturesValidated;
    details.hookStage = fw->hookStage.load();
    details.sharedPtrBytes = sizeof(std::shared_ptr<void>);
    details.functionBytes = sizeof(std::function<void(bool)>);
    details.codeResolved = fw->plan.complete;
    details.objectDiscoveryStage = fw->objectStage.load();
    details.driverCandidates = fw->driverCandidates.load();
    details.hardwareCandidates = fw->hardwareCandidates.load();
    details.objectLayoutResolved = fw->driverMember.load() && fw->hardwareSlot.load();
    details.policy =
        "Runtime capability discovery; UUIDs are diagnostic metadata only; no numerical-offset fallback";
    return report;
}
