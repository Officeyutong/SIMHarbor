TARGET := iphone:clang:latest:14.0
ARCHS  := arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = estkrecon

estkrecon_FILES      = Tweak.xm Apdu.mm ResolverCore.cpp RuntimeResolver.mm
estkrecon_CFLAGS     = -fobjc-arc -Wno-deprecated-declarations -std=c++17
estkrecon_FRAMEWORKS = Foundation
estkrecon_LIBRARIES  = substrate

estkrecon_CFLAGS += -DSH_USE_GUM
estkrecon_LDFLAGS += $(abspath ../vendor/frida-gum)/$(THEOS_CURRENT_ARCH)/libfrida-gum.a -Wl,-dead_strip -Wl,-exported_symbol,_estk_apdu_start

include $(THEOS_MAKE_PATH)/tweak.mk
