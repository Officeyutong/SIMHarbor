#pragma once
#import <UIKit/UIKit.h>
#ifdef __cplusplus
extern "C" {
#endif
UIAlertController *SHActivationPrompt(NSInteger slot, NSString *suffix, NSString *code,
                                      NSString *confirmationCode, void (^cancel)(void),
                                      void (^install)(NSString *, NSString *, NSString *));
#ifdef __cplusplus
}
#endif
