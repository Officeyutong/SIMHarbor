#pragma once
#import <CoreTelephony/CTCellularPlanProvisioning.h>

// The handler must eventually invoke completion exactly once on the caller's behalf.
typedef void (^SHPlanHandler)(CTCellularPlanProvisioningRequest *request, id properties,
                              void (^completion)(CTCellularPlanProvisioningAddPlanResult));
BOOL SHInstallPlanHooks(SHPlanHandler handler);
void SHRemovePlanHooks(void);
