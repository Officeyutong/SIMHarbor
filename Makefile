# SIMHarbor: native App + CommCenter extension, roothide package.
export THEOS_PACKAGE_SCHEME = roothide

include $(THEOS)/makefiles/common.mk

SUBPROJECTS += tweak
SUBPROJECTS += viewer

include $(THEOS)/makefiles/aggregate.mk

# 装/卸后重启 CommCenter 让 tweak 生效(会短暂掉蜂窝网,自动恢复)
after-install::
	install.exec "killall -9 CommCenter || true"
