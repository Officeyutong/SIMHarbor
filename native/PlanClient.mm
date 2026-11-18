#import "PlanClient.hpp"
#import "../shared/Wire.h"
#import "../shared/JSONFoundation.h"
#include "../shared/Framing.hpp"
#include <arpa/inet.h>
#include <sys/socket.h>
#include <unistd.h>

#ifndef SH_PROVISIONING_PORT
#define SH_PROVISIONING_PORT 18100
#endif
static constexpr uint16_t SHProvisioningPort = SH_PROVISIONING_PORT;

void SHSubmitProvisioning(shjson::ProvisioningRequest request, id properties,
                          void (^result)(CTCellularPlanProvisioningAddPlanResult)) {
    // Properties require a separately verified encoding before they can be forwarded.
    if (properties) {
        if (result)
            result(CTCellularPlanProvisioningAddPlanResultFail);
        return;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        CTCellularPlanProvisioningAddPlanResult outcome =
            CTCellularPlanProvisioningAddPlanResultFail;
        // Retry only the initial connection while the app is starting. Once a
        // request is sent it is never replayed.
        int fd = -1;
        struct sockaddr_in destination = {};
        destination.sin_len = sizeof destination;
        destination.sin_family = AF_INET;
        destination.sin_port = htons(SHProvisioningPort);
        destination.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        for (int attempt = 0; attempt < 40; ++attempt) {
            fd = socket(AF_INET, SOCK_STREAM, 0);
            if (fd < 0)
                break;
            if (connect(fd, (struct sockaddr *)&destination, sizeof destination) == 0)
                break;
            close(fd);
            fd = -1;
            usleep(250000);
        }
        if (fd >= 0) {
            int yes = 1;
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof yes);
            struct timeval timeout = {5, 0};
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof timeout);
            setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof timeout);
            {
                auto challenge = shjson::readMessage<shjson::Challenge>(fd);
                NSString *nonce = challenge ? SHString(challenge->nonce) : nil;
                bool sent =
                    nonce && shjson::writeMessage(fd, shjson::Authentication{SHStdString(
                                                          SHMAC(@"provision-client:", nonce))});
                auto peer = sent ? shjson::readMessage<shjson::Authentication>(fd) : std::nullopt;
                if (peer && SHSame(SHString(peer->mac), SHMAC(@"provision-app:", nonce)) &&
                    shjson::writeMessage(fd, request)) {
                    // After submission a lost connection cannot establish whether
                    // installation completed. Never report a definite failure.
                    outcome = CTCellularPlanProvisioningAddPlanResultUnknown;
                    timeout.tv_sec = 1800;
                    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof timeout);
                    shjson::JSON reply;
                    std::string status;
                    if (shjson::readJSON(fd, reply) && shjson::field(reply, "status", status)) {
                        if (status == "success")
                            outcome = CTCellularPlanProvisioningAddPlanResultSuccess;
                        else if (status == "unknown")
                            outcome = CTCellularPlanProvisioningAddPlanResultUnknown;
                        else if (status == "cancel") {
                            // Cancel was added after the project's iOS 16 SDK.
                            // The iOS 17 SDK appends it after success (value 3).
                            if (NSProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 17)
                                outcome = (CTCellularPlanProvisioningAddPlanResult)3;
                            else
                                outcome = CTCellularPlanProvisioningAddPlanResultFail;
                        } else if (status == "failure")
                            outcome = CTCellularPlanProvisioningAddPlanResultFail;
                    }
                }
            }
            close(fd);
        }
        NSLog(@"SIMHarbor native install completion: %lu", (unsigned long)outcome);
        if (result)
            dispatch_async(dispatch_get_main_queue(), ^{
                result(outcome);
            });
    });
}
