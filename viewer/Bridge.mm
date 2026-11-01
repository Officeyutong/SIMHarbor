#import "TraceLog.h"
#import "Localization.h"
#import "Bridge.h"
#import "../shared/Wire.h"
#import "../shared/JSONFoundation.h"
#import <arpa/inet.h>
#import <Security/Security.h>
#import <errno.h>
#import <string.h>
@interface SHBridge () {
    int _peer;
    NSRecursiveLock *_lock;
}
@end
@implementation SHBridge
+ (instancetype)shared {
    static SHBridge *b;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        b = [SHBridge new];
        b->_peer = -1;
        b->_lock = [NSRecursiveLock new];
    });
    return b;
}
- (BOOL)connected {
    [_lock lock];
    BOOL yes = _peer >= 0;
    [_lock unlock];
    return yes;
}
- (void)start {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            while (1) {
                @autoreleasepool {
                    int server = socket(AF_INET, SOCK_STREAM, 0), yes = 1;
                    if (server < 0) {
                        [[SHTraceLog shared]
                            event:[NSString stringWithFormat:
                                                @"IPC socket creation failed: %s (%d); retrying.",
                                                strerror(errno), errno]];
                        sleep(1);
                        continue;
                    }
                    setsockopt(server, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof yes);
                    setsockopt(server, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof yes);
                    struct sockaddr_in addr = {0};
                    addr.sin_len = sizeof addr;
                    addr.sin_family = AF_INET;
                    addr.sin_port = htons(SH_PORT);
                    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
                    if (bind(server, (struct sockaddr *)&addr, sizeof addr) || listen(server, 2)) {
                        int code = errno;
                        [[SHTraceLog shared]
                            event:[NSString stringWithFormat:
                                                @"IPC listener failed to start: %s (%d); retrying.",
                                                strerror(code), code]];
                        close(server);
                        sleep(1);
                        continue;
                    }
                    [[SHTraceLog shared]
                        event:[NSString
                                  stringWithFormat:@"IPC listener started on loopback port %d.",
                                                   SH_PORT]];
                    while (1) {
                        @autoreleasepool {
                            int fd = accept(server, NULL, NULL);
                            if (fd < 0) {
                                int code = errno;
                                if (code == EINTR)
                                    continue;
                                [[SHTraceLog shared]
                                    event:
                                        [NSString
                                            stringWithFormat:
                                                @"IPC accept failed: %s (%d); rebuilding listener.",
                                                strerror(code), code]];
                                break;
                            }
                            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof yes);
                            struct timeval timeout = {5, 0};
                            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof timeout);
                            setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof timeout);
                            unsigned char bytes[32];
                            if (SecRandomCopyBytes(kSecRandomDefault, sizeof bytes, bytes) !=
                                errSecSuccess) {
                                close(fd);
                                continue;
                            }
                            NSString *nonce = SHHex([NSData dataWithBytes:bytes length:32]);
                            bool ok =
                                shjson::writeMessage(fd, shjson::Challenge{SHStdString(nonce)});
                            auto reply =
                                ok ? shjson::readMessage<shjson::Authentication>(fd) : std::nullopt;
                            if (!reply ||
                                !SHSame(SHString(reply->mac), SHMAC(@"commcenter:", nonce)) ||
                                !shjson::writeMessage(fd, shjson::Authentication{SHStdString(
                                                              SHMAC(@"app:", nonce))})) {
                                close(fd);
                                continue;
                            }
                            [self->_lock lock];
                            if (self->_peer >= 0) {
                                char b;
                                ssize_t n = recv(self->_peer, &b, 1, MSG_PEEK | MSG_DONTWAIT);
                                if (n == 0 || (n < 0 && errno != EAGAIN && errno != EWOULDBLOCK)) {
                                    close(self->_peer);
                                    self->_peer = -1;
                                }
                            }
                            if (self->_peer >= 0)
                                close(fd);
                            else {
                                timeout.tv_sec = 35;
                                setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof timeout);
                                self->_peer = fd;
                                [[SHTraceLog shared] event:@"IPC peer authenticated."];
                            }
                            [self->_lock unlock];
                        }
                    }
                    close(server);
                    sleep(1);
                }
            }
        });
    });
}
- (std::optional<shjson::Reply>)request:(const shjson::Request &)body error:(NSError **)error {
    [_lock lock];
    auto request = body;
    request.id = SHStdString(NSUUID.UUID.UUIDString);
    std::optional<shjson::Reply> reply;
    auto operation = shjson::JSON(request.op);
    NSString *op =
        operation.is_string() ? SHString(operation.get_ref<const std::string &>()) : @"unknown";
    NSString *identifier = SHString(request.id);
    [[SHTraceLog shared] event:[NSString stringWithFormat:@"IPC TX id=%@ op=%@", identifier, op]];
    if (request.op == shjson::Operation::Transmit)
        [[SHTraceLog shared] frame:[@"APDU TX " stringByAppendingString:identifier]
                              data:SHUnhex(SHString(request.hex))];
    else if (request.op == shjson::Operation::Open)
        [[SHTraceLog shared]
            event:[NSString stringWithFormat:@"CHANNEL OPEN slot=%d AID=%@",
                                             request.slot.value_or(0), SHString(request.aid)]];
    if (_peer >= 0 && shjson::writeMessage(_peer, request))
        reply = shjson::readReply(_peer, request.op);
    if (!reply || reply->id != request.id) {
        if (_peer >= 0)
            close(_peer);
        _peer = -1;
        reply.reset();
    }
    auto transmission = shjson::body<shjson::TransmitReply>(reply);
    if (transmission) {
        NSData *rx = SHUnhex(SHString(transmission->hex));
        [[SHTraceLog shared] frame:[@"APDU RX " stringByAppendingString:identifier] data:rx];
        if (rx.length >= 2) {
            const auto *bytes = static_cast<const uint8_t *>(rx.bytes);
            [[SHTraceLog shared]
                event:[NSString stringWithFormat:@"APDU SW=%02X%02X", bytes[rx.length - 2],
                                                 bytes[rx.length - 1]]];
        }
    } else if (reply)
        [[SHTraceLog shared]
            event:[@"IPC RX "
                      stringByAppendingString:SHString(shjson::dump(shjson::JSON(*reply)))]];
    NSString *message =
        !reply ? @"Card service is disconnected. Keep the app in the foreground and refresh later."
        : !reply->ok ? (reply->error.empty() ? @"Card operation failed" : SHString(reply->error))
                     : nil;
    if (message) {
        [[SHTraceLog shared] event:[@"IPC ERROR " stringByAppendingString:message]];
        if (error) {
            int code = 0;
            NSString *display = SHL(message);
            if (sscanf(message.UTF8String, "Card transport failed (%d).", &code) == 1)
                display = [NSString stringWithFormat:SHL(@"Card transport failed (%d)."), code];
            *error = [NSError errorWithDomain:@"SIMHarbor"
                                         code:1
                                     userInfo:@{
                                         NSLocalizedDescriptionKey : display,
                                         @"SHErrorEnglish" : message
                                     }];
        }
    }
    [_lock unlock];
    return message ? std::nullopt : reply;
}
@end
