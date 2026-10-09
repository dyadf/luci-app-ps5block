# SPDX-License-Identifier: MIT
#
# OpenWrt SDK / buildroot package for luci-app-ps5block.
# Put this directory into feeds/luci/applications/ (or any feed that has luci.mk)
# and run: make package/luci-app-ps5block/compile
# For a quick stand-alone build without the SDK use ./build.sh instead
# (it reads the PKG_* values below).

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-ps5block
PKG_VERSION:=1.1.1
PKG_RELEASE:=1
PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=arsutov <arsutov@users.noreply.github.com>
PKG_URL:=https://github.com/dyadf/luci-app-ps5block

LUCI_TITLE:=PS5 system update blocker
LUCI_DESCRIPTION:=Blocks PlayStation 5 system software updates: DNS block, forced DNS, \
	strict DNS, DoT/DoH and L3 blocking, console auto-detection by MAC, podkop/zapret aware.
LUCI_DEPENDS:=+luci-base +firewall4
LUCI_PKGARCH:=all

define Package/luci-app-ps5block/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
[ "$$1" = "upgrade" ] && exit 0
[ -x /usr/sbin/ps5block ] && /usr/sbin/ps5block teardown >/dev/null 2>&1
/etc/init.d/ps5block disable >/dev/null 2>&1
exit 0
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
