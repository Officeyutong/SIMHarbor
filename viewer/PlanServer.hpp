#pragma once
#import <Foundation/Foundation.h>
#include "../shared/Provisioning.hpp"

typedef void (^SHIncomingPlan)(shjson::ProvisioningRequest request, NSTimeInterval deadline,
                               void (^reply)(NSString *status));
void SHStartPlanServer(SHIncomingPlan handler);
