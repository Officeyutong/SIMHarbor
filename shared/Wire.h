#pragma once
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonHMAC.h>
#import <sys/socket.h>
#import <unistd.h>
#import "PairingKey.h"
// Public wire protocol constant; the generated header contains only pairing material.
#ifndef SH_PORT
#define SH_PORT 18099
#endif
static inline NSString *SHHex(NSData *d) {
    const unsigned char *b = (const unsigned char *)d.bytes;
    NSMutableString *s = [NSMutableString string];
    for (NSUInteger i = 0; i < d.length; i++)
        [s appendFormat:@"%02x", b[i]];
    return s;
}
static inline NSData *SHUnhex(NSString *s) {
    if (![s isKindOfClass:NSString.class] || s.length % 2 || s.length > 131076)
        return nil;
    NSMutableData *d = [NSMutableData data];
    for (NSUInteger i = 0; i < s.length; i += 2) {
        unsigned x;
        NSString *t = [s substringWithRange:NSMakeRange(i, 2)];
        NSScanner *sc = [NSScanner scannerWithString:t];
        if (![sc scanHexInt:&x] || !sc.isAtEnd)
            return nil;
        uint8_t b = x;
        [d appendBytes:&b length:1];
    }
    return d;
}
static inline NSString *SHMAC(NSString *role, NSString *nonce) {
    NSData *k = [SH_PAIRING_KEY dataUsingEncoding:NSUTF8StringEncoding],
           *m = [[role stringByAppendingString:nonce] dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char out[32];
    CCHmac(kCCHmacAlgSHA256, k.bytes, k.length, m.bytes, m.length, out);
    return SHHex([NSData dataWithBytes:out length:32]);
}
static inline BOOL SHSame(NSString *a, NSString *b) {
    NSData *x = [a dataUsingEncoding:NSUTF8StringEncoding],
           *y = [b dataUsingEncoding:NSUTF8StringEncoding];
    if (x.length != y.length || !x.length)
        return NO;
    const uint8_t *p = (const uint8_t *)x.bytes, *q = (const uint8_t *)y.bytes;
    uint8_t diff = 0;
    for (NSUInteger i = 0; i < x.length; i++)
        diff |= p[i] ^ q[i];
    return diff == 0;
}
#ifdef __cplusplus
#include "Framing.hpp"
#endif
