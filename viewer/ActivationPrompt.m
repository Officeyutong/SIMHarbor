#import "ActivationPrompt.h"
#import "Localization.h"

UIAlertController *SHActivationPrompt(NSInteger slot, NSString *suffix, NSString *code,
                                      NSString *confirmationCode, void (^cancel)(void),
                                      void (^install)(NSString *, NSString *, NSString *)) {
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:SHL(@"Add eSIM")
                         message:
                             [NSString
                                 stringWithFormat:
                                     SHL(@"Download to slot %ld (EID ending %@). The profile remains disabled."),
                                     (long)slot, suffix]
                  preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *t) {
        t.placeholder = SHL(@"LPA:1$server$activation-token");
        t.text = code;
        t.autocapitalizationType = UITextAutocapitalizationTypeNone;
        t.autocorrectionType = UITextAutocorrectionTypeNo;
        t.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [a addTextFieldWithConfigurationHandler:^(UITextField *t) {
        t.placeholder = SHL(@"Confirmation code (if required)");
        t.secureTextEntry = YES;
        t.text = confirmationCode;
    }];
    [a addTextFieldWithConfigurationHandler:^(UITextField *t) {
        t.placeholder = SHL(@"IMEI (optional, 15 digits)");
        t.keyboardType = UIKeyboardTypeNumberPad;
    }];
    __weak UIAlertController *weakAlert = a;
    [a addAction:[UIAlertAction actionWithTitle:SHL(@"Cancel")
                                          style:UIAlertActionStyleCancel
                                        handler:^(UIAlertAction *action) {
                                            if (cancel)
                                                cancel();
                                        }]];
    [a addAction:[UIAlertAction actionWithTitle:SHL(@"Download and install")
                                          style:UIAlertActionStyleDefault
                                        handler:^(UIAlertAction *x) {
                                            UIAlertController *alert = weakAlert;
                                            NSString *activation = alert.textFields[0].text ?: @"";
                                            NSString *confirmation =
                                                alert.textFields[1].text ?: @"";
                                            NSString *imei = alert.textFields[2].text;
                                            for (UITextField *field in alert.textFields)
                                                field.text = @"";
                                            install(activation, confirmation, imei);
                                        }]];
    return a;
}
