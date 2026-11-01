#import <Foundation/Foundation.h>
#ifdef __cplusplus
extern "C" {
#endif
NSString *SHL(NSString *key);
NSString *SHEnglish(NSString *text);
NSString *SHLanguage(void);
NSString *SHResolvedLanguage(void);
void SHSetLanguage(NSString *language);
NSError *SHError(NSInteger code, NSString *english);
#ifdef __cplusplus
}
#endif
