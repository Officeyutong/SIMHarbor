#pragma once
// Requirements of the compiled ARM64 transport adapter, not firmware identities.
// Runtime symbol/instruction/object validation supplies the target-side evidence.
#ifdef __cplusplus
#include <cstddef>
static inline bool SHRuntimeAbiLayoutCompatible(size_t pointerBytes, size_t sharedPtrBytes,
                                                size_t functionBytes) {
    return pointerBytes == 8 && sharedPtrBytes == 16 && functionBytes == 32;
}
#endif
