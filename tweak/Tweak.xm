#import <Foundation/Foundation.h>
extern "C" void estk_apdu_start(void);
// Defer bridge startup while CommCenter begins initializing its services.
// A native constructor keeps this entry point directly parseable by clangd.
__attribute__((constructor)) static void SHInitializeTweak(void) {
    @autoreleasepool {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                       dispatch_get_global_queue(0, 0), ^{
                           estk_apdu_start();
                       });
    }
}
