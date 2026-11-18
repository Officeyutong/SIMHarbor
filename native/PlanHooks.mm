#import "PlanHooks.h"
#import <objc/runtime.h>
#import <os/lock.h>

static os_unfair_lock hookLock = OS_UNFAIR_LOCK_INIT;
static SHPlanHandler planHandler;
// If another hook wraps one of ours, its saved IMP may still call our wrapper.
// Retain the original IMPs and refuse reinstallation in that process.
static bool wrappedByAnotherHook;
static IMP originalSupport, originalEmbedded, originalAdd, originalAddProperties;
static Method supportMethod, embeddedMethod, addMethod, addPropertiesMethod;

static void (^onceCompletion(void (^completion)(CTCellularPlanProvisioningAddPlanResult)))(
    CTCellularPlanProvisioningAddPlanResult) {
    if (!completion)
        return nil;
    NSLock *lock = [NSLock new];
    __block BOOL completed = NO;
    return ^(CTCellularPlanProvisioningAddPlanResult result) {
        [lock lock];
        BOOL deliver = !completed;
        completed = YES;
        [lock unlock];
        if (deliver)
            completion(result);
    };
}
static BOOL support(id self, SEL selector) {
    os_unfair_lock_lock(&hookLock);
    BOOL enabled = planHandler != nil;
    IMP original = selector == @selector(supportsCellularPlan) ? originalSupport : originalEmbedded;
    os_unfair_lock_unlock(&hookLock);
    return enabled ? YES : ((BOOL (*)(id, SEL))original)(self, selector);
}
static void addPlan(id self, SEL selector, CTCellularPlanProvisioningRequest *request,
                    void (^completion)(CTCellularPlanProvisioningAddPlanResult)) {
    os_unfair_lock_lock(&hookLock);
    SHPlanHandler handler = [planHandler copy];
    IMP original = originalAdd;
    os_unfair_lock_unlock(&hookLock);
    if (handler)
        handler(request, nil, onceCompletion(completion));
    else
        ((void (*)(id, SEL, id, id))original)(self, selector, request, completion);
}
static void addPlanWithProperties(id self, SEL selector, CTCellularPlanProvisioningRequest *request,
                                  id properties,
                                  void (^completion)(CTCellularPlanProvisioningAddPlanResult)) {
    os_unfair_lock_lock(&hookLock);
    SHPlanHandler handler = [planHandler copy];
    IMP original = originalAddProperties;
    os_unfair_lock_unlock(&hookLock);
    if (handler)
        handler(request, properties, onceCompletion(completion));
    else
        ((void (*)(id, SEL, id, id, id))original)(self, selector, request, properties, completion);
}
BOOL SHInstallPlanHooks(SHPlanHandler handler) {
    if (!handler)
        return NO;
    os_unfair_lock_lock(&hookLock);
    if (planHandler || wrappedByAnotherHook) {
        os_unfair_lock_unlock(&hookLock);
        return NO;
    }
    Class cls = CTCellularPlanProvisioning.class;
    supportMethod = class_getInstanceMethod(cls, @selector(supportsCellularPlan));
    embeddedMethod = class_getInstanceMethod(cls, @selector(supportsEmbeddedSIM));
    addMethod = class_getInstanceMethod(cls, @selector(addPlanWith:completionHandler:));
    addPropertiesMethod =
        class_getInstanceMethod(cls, sel_registerName("addPlanWith:properties:completionHandler:"));
    if (!supportMethod || !addMethod) {
        os_unfair_lock_unlock(&hookLock);
        return NO;
    }
    originalSupport = method_getImplementation(supportMethod);
    originalEmbedded = embeddedMethod ? method_getImplementation(embeddedMethod) : nullptr;
    originalAdd = method_getImplementation(addMethod);
    originalAddProperties =
        addPropertiesMethod ? method_getImplementation(addPropertiesMethod) : nullptr;
    planHandler = [handler copy];
    method_setImplementation(supportMethod, (IMP)support);
    if (embeddedMethod)
        method_setImplementation(embeddedMethod, (IMP)support);
    method_setImplementation(addMethod, (IMP)addPlan);
    if (addPropertiesMethod)
        method_setImplementation(addPropertiesMethod, (IMP)addPlanWithProperties);
    os_unfair_lock_unlock(&hookLock);
    return YES;
}
void SHRemovePlanHooks(void) {
    os_unfair_lock_lock(&hookLock);
    if (planHandler) {
        if (method_getImplementation(supportMethod) != (IMP)support ||
            (embeddedMethod && method_getImplementation(embeddedMethod) != (IMP)support) ||
            method_getImplementation(addMethod) != (IMP)addPlan ||
            (addPropertiesMethod &&
             method_getImplementation(addPropertiesMethod) != (IMP)addPlanWithProperties))
            wrappedByAnotherHook = true;
        if (method_getImplementation(supportMethod) == (IMP)support)
            method_setImplementation(supportMethod, originalSupport);
        if (embeddedMethod && method_getImplementation(embeddedMethod) == (IMP)support)
            method_setImplementation(embeddedMethod, originalEmbedded);
        if (method_getImplementation(addMethod) == (IMP)addPlan)
            method_setImplementation(addMethod, originalAdd);
        if (addPropertiesMethod &&
            method_getImplementation(addPropertiesMethod) == (IMP)addPlanWithProperties)
            method_setImplementation(addPropertiesMethod, originalAddProperties);
        planHandler = nil;
    }
    os_unfair_lock_unlock(&hookLock);
}
