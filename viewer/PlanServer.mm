#import "PlanServer.hpp"
#import "../shared/Wire.h"
#import "../shared/JSONFoundation.h"
#import <Security/Security.h>
#include "../shared/Framing.hpp"
#include <arpa/inet.h>
#include <sys/socket.h>
#include <unistd.h>
#ifndef SH_PROVISIONING_PORT
#define SH_PROVISIONING_PORT 18100
#endif

static void servePlan(int fd, SHIncomingPlan handler) {
    int yes = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof yes);
    struct timeval timeout = {5, 0};
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof timeout);
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof timeout);
    unsigned char bytes[32];
    if (SecRandomCopyBytes(kSecRandomDefault, sizeof bytes, bytes) != errSecSuccess)
        return;
    NSString *nonce = SHHex([NSData dataWithBytes:bytes length:sizeof bytes]);
    if (!shjson::writeMessage(fd, shjson::Challenge{SHStdString(nonce)}))
        return;
    auto peer = shjson::readMessage<shjson::Authentication>(fd);
    if (!peer || !SHSame(SHString(peer->mac), SHMAC(@"provision-client:", nonce)) ||
        !shjson::writeMessage(fd,
                              shjson::Authentication{SHStdString(SHMAC(@"provision-app:", nonce))}))
        return;
    auto request = shjson::readMessage<shjson::ProvisioningRequest>(fd);
    if (!request)
        return;
    dispatch_semaphore_t finished = dispatch_semaphore_create(0);
    NSLock *lock = [NSLock new];
    __block NSString *status = nil;
    handler(*request, NSProcessInfo.processInfo.systemUptime + 280, ^(NSString *value) {
        [lock lock];
        if (!status) {
            status = [value copy] ?: @"failure";
            dispatch_semaphore_signal(finished);
        }
        [lock unlock];
    });
    if (dispatch_semaphore_wait(finished,
                                dispatch_time(DISPATCH_TIME_NOW, 1795LL * NSEC_PER_SEC)) != 0)
        return;
    [lock lock];
    NSString *response = status;
    [lock unlock];
    if (![response isEqual:@"success"] && ![response isEqual:@"cancel"] &&
        ![response isEqual:@"unknown"])
        response = @"failure";
    bool delivered = shjson::writeJSON(fd, shjson::JSON{{"status", SHStdString(response)}});
    NSLog(@"SIMHarbor native install response: %@, sent=%d", response, delivered);
}
void SHStartPlanServer(SHIncomingPlan handler) {
    if (!handler)
        return;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        SHIncomingPlan receiver = [handler copy];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            for (;;) {
                int server = socket(AF_INET, SOCK_STREAM, 0), yes = 1;
                if (server < 0) {
                    sleep(1);
                    continue;
                }
                setsockopt(server, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof yes);
                struct sockaddr_in address = {};
                address.sin_len = sizeof address;
                address.sin_family = AF_INET;
                address.sin_port = htons(SH_PROVISIONING_PORT);
                address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
                if (bind(server, (struct sockaddr *)&address, sizeof address) ||
                    listen(server, 4)) {
                    close(server);
                    sleep(1);
                    continue;
                }
                for (;;) {
                    int fd = accept(server, nullptr, nullptr);
                    if (fd < 0) {
                        if (errno == EINTR)
                            continue;
                        break;
                    }
                    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                        @autoreleasepool {
                            servePlan(fd, receiver);
                            close(fd);
                        }
                    });
                }
                close(server);
                sleep(1);
            }
        });
    });
}
