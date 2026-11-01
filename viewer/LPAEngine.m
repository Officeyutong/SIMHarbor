#import "TraceLog.h"
#import "ErrorDiagnostics.h"
#import "SignalCodec.h"
#import <euicc/euicc.private.h>
#import "Localization.h"
#import "LPAEngine.h"
#import "Bridge.h"
#import "../shared/Wire.h"
#import <Security/Security.h>
#import <dlfcn.h>
#import <euicc/euicc.h>
#import <euicc/es10c.h>
#import <euicc/es10a.h>
#import <euicc/es10c_ex.h>
#import <euicc/es9p.h>
#import <euicc/es8p.h>

@interface SHTLS : NSObject <NSURLSessionDelegate>
@end
@implementation SHTLS
- (void)URLSession:(NSURLSession *)s
    didReceiveChallenge:(NSURLAuthenticationChallenge *)c
      completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))done {
    if (![c.protectionSpace.authenticationMethod isEqual:NSURLAuthenticationMethodServerTrust]) {
        done(NSURLSessionAuthChallengePerformDefaultHandling, nil);
        return;
    }
    SecTrustRef trust = c.protectionSpace.serverTrust;
    NSString *host = c.protectionSpace.host;
    SecPolicyRef policy = SecPolicyCreateSSL(true, (__bridge CFStringRef)host);
    SecTrustSetPolicies(trust, policy);
    CFRelease(policy);
    NSData *pem =
        [NSData dataWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"gsma-rsp2-root-ci1"
                                                                     ofType:@"pem"]];
    NSString *t = [[NSString alloc] initWithData:pem encoding:NSUTF8StringEncoding];
    t = [[t stringByReplacingOccurrencesOfString:@"-----BEGIN CERTIFICATE-----" withString:@""]
        stringByReplacingOccurrencesOfString:@"-----END CERTIFICATE-----"
                                  withString:@""];
    NSData *der =
        [[NSData alloc] initWithBase64EncodedString:t ?: @""
                                            options:NSDataBase64DecodingIgnoreUnknownCharacters];
    SecCertificateRef cert =
        der ? SecCertificateCreateWithData(NULL, (__bridge CFDataRef)der) : NULL;
    if (cert) {
        SecTrustSetAnchorCertificates(trust, (__bridge CFArrayRef) @[ (__bridge id)cert ]);
        SecTrustSetAnchorCertificatesOnly(trust, false);
        CFRelease(cert);
    }
    if (SecTrustEvaluateWithError(trust, NULL))
        done(NSURLSessionAuthChallengeUseCredential, [NSURLCredential credentialForTrust:trust]);
    else
        done(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
}
- (void)URLSession:(NSURLSession *)s
                          task:(NSURLSessionTask *)task
    willPerformHTTPRedirection:(NSHTTPURLResponse *)response
                    newRequest:(NSURLRequest *)req
             completionHandler:(void (^)(NSURLRequest *))done {
    done(nil);
}
@end

