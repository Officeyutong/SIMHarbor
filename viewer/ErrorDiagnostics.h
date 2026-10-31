#import <Foundation/Foundation.h>

NSError *SHDiagnosticError(NSString *stage, NSDictionary *details, NSError *underlying);
NSString *SHErrorSummary(NSError *error);
NSString *SHErrorReport(NSError *error);
