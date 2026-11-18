#import <Foundation/Foundation.h>
BOOL SHStartPlanBridge(void);
__attribute__((constructor)) static void SHNativePlanEntry(void) {
    @autoreleasepool {
        if ([NSBundle.mainBundle.bundleIdentifier isEqual:@"com.estk.viewer"])
            return;
        SHStartPlanBridge();
    }
}
