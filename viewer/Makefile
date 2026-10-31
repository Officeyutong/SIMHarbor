TARGET := iphone:clang:latest:14.0
ARCHS := arm64
include $(THEOS)/makefiles/common.mk
APPLICATION_NAME = ESTKLog
ESTKLog_FILES = main.m Bridge.m LPAEngine.m QRDecoder.m ManagementVC.m Localization.m TraceLog.m SignalConsoleVC.m DocumentsVC.m FirmwareReportVC.m AboutVC.m ErrorDetailsVC.m ErrorDiagnostics.m SignalCodec.c $(wildcard ../vendor/euicc/*.c) ../vendor/cjson/cJSON.c ../vendor/cjson-ext/cJSON_ex.c
ESTKLog_FRAMEWORKS = UIKit CoreGraphics CoreMedia CoreVideo Foundation AVFoundation Security QuartzCore Vision PhotosUI
ESTKLog_FILES += ../tests/test_error_diagnostics.m
ESTKLog_CODESIGN_FLAGS = -Sentitlements.plist
ESTKLog_CFLAGS = -fobjc-arc -I../vendor -Wno-deprecated-declarations
ESTKLog_CFLAGS += -Wno-incompatible-pointer-types-discards-qualifiers
include $(THEOS_MAKE_PATH)/application.mk
