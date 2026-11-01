TARGET := iphone:clang:latest:14.0
ARCHS := arm64
include $(THEOS)/makefiles/common.mk
APPLICATION_NAME = ESTKLog
ESTKLog_FILES = main.mm Bridge.mm LPAEngine.mm QRDecoder.m ManagementVC.m Localization.m TraceLog.m SignalConsoleVC.m DocumentsVC.mm FirmwareReportVC.mm AboutVC.m ErrorDetailsVC.m ErrorDiagnostics.mm SignalCodec.c $(wildcard ../vendor/euicc/*.c) ../vendor/cjson/cJSON.c ../vendor/cjson-ext/cJSON_ex.c
ESTKLog_FRAMEWORKS = UIKit CoreGraphics CoreMedia CoreVideo Foundation AVFoundation Security QuartzCore Vision PhotosUI
ESTKLog_FILES += ../tests/test_error_diagnostics.mm ../tests/test_notifications.m ../tests/test_json_foundation.mm
ESTKLog_CODESIGN_FLAGS = -Sentitlements.plist
ESTKLog_CFLAGS = -fobjc-arc -I../vendor -Wno-deprecated-declarations
ESTKLog_CFLAGS += -Wno-incompatible-pointer-types-discards-qualifiers
include $(THEOS_MAKE_PATH)/application.mk

ESTKLog_CCFLAGS += -std=c++17
