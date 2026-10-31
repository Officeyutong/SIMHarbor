#pragma once
// Calling-convention approval only. Function and object offsets are not configured here.
#define SH_APPROVED_CC_UUID "10bdb2fd04e33fcea0a188d064801df2"
#define SH_APPROVED_DRIVER_UUID "571c9998ee7c3d9e946f779aee761332"
// Measured in the actual arm64e native build. Earlier Frida scratch buffers
// allocated 48 bytes for std::function; that allocation was not its sizeof.
#define SH_APPROVED_SHARED_PTR_BYTES 16
#define SH_APPROVED_FUNCTION_BYTES 32

#ifdef __cplusplus
#include <cstring>
struct SHApprovedAbi {
    const char *commcenterUUID, *driverUUID;
    size_t sharedPtrBytes, functionBytes;
};
static constexpr SHApprovedAbi SHApprovedAbis[] = {
    {SH_APPROVED_CC_UUID, SH_APPROVED_DRIVER_UUID, SH_APPROVED_SHARED_PTR_BYTES,
     SH_APPROVED_FUNCTION_BYTES},
};
static inline bool SHApproveAbi(const char *cc, const char *driver, size_t shared,
                                size_t function) {
    for (const auto &entry : SHApprovedAbis)
        if (!strcmp(cc, entry.commcenterUUID) && !strcmp(driver, entry.driverUUID) &&
            shared == entry.sharedPtrBytes && function == entry.functionBytes)
            return true;
    return false;
}
#endif