@interface SHLPA ()
@property(nonatomic, copy, readwrite) NSString *expectedEID;
@property(nonatomic, strong) NSError *transportError;
@property(nonatomic, copy) NSDictionary *lastHTTPDiagnostic;
@property(nonatomic, copy) NSDictionary *lastAPDUDiagnostic;
@property(nonatomic, copy) NSDictionary *installationDiagnostic;
@property(nonatomic) BOOL customSession;
@property(nonatomic) NSUInteger customCalls;
@property(nonatomic) NSUInteger customBytes;
@end
static SHLPA *owner(struct euicc_ctx *c) { return (__bridge SHLPA *)c->userdata; }
static int connectCard(struct euicc_ctx *c) { return 0; }
static void disconnectCard(struct euicc_ctx *c) {}
static int openCard(struct euicc_ctx *c, const uint8_t *aid, uint8_t n) {
    SHLPA *o = owner(c);
    NSError *e = nil;
    NSDictionary *r = [[SHBridge shared] request:@{
        @"op" : @"open",
        @"slot" : @(o.slot),
        @"aid" : SHHex([NSData dataWithBytes:aid length:n])
    }
                                           error:&e];
    o.transportError = e;
    return r ? [r[@"channel"] intValue] : -1;
}
static void closeCard(struct euicc_ctx *c, uint8_t n) {
    NSError *e = nil;
    [[SHBridge shared] request:@{@"op" : @"close"} error:&e];
    if (e)
        owner(c).transportError = e;
}
static int transmitCard(struct euicc_ctx *c, uint8_t **rx, uint32_t *rn, const uint8_t *tx,
                        uint32_t tn) {
    SHLPA *o = owner(c);
    if (o.customSession && ++o.customCalls > 4096) {
        o.transportError = SHError(20, @"Custom signal response limit exceeded.");
        return -1;
    }
    NSError *e = nil;
    NSDictionary *r = [[SHBridge shared]
        request:@{@"op" : @"transmit", @"hex" : SHHex([NSData dataWithBytes:tx length:tn])}
          error:&e];
    owner(c).transportError = e;
    NSData *d = SHUnhex(r[@"hex"]);
    NSMutableDictionary *diagnostic = [NSMutableDictionary dictionary];
    if (tn >= 4)
        diagnostic[@"commandHeader"] = SHHex([NSData dataWithBytes:tx length:4]);
    if (d.length >= 2) {
        diagnostic[@"statusWord"] = SHHex([d subdataWithRange:NSMakeRange(d.length - 2, 2)]);
        diagnostic[@"responseHex"] =
            SHHex([d subdataWithRange:NSMakeRange(0, MIN(d.length, (NSUInteger)8192))]);
        diagnostic[@"responseBytes"] = @(d.length);
        diagnostic[@"truncated"] = @(d.length > 8192);
    }
    o.lastAPDUDiagnostic = diagnostic;
    if (d.length < 2)
        return -1;
    if (o.customSession && (o.customBytes += d.length) > 1024 * 1024) {
        o.transportError = SHError(20, @"Custom signal response limit exceeded.");
        return -1;
    }
    *rx = malloc(d.length);
    if (!*rx)
        return -1;
    memcpy(*rx, d.bytes, d.length);
    *rn = (uint32_t)d.length;
    return 0;
}
static int httpTransmit(struct euicc_ctx *c, const char *url, uint32_t *status, uint8_t **rx,
                        uint32_t *rn, const uint8_t *tx, uint32_t tn, const char **headers) {
    @autoreleasepool {
        SHLPA *o = owner(c);
        NSString *trace = NSUUID.UUID.UUIDString;
        NSURL *u = [NSURL URLWithString:@(url)];
        o.lastHTTPDiagnostic =
            @{@"requestId" : trace, @"url" : u.absoluteString ?: @"", @"method" : @"POST"};
        if (![u.scheme.lowercaseString isEqual:@"https"] || !u.host.length || u.user || u.password)
            return -1;
        NSMutableURLRequest *req =
            [NSMutableURLRequest requestWithURL:u
                                    cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                timeoutInterval:45];
        req.HTTPMethod = @"POST";
        req.HTTPBody = [NSData dataWithBytes:tx length:tn];
        for (int i = 0; headers && headers[i]; i++) {
            NSString *h = @(headers[i]);
            NSRange r = [h rangeOfString:@":"];
            if (r.location != NSNotFound)
                [req setValue:[[h substringFromIndex:r.location + 1]
                                  stringByTrimmingCharactersInSet:NSCharacterSet
                                                                      .whitespaceCharacterSet]
                    forHTTPHeaderField:[h substringToIndex:r.location]];
        }
        [[SHTraceLog shared]
            event:[NSString stringWithFormat:@"HTTP TX id=%@ POST %@ headers=%@", trace,
                                             u.absoluteString, req.allHTTPHeaderFields]];
        [[SHTraceLog shared] frame:[NSString stringWithFormat:@"HTTP TX BODY id=%@", trace]
                              data:req.HTTPBody];
        NSURLSessionConfiguration *conf = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        conf.connectionProxyDictionary = @{};
        NSString *proxy = [NSUserDefaults.standardUserDefaults stringForKey:@"SHHTTPProxy"];
        if (proxy.length) {
            NSURL *p = [NSURL URLWithString:proxy];
            if ([p.scheme.lowercaseString isEqual:@"http"] && p.host.length && p.port && !p.user &&
                !p.password) {
                conf.connectionProxyDictionary = @{
                    @"HTTPEnable" : @1,
                    @"HTTPProxy" : p.host,
                    @"HTTPPort" : p.port,
                    @"HTTPSEnable" : @1,
                    @"HTTPSProxy" : p.host,
                    @"HTTPSPort" : p.port
                };
            } else {
                return -1;
            }
        }
        conf.HTTPCookieStorage = nil;
        conf.URLCache = nil;
        conf.timeoutIntervalForResource = 60;
        SHTLS *delegate = [SHTLS new];
        NSURLSession *session = [NSURLSession sessionWithConfiguration:conf
                                                              delegate:delegate
                                                         delegateQueue:nil];
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        __block NSData *body = nil;
        __block NSHTTPURLResponse *response = nil;
        __block NSError *err = nil;
        NSURLSessionDataTask *task =
            [session dataTaskWithRequest:req
                       completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
                           body = d;
                           response = (NSHTTPURLResponse *)r;
                           err = e;
                           dispatch_semaphore_signal(sem);
                       }];
        [task resume];
        BOOL timed =
            dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 65 * NSEC_PER_SEC)) != 0;
        if (timed)
            [task cancel];
        [session finishTasksAndInvalidate];
        NSMutableDictionary *httpDiagnostic = [o.lastHTTPDiagnostic mutableCopy];
        httpDiagnostic[@"status"] = @(response.statusCode);
        NSDictionary *json = body.length && body.length <= 512 * 1024
                                 ? [NSJSONSerialization JSONObjectWithData:body options:0 error:nil]
                                 : nil;
        NSDictionary *header = [json isKindOfClass:NSDictionary.class] &&
                                       [json[@"header"] isKindOfClass:NSDictionary.class]
                                   ? json[@"header"]
                                   : nil;
        NSDictionary *execution =
            [header[@"functionExecutionStatus"] isKindOfClass:NSDictionary.class]
                ? header[@"functionExecutionStatus"]
                : nil;
        if (execution)
            httpDiagnostic[@"functionExecutionStatus"] = execution;
        NSString *executionStatus =
            [execution[@"status"] isKindOfClass:NSString.class] ? execution[@"status"] : nil;
        if (response.statusCode >= 400 ||
            (executionStatus && ![executionStatus isEqual:@"Executed-Success"])) {
            NSData *limited =
                [body subdataWithRange:NSMakeRange(0, MIN(body.length, (NSUInteger)65536))];
            httpDiagnostic[@"responseBody"] = [[NSString alloc] initWithData:limited encoding:NSUTF8StringEncoding] ?: [limited base64EncodedStringWithOptions:0] ?: @"";
            httpDiagnostic[@"responseTruncated"] = @(body.length > 65536);
        }
        o.lastHTTPDiagnostic = httpDiagnostic;
        [[SHTraceLog shared]
            event:[NSString stringWithFormat:@"HTTP RX id=%@ status=%ld headers=%@", trace,
                                             (long)response.statusCode,
                                             response.allHeaderFields ?: @{}]];
        if (body.length <= 16 * 1024 * 1024)
            [[SHTraceLog shared] frame:[NSString stringWithFormat:@"HTTP RX BODY id=%@", trace]
                                  data:body];
        if (err)
            [[SHTraceLog shared] error:err];
        if (err || timed || body.length > 16 * 1024 * 1024) {
            NSString *message =
                err.code == NSURLErrorNotConnectedToInternet
                    ? @"No network access. Check your connection and allow SIMHarbor wireless data in Settings."
                    : (err.localizedDescription
                           ?: @"Server request timed out or the response was too large.");
            NSMutableDictionary *info = [@{
                NSLocalizedDescriptionKey : SHL(message),
                @"SHErrorEnglish" : err ? @"HTTP transport failed."
                                        : @"Server request timed out or the response was too large."
            } mutableCopy];
            if (err)
                info[NSUnderlyingErrorKey] = err;
            o.transportError = [NSError errorWithDomain:@"SIMHarbor" code:2 userInfo:info];
            return -1;
        }
        *status = (uint32_t)response.statusCode;
        *rn = (uint32_t)body.length;
        *rx = malloc(MAX((NSUInteger)1, body.length));
        if (!*rx)
            return -1;
        if (body.length)
            memcpy(*rx, body.bytes, body.length);
        return 0;
    }
}
static const struct euicc_apdu_interface apdu = {connectCard, disconnectCard, openCard,
                                                 closeCard,   transmitCard,   NULL};
