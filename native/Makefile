TARGET := iphone:clang:latest:14.0
ARCHS := arm64 arm64e
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = shnativeplan
shnativeplan_FILES = Entry.mm PlanHooks.mm PlanDispatch.mm PlanClient.mm PlanLauncher.mm
shnativeplan_CFLAGS = -fobjc-arc -std=c++17 -Wno-deprecated-declarations
shnativeplan_FRAMEWORKS = Foundation CoreTelephony UIKit
include $(THEOS_MAKE_PATH)/tweak.mk
