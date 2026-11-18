#import "PlanClient.hpp"
#import "PlanDispatch.hpp"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <dlfcn.h>

// Invoke Launch Services without placing request contents in a URL or pasteboard.
BOOL SHStartPlanBridge(void) {
    return SHStartPlanDispatch(^(shjson::ProvisioningRequest request, id properties,
                                 void (^result)(CTCellularPlanProvisioningAddPlanResult)) {
        dispatch_async(dispatch_get_main_queue(), ^{
            // This bridge cannot yet preserve the optional plan properties.
            // Reject before switching apps so the caller can display its error.
            if (properties) {
                if (result)
                    result(CTCellularPlanProvisioningAddPlanResultFail);
                return;
            }
            // The requesting app is sent to the background when SIMHarbor opens.
            // This is best effort: iOS may expire the task before installation ends.
            __block UIBackgroundTaskIdentifier task = UIBackgroundTaskInvalid;
            UIApplication *application = UIApplication.sharedApplication;
            task = [application beginBackgroundTaskWithExpirationHandler:^{
                if (task != UIBackgroundTaskInvalid) {
                    [application endBackgroundTask:task];
                    task = UIBackgroundTaskInvalid;
                }
            }];
            void (^finish)(CTCellularPlanProvisioningAddPlanResult) =
                ^(CTCellularPlanProvisioningAddPlanResult value) {
                    // Keep the caller alive while its completion handler runs.
                    // The expiration handler may already have ended this task.
                    @try {
                        if (result)
                            result(value);
                    } @finally {
                        if (task != UIBackgroundTaskInvalid) {
                            [application endBackgroundTask:task];
                            task = UIBackgroundTaskInvalid;
                        }
                    }
                };
            dlopen("/System/Library/Frameworks/CoreServices.framework/CoreServices", RTLD_LAZY);
            Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
            SEL shared = NSSelectorFromString(@"defaultWorkspace");
            SEL open = NSSelectorFromString(@"openApplicationWithBundleID:");
            if (!workspaceClass || ![workspaceClass respondsToSelector:shared]) {
                finish(CTCellularPlanProvisioningAddPlanResultFail);
                return;
            }
            id workspace = ((id (*)(id, SEL))objc_msgSend)(workspaceClass, shared);
            if (![workspace respondsToSelector:open] ||
                !((BOOL (*)(id, SEL, id))objc_msgSend)(workspace, open, @"com.estk.viewer")) {
                finish(CTCellularPlanProvisioningAddPlanResultFail);
                return;
            }
            SHSubmitProvisioning(
                request, properties, ^(CTCellularPlanProvisioningAddPlanResult value) {
                    // Callers commonly update their UI from the completion block.
                    // A backgrounded app can lose that update while its web view is
                    // suspended, so deliver after it becomes active again.
                    if (application.applicationState == UIApplicationStateActive) {
                        finish(value);
                        return;
                    }
                    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
                    __block id observer = nil;
                    observer = [center
                        addObserverForName:UIApplicationDidBecomeActiveNotification
                                    object:application
                                     queue:NSOperationQueue.mainQueue
                                usingBlock:^(NSNotification *notification) {
                                    [NSNotificationCenter.defaultCenter removeObserver:observer];
                                    observer = nil;
                                    finish(value);
                                }];
                });
        });
    });
}
