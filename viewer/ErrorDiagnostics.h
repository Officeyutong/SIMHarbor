#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif
NSError *SHDiagnosticError(NSString *stage, NSDictionary *details, NSError *underlying);
NSString *SHErrorSummary(NSError *error);
NSString *SHErrorReport(NSError *error);
#ifdef __cplusplus
}
#endif
