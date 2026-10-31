#import "Localization.h"
NSString *SHLanguage(void) {
    NSString *language = [NSUserDefaults.standardUserDefaults stringForKey:@"SHLanguage"];
    return [@[@"en", @"zh-Hans"] containsObject:language] ? language : @"system";
}
static NSBundle *LanguageBundle(NSString *language) {
    NSString *path = [NSBundle.mainBundle pathForResource:language ofType:@"lproj"];
    return path ? [NSBundle bundleWithPath:path] : NSBundle.mainBundle;
}
NSString *SHResolvedLanguage(void) {
    NSString *language = SHLanguage();
    if ([language isEqual:@"system"]) {
        NSString *preferred = NSBundle.mainBundle.preferredLocalizations.firstObject ?: @"en";
        language = [preferred hasPrefix:@"zh"] ? @"zh-Hans" : @"en";
    }
    return language;
}
NSString *SHL(NSString *key) {
    if (!key) return @"";
    return [LanguageBundle(SHResolvedLanguage()) localizedStringForKey:key value:key table:nil];
}
NSString *SHEnglish(NSString *text) {
    static NSDictionary *reverse;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *path = [LanguageBundle(@"zh-Hans") pathForResource:@"Localizable" ofType:@"strings"];
        NSDictionary *strings = path ? [NSDictionary dictionaryWithContentsOfFile:path] : nil;
        NSMutableDictionary *map = [NSMutableDictionary dictionary];
        for (NSString *key in strings) map[strings[key]] = key;
        reverse = [map copy];
    });
    return reverse[text] ?: text ?: @"";
}
void SHSetLanguage(NSString *language) {
    [NSUserDefaults.standardUserDefaults setObject:language forKey:@"SHLanguage"];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"SHLanguageChanged" object:nil];
}
NSError *SHError(NSInteger code, NSString *english) {
    return [NSError errorWithDomain:@"SIMHarbor" code:code userInfo:@{
        NSLocalizedDescriptionKey: SHL(english), @"SHErrorEnglish": english ?: @"Operation failed"
    }];
}
