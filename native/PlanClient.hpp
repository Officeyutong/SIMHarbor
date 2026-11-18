#pragma once
#include "PlanDispatch.hpp"
// A request is sent at most once. A lost connection after submission reports
// unknown because the installation may already have completed.
void SHSubmitProvisioning(shjson::ProvisioningRequest request, id properties,
                          void (^result)(CTCellularPlanProvisioningAddPlanResult));
