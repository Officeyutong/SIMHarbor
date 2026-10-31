#import "ErrorDiagnostics.h"
#import "Localization.h"
#import <euicc/es10b.h>

static NSString *SHInstallationMessage(NSInteger reason) {
    switch (reason) {
    case ES10B_ERROR_REASON_INSTALL_FAILED_DUE_TO_ICCID_ALREADY_EXISTS_ON_EUICC:
        return @"This eSIM profile is already installed on the card. Use the existing profile in the profile list.";
    case ES10B_ERROR_REASON_INSTALL_FAILED_DUE_TO_INSUFFICIENT_MEMORY_FOR_PROFILE:
        return @"The card does not have enough free space. Delete an unused profile and try again.";
    case ES10B_ERROR_REASON_INSTALL_FAILED_DUE_TO_INTERRUPTION:
        return @"Installation was interrupted. Refresh the profile list before trying again.";
    case ES10B_ERROR_REASON_INVALID_SIGNATURE:
        return @"The card rejected the profile signature. Contact your operator.";
    case ES10B_ERROR_REASON_INVALID_TRANSACTION_ID:
        return @"The download session is no longer valid. Start a new download.";
    case ES10B_ERROR_REASON_PPR_NOT_ALLOWED:
        return @"Card policy does not allow this profile to be installed.";
    default:
        return nil;
    }
}

static BOOL SHMeaningfulMessage(NSString *message) {
    if (![message isKindOfClass:NSString.class])
        return NO;
    NSString *trimmed =
        [message stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return trimmed.length &&
           ![@[ @"unknown", @"null", @"(null)" ] containsObject:trimmed.lowercaseString];
}

NSString *SHErrorSummary(NSError *error) {
    NSString *key = error.userInfo[@"SHFriendlyMessage"];
    if (key)
        return SHL(key);
    NSString *stage = error.userInfo[@"SHDiagnosticStage"];
    NSString *raw = error.userInfo[@"SHDiagnostics"][@"es9p"][@"message"];
    if (stage.length && SHMeaningfulMessage(raw))
        return [NSString stringWithFormat:@"%@: %@", SHL(stage), raw];
    if (stage.length)
        return [NSString
            stringWithFormat:@"%@\n%@", SHL(stage),
                             SHL(@"Check Error details for the exact response and error codes.")];
    NSString *english = error.userInfo[@"SHErrorEnglish"];
    if (SHMeaningfulMessage(english))
        return SHL(english);
    return SHMeaningfulMessage(error.localizedDescription)
               ? error.localizedDescription
               : SHL(@"The operation could not be completed. Check Error details for diagnostic information.");
}

NSError *SHDiagnosticError(NSString *stage, NSDictionary *details, NSError *underlying) {
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[@"SHDiagnosticStage"] = stage ?: @"Operation incomplete";
    // Snapshot before cancellation/close requests can replace transport state.
    info[@"SHDiagnostics"] = [details copy] ?: @{};
    info[@"SHRecordedAt"] = [NSISO8601DateFormatter.new stringFromDate:NSDate.date];
    if (underlying)
        info[NSUnderlyingErrorKey] = underlying;
    NSNumber *reason = details[@"es10b"][@"errorReason"];
    NSString *message = reason ? SHInstallationMessage(reason.integerValue) : nil;
    NSDictionary *server = details[@"es9p"];
    if (!message && [server[@"subjectCode"] isEqual:@"8.2.6"] &&
        [server[@"reasonCode"] isEqual:@"3.8"])
        message =
            @"The operator rejected this activation code. It may already be used or no longer valid.";
    if (!message && [server[@"subjectCode"] isEqual:@"8.2.7"] &&
        [server[@"reasonCode"] isEqual:@"3.8"])
        message = @"The operator rejected the confirmation code. Check it before trying again.";
    if (!message && underlying)
        message = underlying.userInfo[@"SHErrorEnglish"];
    if (message.length)
        info[@"SHFriendlyMessage"] = message;
    info[@"SHErrorEnglish"] = message ?: stage ?: @"Operation incomplete";
    NSInteger code = reason ? 4000 + reason.integerValue : (underlying ? underlying.code : 1);
    NSError *error = [NSError errorWithDomain:@"SIMHarbor" code:code userInfo:info];
    info[NSLocalizedDescriptionKey] = SHErrorSummary(error);
    return [NSError errorWithDomain:error.domain code:error.code userInfo:info];
}

static NSDictionary *SHUnderlyingReport(NSError *error, NSUInteger depth) {
    if (!error || depth > 5)
        return @{};
    NSMutableDictionary *report = [@{
        @"domain" : error.domain,
        @"code" : @(error.code),
        @"description" : error.localizedDescription ?: @""
    } mutableCopy];
    if (error.localizedFailureReason)
        report[@"failureReason"] = error.localizedFailureReason;
    if (error.localizedRecoverySuggestion)
        report[@"recoverySuggestion"] = error.localizedRecoverySuggestion;
    if (error.userInfo[NSUnderlyingErrorKey])
        report[@"underlyingError"] =
            SHUnderlyingReport(error.userInfo[NSUnderlyingErrorKey], depth + 1);
    return report;
}

NSString *SHErrorReport(NSError *error) {
    if (!error)
        return SHL(@"No errors recorded in this session.");
    NSDictionary *report = @{
        @"recordedAt":error.userInfo[@"SHRecordedAt"] ?: @"",
        @"stage":error.userInfo[@"SHDiagnosticStage"] ?: @"",
        @"domain":error.domain,
        @"code":@(error.code),
        @"message":error.userInfo[@"SHErrorEnglish"] ?: error.localizedDescription ?: @"",
        @"diagnostics":error.userInfo[@"SHDiagnostics"] ?: @{},
        @"underlyingError":SHUnderlyingReport(error.userInfo[NSUnderlyingErrorKey], 0)
    };
    NSData *json =
        [NSJSONSerialization dataWithJSONObject:report
                                        options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                          error:nil];
    return json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]
                : error.description;
}
