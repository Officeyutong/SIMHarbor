# SIMHarbor: native App + CommCenter extension. Empty scheme means rootful.
export THEOS_PACKAGE_SCHEME ?= roothide

include $(THEOS)/makefiles/common.mk

SUBPROJECTS += tweak
SUBPROJECTS += viewer

include $(THEOS)/makefiles/aggregate.mk

before-package::
	mkdir -p "$(THEOS_STAGING_DIR)/DEBIAN"
	sed 's|@INSTALL_PREFIX@|$(THEOS_PACKAGE_INSTALL_PREFIX)|g' packaging/postinst.in > "$(THEOS_STAGING_DIR)/DEBIAN/postinst"
	chmod 755 "$(THEOS_STAGING_DIR)/DEBIAN/postinst"

# 装/卸后重启 CommCenter 让 tweak 生效(会短暂掉蜂窝网,自动恢复)
after-install::
	install.exec "killall -9 CommCenter || true"
