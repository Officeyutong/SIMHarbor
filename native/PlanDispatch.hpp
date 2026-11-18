#pragma once
#include "../shared/Provisioning.hpp"
#import <CoreTelephony/CTCellularPlanProvisioning.h>

// The backend owns a copy of the request and invokes the result block once.
typedef void (^SHProvisioningBackend)(shjson::ProvisioningRequest request, id properties,
                                      void (^result)(CTCellularPlanProvisioningAddPlanResult));
BOOL SHStartPlanDispatch(SHProvisioningBackend backend);
void SHStopPlanDispatch(void);
