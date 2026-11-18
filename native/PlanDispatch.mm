#import "PlanDispatch.hpp"
#import "PlanHooks.h"
#include "../shared/ProvisioningFoundation.hpp"

BOOL SHStartPlanDispatch(SHProvisioningBackend backend) {
    if (!backend)
        return NO;
    SHProvisioningBackend retained = [backend copy];
    return SHInstallPlanHooks(^(CTCellularPlanProvisioningRequest *request, id properties,
                                void (^completion)(CTCellularPlanProvisioningAddPlanResult)) {
        shjson::ProvisioningRequest parsed;
        if (!shjson::fromNativeProvisioning(request, parsed)) {
            if (completion)
                completion(CTCellularPlanProvisioningAddPlanResultFail);
            return;
        }
        retained(std::move(parsed), properties, completion);
    });
}
void SHStopPlanDispatch(void) { SHRemovePlanHooks(); }
