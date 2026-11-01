#import "../shared/JSONFoundation.h"
#import "../viewer/ErrorDiagnostics.h"
#import "../viewer/Localization.h"
#import "../viewer/LPAEngine.h"
#import <Foundation/Foundation.h>

extern "C" int SHErrorDiagnosticsCheck(void) {
    @autoreleasepool {
        SHLPA *first = [[SHLPA alloc] initWithSlot:1 expectedEID:@"fixture-card-one"];
        SHLPA *second = [[SHLPA alloc] initWithSlot:2 expectedEID:@"fixture-card-two"];
        if (first.slot != 1 || second.slot != 2 || [first.expectedEID isEqual:second.expectedEID] ||
            [SHLPA operationQueue] != [SHLPA operationQueue] ||
            [SHLPA operationQueue].maxConcurrentOperationCount != 1)
            return 6;
        SHLPA *unbound = [[SHLPA alloc] initWithSlot:1];
        NSError *unboundError = nil;
        if ([unbound download:@"LPA:1$example.invalid$fixture"
                 confirmation:nil
                        error:&unboundError] ||
            unboundError.code != 30)
            return 7;
        NSString *original = [NSUserDefaults.standardUserDefaults stringForKey:@"SHLanguage"];
        @try {
            for (NSString *language in @[ @"en", @"zh-Hans" ]) {
                [NSUserDefaults.standardUserDefaults setObject:language forKey:@"SHLanguage"];
                NSMutableDictionary *details = [@{
                    @"es9p" : @{
                        @"message" : @"unknown",
                        @"subjectCode" : @"0.0.0",
                        @"reasonCode" : @"0.0.0"
                    },
                    @"es10b" : @{@"errorReason" : @9, @"bppCommandId" : @5},
                    @"http" : @{@"status" : @200, @"requestId" : @"fixture-request"},
                    @"apdu" : @{@"statusWord" : @"9000", @"responseHex" : @"fixture-response"}
                } mutableCopy];
                NSError *duplicate =
                    SHDiagnosticError(@"Profile installation failed", details, nil);
                details[@"es10b"] = @{@"errorReason" : @10};
                NSString *text = SHErrorReport(duplicate);
                shjson::JSON report;
                bool decoded =
                    shjson::parseData([text dataUsingEncoding:NSUTF8StringEncoding], report);
                NSDictionary *snapshot =
                    decoded && report.is_object() ? shjson::foundation(report) : nil;
                if (duplicate.code != 4009 || ![text containsString:@"fixture-request"] ||
                    ![text containsString:@"fixture-response"] ||
                    [snapshot[@"diagnostics"][@"es10b"][@"errorReason"] integerValue] != 9 ||
                    [SHErrorSummary(duplicate) containsString:@"unknown"])
                    return 1;
                NSString *expected = [language isEqual:@"en"] ? @"already installed" : @"已安装";
                if (![SHErrorSummary(duplicate) containsString:expected])
                    return 2;
                NSError *full = SHDiagnosticError(@"Profile installation failed", details, nil);
                expected = [language isEqual:@"en"] ? @"free space" : @"空间";
                if (![SHErrorSummary(full) containsString:expected])
                    return 3;
                details[@"es10b"] = @{@"errorReason" : @127};
                NSError *unspecified =
                    SHDiagnosticError(@"Profile installation failed", details, nil);
                if ([SHErrorSummary(unspecified) isEqual:SHErrorSummary(duplicate)] ||
                    [SHErrorSummary(unspecified) containsString:@"unknown"] ||
                    ![SHErrorReport(unspecified) containsString:@"127"])
                    return 4;
                NSError *network = [NSError errorWithDomain:NSURLErrorDomain
                                                       code:NSURLErrorTimedOut
                                                   userInfo:nil];
                NSError *wrapped =
                    SHDiagnosticError(@"Operator authentication failed", @{}, network);
                if (![SHErrorReport(wrapped) containsString:@"NSURLErrorDomain"] ||
                    ![SHErrorReport(wrapped) containsString:@"-1001"])
                    return 5;
            }
        } @finally {
            if (original)
                [NSUserDefaults.standardUserDefaults setObject:original forKey:@"SHLanguage"];
            else
                [NSUserDefaults.standardUserDefaults removeObjectForKey:@"SHLanguage"];
        }
        printf(
            "PASS: bilingual duplicate/full/unspecified errors, immutable failure snapshot and underlying network diagnostics\n");
        return 0;
    }
}