static const struct euicc_http_interface http = {httpTransmit, NULL};
@implementation SHLPA
- (instancetype)init {
    return [self
        initWithSlot:(int)[NSUserDefaults.standardUserDefaults integerForKey:@"SHPreferredSlot"]];
}
- (instancetype)initWithSlot:(int)slot {
    return [self initWithSlot:slot expectedEID:nil];
}
- (instancetype)initWithSlot:(int)slot expectedEID:(NSString *)eid {
    if ((self = [super init])) {
        _slot = slot;
        _expectedEID = [eid copy];
    }
    return self;
}
+ (NSArray<NSDictionary *> *)availableSlots:(NSError **)error {
    NSDictionary *reply = [[SHBridge shared] request:@{@"op" : @"slots"} error:error];
    return reply[@"slots"];
}
+ (NSOperationQueue *)operationQueue {
    static NSOperationQueue *queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = [NSOperationQueue new];
        queue.name = @"com.simharbor.card.operations";
        queue.maxConcurrentOperationCount = 1;
    });
    return queue;
}
- (void)warn:(NSString *)english {
    self.lastWarning = SHL(english);
    [[SHTraceLog shared] event:[@"WARNING " stringByAppendingString:english]];
}
- (void)stage:(NSString *)s {
    [[SHTraceLog shared] event:s];
    if (self.progress)
        self.progress(SHL(s));
}
- (BOOL)begin:(struct euicc_ctx *)ctx error:(NSError **)e {
    return [self begin:ctx allowUnbound:NO error:e];
}
- (BOOL)begin:(struct euicc_ctx *)ctx allowUnbound:(BOOL)allowUnbound error:(NSError **)e {
    memset(ctx, 0, sizeof(*ctx));
    if (self.slot < 1 || (!allowUnbound && !self.expectedEID.length)) {
        if (e)
            *e = SHError(
                30, @"Select an eUICC slot and refresh its profile list before this operation.");
        return NO;
    }
    ctx->userdata = (__bridge void *)self;
    NSInteger mss = [NSUserDefaults.standardUserDefaults integerForKey:@"SHMSS"];
    if (mss >= 6 && mss <= 255)
        ctx->es10x_mss = (uint8_t)mss;
    ctx->apdu.interface = &apdu;
    ctx->http.interface = &http;
    self.transportError = nil;
    self.lastHTTPDiagnostic = nil;
    self.lastAPDUDiagnostic = nil;
    self.installationDiagnostic = nil;
    self.lastWarning = nil;
    [self stage:@"Connecting to the removable card…"];
    if (euicc_init(ctx)) {
        if (e)
            *e =
                self.transportError
                    ?: [NSError
                           errorWithDomain:@"SIMHarbor"
                                      code:1
                                  userInfo:@{
                                      NSLocalizedDescriptionKey : SHL(
                                          @"Unable to access the eUICC. Check that the card is inserted and try again."),
                                      @"SHErrorEnglish" :
                                          @"Unable to access the eUICC. Check that the card is inserted and try again."
                                  }];
        return NO;
    }
    if (self.expectedEID.length) {
        char *eid = NULL;
        int rc = es10c_get_eid(ctx, &eid);
        NSString *actual = eid ? @(eid) : @"";
        BOOL matches = !rc && [actual isEqual:self.expectedEID];
        free(eid);
        if (!matches) {
            NSError *failure = SHError(
                31,
                @"The card in this slot has changed or is unavailable. Refresh and select the card again before continuing.");
            euicc_fini(ctx);
            if (e)
                *e = failure;
            return NO;
        }
    }
    return YES;
}
- (void)failure:(NSString *)stage ctx:(struct euicc_ctx *)ctx error:(NSError **)e {
    [[SHTraceLog shared] event:[@"LPA ERROR " stringByAppendingString:stage]];
    NSMutableDictionary *details = [NSMutableDictionary dictionary];
    details[@"logicalSlot"] = @(self.slot);
    details[@"es9p"] = @{
        @"subjectCode" : [NSString stringWithUTF8String:ctx->http.status.subjectCode] ?: @"",
        @"reasonCode" : [NSString stringWithUTF8String:ctx->http.status.reasonCode] ?: @"",
        @"subjectIdentifier" : [NSString stringWithUTF8String:ctx->http.status.subjectIdentifier]
            ?: @"",
        @"message" : [NSString stringWithUTF8String:ctx->http.status.message] ?: @""
    };
    if (self.lastHTTPDiagnostic)
        details[@"http"] = self.lastHTTPDiagnostic;
    if (self.lastAPDUDiagnostic)
        details[@"apdu"] = self.lastAPDUDiagnostic;
    if (self.installationDiagnostic)
        details[@"es10b"] = self.installationDiagnostic;
    NSError *failure = SHDiagnosticError(stage, details, self.transportError);
    if (e)
        *e = failure;
}
- (BOOL)allowOwnNetworking:(NSError **)e {
    void *h = dlopen("/System/Library/Frameworks/CoreTelephony.framework/CoreTelephony", RTLD_LAZY);
    typedef void *(*Create)(CFAllocatorRef, void *, void *);
    typedef int64_t (*Policy)(void *, CFStringRef, CFDictionaryRef);
    Create create = h ? (Create)dlsym(h, "_CTServerConnectionCreate") : NULL;
    Policy apply = h ? (Policy)dlsym(h, "_CTServerConnectionSetCellularUsagePolicy") : NULL;
    NSString *identifier = NSBundle.mainBundle.bundleIdentifier;
    BOOL ok = NO;
    if (create && apply && [identifier isEqual:@"com.estk.viewer"]) {
        void *connection = create(kCFAllocatorDefault, NULL, NULL);
        if (connection) {
            NSDictionary *policy = @{
                @"kCTCellularDataUsagePolicy" : @"kCTCellularDataUsagePolicyAlwaysAllow",
                @"kCTWiFiDataUsagePolicy" : @"kCTCellularDataUsagePolicyAlwaysAllow"
            };
            int64_t rc = apply(connection, (__bridge CFStringRef)identifier,
                               (__bridge CFDictionaryRef)policy);
            ok = rc == 0;
            CFRelease(connection);
        }
    }
    if (ok) {
        [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"SHNetworkConsent"];
        return YES;
    }
    if (e)
        *e = [NSError
            errorWithDomain:@"SIMHarbor"
                       code:4
                   userInfo:@{
                       NSLocalizedDescriptionKey : SHL(
                           @"Unable to update this app's wireless data policy. Check network restrictions in Settings."),
                       @"SHErrorEnglish" :
                           @"Unable to update this app's wireless data policy. Check network restrictions in Settings."
                   }];
    return NO;
}
- (BOOL)checkNetwork:(NSError **)e {
    struct euicc_ctx c = {0};
    c.userdata = (__bridge void *)self;
    self.transportError = nil;
    uint8_t *data = NULL;
    uint32_t n = 0, status = 0;
    const char *headers[] = {"Content-Type: application/json", NULL};
    int rc = httpTransmit(&c, "https://rsp1.cmlink.com/", &status, &data, &n, (const uint8_t *)"{}",
                          2, headers);
    free(data);
    if (rc || !status) {
        if (e)
            *e = self.transportError;
        return NO;
    }
    return YES;
}
- (NSDictionary *)readCard:(NSError **)e {
    struct euicc_ctx c;
    if (![self begin:&c allowUnbound:YES error:e])
        return nil;
    NSMutableArray *items = [NSMutableArray array];
    char *eid = NULL;
    struct es10c_profile_info_list *list = NULL;
    struct es10c_ex_euiccinfo2 info = {0};
    NSDictionary *result = nil;
    @try {
        [self stage:@"Reading the card…"];
        if (es10c_get_eid(&c, &eid) || es10c_get_profiles_info(&c, &list)) {
            [self failure:@"Card read failed" ctx:&c error:e];
            return nil;
        }
        for (struct es10c_profile_info_list *p = list; p; p = p->next)
            [items addObject:@{
                @"iccid" : @(p->iccid),
                @"name" : (p->profileNickname && p->profileNickname[0])
                    ? @(p->profileNickname)
                    : (p->profileName ? @(p->profileName) : @"eSIM"),
                @"provider" : p->serviceProviderName ? @(p->serviceProviderName) : @"",
                @"enabled" : @(p->profileState == ES10C_PROFILE_STATE_ENABLED),
                @"aid" : @(p->isdpAid),
                @"profileClass" : @(p->profileClass),
                @"originalName" : p->profileName ? @(p->profileName) : @""
            }];
        NSNumber *space = @0;
        if (!es10c_ex_get_euiccinfo2(&c, &info))
            space = @(info.extCardResource.freeNonVolatileMemory);
        struct es10a_euicc_configured_addresses addresses = {0};
        es10a_get_euicc_configured_addresses(&c, &addresses);
        result = @{
            @"logicalSlot" : @(self.slot),
            @"eid" : eid ? @(eid) : @"",
            @"profiles" : items,
            @"freeBytes" : space,
            @"freeVolatileBytes" : @(info.extCardResource.freeVolatileMemory),
            @"firmware" : info.euiccFirmwareVer ? @(info.euiccFirmwareVer) : @"",
            @"rspVersion" : info.svn ? @(info.svn) : @"",
            @"profileVersion" : info.profileVersion ? @(info.profileVersion) : @"",
            @"defaultServer" : addresses.defaultDpAddress ? @(addresses.defaultDpAddress) : @"",
            @"discoveryServer" : addresses.rootDsAddress ? @(addresses.rootDsAddress) : @""
        };
        es10a_euicc_configured_addresses_free(&addresses);
        if (!self.expectedEID.length && eid)
            self.expectedEID = @(eid);
    } @finally {
        free(eid);
        es10c_profile_info_list_free_all(list);
        es10c_ex_euiccinfo2_free(&info);
        euicc_fini(&c);
    }
    return result;
}
- (BOOL)notify:(unsigned long)seq ctx:(struct euicc_ctx *)c {
    struct es10b_pending_notification n = {0};
    BOOL ok = NO;
    const char *old = c->http.server_address;
    NSString *host = nil;
    if (!es10b_retrieve_notifications_list(c, &n, seq) && n.notificationAddress) {
        host = [@(n.notificationAddress)
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if ([host hasPrefix:@"https://"])
            host = [NSURL URLWithString:host].host;
        if (host.length && [host rangeOfString:@"/"].location == NSNotFound) {
            c->http.server_address = host.UTF8String;
            if (!es9p_handle_notification(c, n.b64_PendingNotification) &&
                !es10b_remove_notification_from_list(c, seq))
                ok = YES;
        }
    }
    c->http.server_address = old;
    es10b_pending_notification_free(&n);
    return ok;
}
- (BOOL)download:(NSString *)code confirmation:(NSString *)confirmation error:(NSError **)e {
    NSString *s =
        [code stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([s.lowercaseString hasPrefix:@"lpa:"])
        s = [s substringFromIndex:4];
    NSArray *t = [s componentsSeparatedByString:@"$"];
    if (t.count < 3 || ![t[0] isEqual:@"1"] || ![t[1] length] || ![t[2] length] ||
        [t[1] rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"/:@?# "]]
                .location != NSNotFound) {
        if (e)
            *e = [NSError
                errorWithDomain:@"SIMHarbor"
                           code:3
                       userInfo:@{
                           NSLocalizedDescriptionKey :
                               SHL(@"Invalid activation code. Use LPA:1$server$activation-token."),
                           @"SHErrorEnglish" :
                               @"Invalid activation code. Use LPA:1$server$activation-token."
                       }];
        return NO;
    }
    if (t.count > 4 && [t[4] isEqual:@"1"] && !confirmation.length) {
        if (e)
            *e = [NSError
                errorWithDomain:@"SIMHarbor"
                           code:3
                       userInfo:@{
                           NSLocalizedDescriptionKey :
                               SHL(@"This activation code requires a confirmation code."),
                           @"SHErrorEnglish" : @"This activation code requires a confirmation code."
                       }];
        return NO;
    }
    if (self.downloadIMEI.length &&
        ([self.downloadIMEI
             rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet]
                 .location != NSNotFound ||
         self.downloadIMEI.length != 15)) {
        if (e)
            *e =
                [NSError errorWithDomain:@"SIMHarbor"
                                    code:3
                                userInfo:@{
                                    NSLocalizedDescriptionKey :
                                        SHL(@"IMEI must contain 15 digits, or be blank."),
                                    @"SHErrorEnglish" : @"IMEI must contain 15 digits, or be blank."
                                }];
        return NO;
    }
    struct euicc_ctx c;
    if (![self begin:&c error:e])
        return NO;
    BOOL installed = NO;
    NSString *host = t[1], *token = t[2];
    c.http.server_address = host.UTF8String;
    struct es10b_load_bound_profile_package_result result = {0};
    NSString *failed = nil;
    @try {
        [self stage:@"Verifying the card…"];
        if (es10b_get_euicc_challenge_and_info(&c)) {
            failed = @"Failed to read authentication information";
            return NO;
        }
        [self stage:@"Connecting to the operator…"];
        if (es9p_initiate_authentication(&c)) {
            failed = @"Server authentication initialization failed";
            return NO;
        }
        [self stage:@"Verifying the operator certificate…"];
        if (es10b_authenticate_server(&c, token.UTF8String,
                                      self.downloadIMEI.length ? self.downloadIMEI.UTF8String
                                                               : NULL)) {
            failed = @"The card rejected server authentication";
            return NO;
        }
        [self stage:@"Verifying the activation code…"];
        if (es9p_authenticate_client(&c)) {
            failed = @"Operator authentication failed";
            return NO;
        }
        [self stage:@"Preparing download…"];
        if (es10b_prepare_download(&c, confirmation.length ? confirmation.UTF8String : NULL)) {
            failed = @"Download preparation failed. Check the confirmation code";
            return NO;
        }
        [self stage:@"Downloading the encrypted profile…"];
        if (es9p_get_bound_profile_package(&c)) {
            failed = @"Encrypted profile download failed";
            return NO;
        }
        [self stage:@"Installing the profile. Keep the app in the foreground…"];
        if (es10b_load_bound_profile_package(&c, &result)) {
            self.installationDiagnostic = @{
                @"errorReason" : @(result.errorReason),
                @"bppCommandId" : @(result.bppCommandId),
                @"sequenceNumber" : @(result.seqNumber)
            };
            failed = @"Profile installation failed";
            return NO;
        }
        installed = YES;
        [self stage:@"Confirming the installation result…"];
        if ([self autoNotify:@"SHNotifyDownload"] && ![self notify:result.seqNumber ctx:&c])
            [self
                warn:
                    @"Profile installed, but the result notification is pending. Use Notifications to retry."];
        return YES;
    } @finally {
        if (!installed) {
            [self failure:failed ?: @"Download failed" ctx:&c error:e];
            if (c.http._internal.transaction_id_bin)
                es10b_cancel_session(&c, ES10B_CANCEL_SESSION_REASON_ENDUSERREJECTION);
            if (c.http._internal.transaction_id_http)
                es9p_cancel_session(&c);
        }
        self.downloadIMEI = nil;
        free(result.iccid);
        euicc_http_cleanup(&c);
        euicc_fini(&c);
    }
}
- (BOOL)deleteProfile:(NSString *)iccid error:(NSError **)e {
    struct euicc_ctx c;
    if (![self begin:&c error:e])
        return NO;
    struct es10c_profile_info_list *list = NULL;
    struct es10b_notification_metadata_list *notes = NULL;
    BOOL success = NO;
    @try {
        [self stage:@"Checking the profile…"];
        if (es10c_get_profiles_info(&c, &list)) {
            [self failure:@"Failed to read the profile list" ctx:&c error:e];
            return NO;
        }
        BOOL found = NO;
        for (struct es10c_profile_info_list *p = list; p; p = p->next)
            if ([@(p->iccid) isEqual:iccid]) {
                found = YES;
                if (p->profileState != ES10C_PROFILE_STATE_DISABLED) {
                    [self failure:@"Disable this profile before deleting it." ctx:&c error:e];
                    return NO;
                }
            }
        if (!found) {
            [self failure:@"This profile is no longer on the card. Refresh the list."
                      ctx:&c
                    error:e];
            return NO;
        }
        [self stage:@"Deleting the profile…"];
        int rc = es10c_delete_profile(&c, iccid.UTF8String);
        if (rc) {
            [self
                failure:rc == 3 ? @"The profile policy does not allow deletion." : @"Delete failed"
                    ctx:&c
                  error:e];
            return NO;
        }
        success = YES;
        [self stage:@"Confirming the deletion result…"];
        if (!es10b_list_notification(&c, &notes)) {
            unsigned long newest = 0;
            BOOL have = NO;
            for (struct es10b_notification_metadata_list *p = notes; p; p = p->next)
                if (p->iccid && [iccid isEqual:@(p->iccid)] &&
                    p->profileManagementOperation == ES10B_PROFILE_MANAGEMENT_OPERATION_DELETE) {
                    if (!have || p->seqNumber > newest) {
                        newest = p->seqNumber;
                        have = YES;
                    }
                }
            if (have && [self autoNotify:@"SHNotifyDelete"] && ![self notify:newest ctx:&c])
                [self warn:@"Profile deleted, but the operator notification is pending."];
        }
        return success;
    } @finally {
        es10c_profile_info_list_free_all(list);
        es10b_notification_metadata_list_free_all(notes);
        euicc_http_cleanup(&c);
        euicc_fini(&c);
    }
}

- (BOOL)autoNotify:(NSString *)key {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    return [d objectForKey:key] ? [d boolForKey:key] : YES;
}
- (BOOL)setProfile:(NSString *)iccid enabled:(BOOL)enabled error:(NSError **)e {
    NSDictionary *before = [self readCard:e];
    if (!before)
        return NO;
    NSDictionary *target = nil;
    for (NSDictionary *p in before[@"profiles"])
        if ([p[@"iccid"] isEqual:iccid])
            target = p;
    if (!target) {
        if (e)
            *e =
                [NSError errorWithDomain:@"SIMHarbor"
                                    code:6
                                userInfo:@{
                                    NSLocalizedDescriptionKey :
                                        SHL(@"The target eSIM no longer exists. Refresh the list."),
                                    @"SHErrorEnglish" :
                                        @"The target eSIM no longer exists. Refresh the list."
                                }];
        return NO;
    }
    if ([target[@"enabled"] boolValue] == enabled)
        return YES;
    struct euicc_ctx c;
    if (![self begin:&c error:e])
        return NO;
    [self stage:enabled ? @"Enabling the profile and waiting for refresh…"
                        : @"Disabling the profile and waiting for refresh…"];
    BOOL refresh = [NSUserDefaults.standardUserDefaults objectForKey:@"SHRefresh"]
                       ? [NSUserDefaults.standardUserDefaults boolForKey:@"SHRefresh"]
                       : YES;
    int rc = enabled ? es10c_enable_profile(&c, iccid.UTF8String, refresh)
                     : es10c_disable_profile(&c, iccid.UTF8String, refresh);
    euicc_fini(&c);
    BOOL verified = NO;
    for (int i = 0; i < 30; i++) {
        [NSThread sleepForTimeInterval:1];
        NSError *readError = nil;
        NSDictionary *r = [self readCard:&readError];
        for (NSDictionary *p in r[@"profiles"])
            if ([p[@"iccid"] isEqual:iccid] && [p[@"enabled"] boolValue] == enabled)
                verified = YES;
        if (verified)
            break;
        if (rc > 0)
            break;
    }
    if (!verified) {
        if (e)
            *e = [NSError
                errorWithDomain:@"SIMHarbor"
                           code:6
                       userInfo:@{
                           NSLocalizedDescriptionKey : SHL(
                               rc == 3
                                   ? @"The profile policy does not allow this switch."
                                   : @"Unable to confirm the switch. Refresh later; do not repeat the switch immediately.")
                       }];
        return NO;
    }
    if ([self autoNotify:@"SHNotifySwitch"]) {
        struct euicc_ctx n;
        if ([self begin:&n error:nil]) {
            struct es10b_notification_metadata_list *list = NULL;
            if (!es10b_list_notification(&n, &list)) {
                unsigned long seq = 0;
                BOOL found = NO;
                for (struct es10b_notification_metadata_list *p = list; p; p = p->next)
                    if (p->iccid && [iccid isEqual:@(p->iccid)] &&
                        p->profileManagementOperation ==
                            (enabled ? ES10B_PROFILE_MANAGEMENT_OPERATION_ENABLE
                                     : ES10B_PROFILE_MANAGEMENT_OPERATION_DISABLE)) {
                        if (!found || p->seqNumber > seq) {
                            seq = p->seqNumber;
                            found = YES;
                        }
                    }
                if (found && ![self notify:seq ctx:&n])
                    [self warn:@"Profile state updated, but the operator notification is pending."];
            }
            es10b_notification_metadata_list_free_all(list);
            euicc_http_cleanup(&n);
            euicc_fini(&n);
        }
    }
    if (!refresh)
        [self
            warn:
                @"Card state updated without requesting refresh. Reinsertion may be needed to use the new profile."];
    return YES;
}
- (BOOL)renameProfile:(NSString *)iccid name:(NSString *)name error:(NSError **)e {
    if ([name lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 64) {
        if (e)
            *e = [NSError
                errorWithDomain:@"SIMHarbor"
                           code:7
                       userInfo:@{
                           NSLocalizedDescriptionKey :
                               SHL(@"Nickname is too long. Shorten it and try again."),
                           @"SHErrorEnglish" : @"Nickname is too long. Shorten it and try again."
                       }];
        return NO;
    }
    struct euicc_ctx c;
    if (![self begin:&c error:e])
        return NO;
    int rc = es10c_set_nickname(&c, iccid.UTF8String, name.UTF8String);
    if (rc)
        [self failure:@"Failed to change nickname" ctx:&c error:e];
    euicc_fini(&c);
    return rc == 0;
}
- (NSArray *)notifications:(NSError **)e {
    struct euicc_ctx c;
    if (![self begin:&c error:e])
        return nil;
    struct es10b_notification_metadata_list *list = NULL;
    NSMutableArray *items = [NSMutableArray array];
    int rc = es10b_list_notification(&c, &list);
    if (rc)
        [self failure:@"Failed to read notifications" ctx:&c error:e];
    else
        for (struct es10b_notification_metadata_list *p = list; p; p = p->next) {
            NSString *type = @"Other";
            switch (p->profileManagementOperation) {
            case ES10B_PROFILE_MANAGEMENT_OPERATION_INSTALL:
                type = @"Install";
                break;
            case ES10B_PROFILE_MANAGEMENT_OPERATION_DELETE:
                type = @"Delete";
                break;
            case ES10B_PROFILE_MANAGEMENT_OPERATION_ENABLE:
                type = @"Enable";
                break;
            case ES10B_PROFILE_MANAGEMENT_OPERATION_DISABLE:
                type = @"Disable";
                break;
            default:
                break;
            }
            [items addObject:@{
                @"sequence" : @(p->seqNumber),
                @"operation" : type,
                @"address" : p->notificationAddress ? @(p->notificationAddress) : @"",
                @"iccid" : p->iccid ? @(p->iccid) : @""
            }];
        }
    es10b_notification_metadata_list_free_all(list);
    euicc_fini(&c);
    return rc ? nil : items;
}
- (BOOL)processNotification:(unsigned long)seq removeOnly:(BOOL)remove error:(NSError **)e {
    struct euicc_ctx c;
    if (![self begin:&c error:e])
        return NO;
    BOOL ok = remove ? es10b_remove_notification_from_list(&c, seq) == 0 : [self notify:seq ctx:&c];
    if (!ok)
        [self failure:remove ? @"Failed to remove notification" : @"Failed to submit notification"
                  ctx:&c
                error:e];
    euicc_http_cleanup(&c);
    euicc_fini(&c);
    return ok;
}
- (BOOL)setDefaultServer:(NSString *)server error:(NSError **)e {
    if (server.length &&
        [server
            rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"/:@?# "]]
                .location != NSNotFound) {
        if (e)
            *e = [NSError
                errorWithDomain:@"SIMHarbor"
                           code:8
                       userInfo:@{
                           NSLocalizedDescriptionKey :
                               SHL(@"Enter only the SM-DP+ domain, without a URL path."),
                           @"SHErrorEnglish" : @"Enter only the SM-DP+ domain, without a URL path."
                       }];
        return NO;
    }
    struct euicc_ctx c;
    if (![self begin:&c error:e])
        return NO;
    int rc = es10a_set_default_dp_address(&c, server.UTF8String);
    if (rc)
        [self failure:@"Failed to change the default server" ctx:&c error:e];
    euicc_fini(&c);
    return rc == 0;
}
- (BOOL)resetCard:(NSString *)eid confirmation:(NSString *)confirmation error:(NSError **)e {
    NSDictionary *r = [self readCard:e];
    if (!r)
        return NO;
    if (![r[@"eid"] isEqual:eid] || ![confirmation isEqual:@"RESET"]) {
        if (e)
            *e = [NSError
                errorWithDomain:@"SIMHarbor"
                           code:9
                       userInfo:@{
                           NSLocalizedDescriptionKey :
                               SHL(@"Reset confirmation does not match. Operation cancelled."),
                           @"SHErrorEnglish" :
                               @"Reset confirmation does not match. Operation cancelled."
                       }];
        return NO;
    }
    struct euicc_ctx c;
    if (![self begin:&c error:e])
        return NO;
    int rc = es10c_euicc_memory_reset(&c);
    if (rc)
        [self failure:@"Reset did not complete. It may be blocked by card policy" ctx:&c error:e];
    euicc_fini(&c);
    return rc == 0;
}

- (NSArray<NSDictionary *> *)sendAPDUs:(NSArray<NSData *> *)commands
                          stopOnStatus:(BOOL)stop
                                 error:(NSError **)error {
    if (!commands.count || commands.count > 64) {
        if (error)
            *error = SHError(20, @"Enter between 1 and 64 APDUs.");
        return nil;
    }
    for (NSData *d in commands) {
        const char *issue = SHValidateAPDU(d.bytes, d.length);
        if (issue) {
            if (error)
                *error = SHError(20, @(issue));
            return nil;
        }
    }
    struct euicc_ctx c;
    if (![self begin:&c error:error])
        return nil;
    NSMutableArray *results = [NSMutableArray array];
    self.customSession = YES;
    self.customCalls = 0;
    self.customBytes = 0;
    @try {
        [self stage:@"Sending custom APDUs…"];
        for (NSData *d in commands) {
            NSMutableData *request = [d mutableCopy];
            uint8_t *b = request.mutableBytes;
            int cla = SHBindChannel(b[0], c.apdu._internal.logic_channel);
            if (cla < 0) {
                if (error)
                    *error = SHError(20, @"Unsupported logical channel.");
                break;
            }
            b[0] = (uint8_t)cla;
            uint8_t *rx = NULL;
            uint32_t n = 0;
            if (transmitCard(&c, &rx, &n, request.bytes, (uint32_t)request.length) < 0) {
                free(rx);
                if (error)
                    *error =
                        self.transportError
                            ?: SHError(
                                   20,
                                   @"Custom APDU transport failed. The command may have reached the card; do not resend automatically.");
                break;
            }
            NSData *response = [NSData dataWithBytes:rx length:n];
            unsigned sw = (rx[n - 2] << 8) | rx[n - 1];
            free(rx);
            [results addObject:@{
                @"tx" : SHHex(request),
                @"rx" : SHHex(response),
                @"sw" : [NSString stringWithFormat:@"%04X", sw]
            }];
            if (stop && sw != 0x9000) {
                if (error)
                    *error = SHError(
                        20,
                        @"Stopped after a non-9000 status. Check the response before continuing.");
                break;
            }
        }
    } @finally {
        euicc_fini(&c);
        self.customSession = NO;
        if (self.transportError && error && !*error)
            *error = self.transportError;
    }
    return results;
}
- (NSData *)sendDER:(NSData *)request error:(NSError **)error {
    NSInteger mss = [NSUserDefaults.standardUserDefaults integerForKey:@"SHMSS"];
    if (mss < 6 || mss > 255)
        mss = 120;
    const char *issue = SHValidateDER(request.bytes, request.length, (size_t)mss * 256);
    if (issue) {
        if (error)
            *error = SHError(20, @(issue));
        return nil;
    }
    struct euicc_ctx c;
    if (![self begin:&c error:error])
        return nil;
    if (c.apdu._internal.logic_channel > 3) {
        euicc_fini(&c);
        if (error)
            *error = SHError(20, @"Unsupported logical channel.");
        return nil;
    }
    self.customSession = YES;
    self.customCalls = 0;
    self.customBytes = 0;
    uint8_t *response = NULL;
    unsigned length = 0;
    NSData *result = nil;
    @try {
        [self stage:@"Sending custom ES10 DER…"];
        if (es10x_command(&c, &response, &length, request.bytes, (unsigned)request.length)) {
            if (error)
                *error =
                    self.transportError
                        ?: SHError(
                               20,
                               @"Custom DER request failed. Check the APDU trace before retrying.");
        } else
            result = [NSData dataWithBytes:response length:length];
    } @finally {
        free(response);
        euicc_fini(&c);
        self.customSession = NO;
        if (self.transportError && error && !*error)
            *error = self.transportError;
    }
    return result;
}
@end
