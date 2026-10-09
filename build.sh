#!/bin/sh
# Build luci-app-ps5block as .ipk (opkg, OpenWrt <= 24.10) and .apk (apk v3, OpenWrt 25.x+)
#   PO2LMO=/path/to/po2lmo APK=/path/to/apk ./build.sh
set -e
cd "$(dirname "$0")"
NAME="luci-app-ps5block"
VERSION="1.0.0"
RELEASE="1"
FULLVER="$VERSION-r$RELEASE"
MAINT="ps5block <ps5block@users.noreply.github.com>"
DESC="PS5 system update blocker for OpenWrt with LuCI: DNS, forced DNS, DoT/DoH and L3 blocking, console auto-detection, podkop/zapret aware"
DEPS="luci-base firewall4"
OUT="${OUT:-dist}"
EPOCH="${SOURCE_DATE_EPOCH:-$(date +%s)}"

B="$(mktemp -d)"; trap 'rm -rf "$B"' EXIT
D="$B/data"; mkdir -p "$D/www" "$OUT"
cp -a root/. "$D/"
cp -a htdocs/. "$D/www/"
if [ -n "$PO2LMO" ] && [ -x "$PO2LMO" ]; then
	mkdir -p "$D/usr/lib/lua/luci/i18n"
	for po in po/*/ps5block.po; do
		lang="$(basename "$(dirname "$po")")"; [ "$lang" = templates ] && continue
		"$PO2LMO" "$po" "$D/usr/lib/lua/luci/i18n/ps5block.$lang.lmo"
	done
else
	echo "WARNING: po2lmo not found, building without translations" >&2
fi
find "$D" -type d -exec chmod 755 {} +
SIZE="$(du -sk "$D" | cut -f1)"

TAR="tar --owner=0 --group=0 --numeric-owner --sort=name --mtime=@$EPOCH"

# ---------------- ipk ----------------
C="$B/control"; mkdir -p "$C"
cat > "$C/control" <<CTL
Package: $NAME
Version: $FULLVER
Depends: libc, $(echo "$DEPS" | sed 's/ /, /g')
Source: feeds/luci/applications/$NAME
SourceName: $NAME
License: MIT
Section: luci
SourceDateEpoch: $EPOCH
URL: https://github.com/
Maintainer: $MAINT
Architecture: all
Installed-Size: $((SIZE * 1024))
Description: $DESC
CTL
cp scripts/postinst scripts/prerm scripts/postrm "$C/"
( cd "$D" && $TAR -czf "$B/data.tar.gz" . )
( cd "$C" && $TAR -czf "$B/control.tar.gz" . )
echo "2.0" > "$B/debian-binary"
( cd "$B" && $TAR -czf "$OLDPWD/$OUT/${NAME}_${FULLVER}_all.ipk" ./debian-binary ./data.tar.gz ./control.tar.gz )
echo "built $OUT/${NAME}_${FULLVER}_all.ipk"

# ---------------- apk ----------------
if [ -n "$APK" ] && [ -x "$APK" ]; then
	"$APK" mkpkg \
		--info "name:$NAME" --info "version:$FULLVER" --info "description:$DESC" \
		--info "arch:noarch" --info "license:MIT" --info "origin:$NAME" \
		--info "url:https://github.com/" --info "maintainer:$MAINT" \
		--info "depends:$DEPS" \
		--script "post-install:scripts/postinst" --script "post-upgrade:scripts/postinst" \
		--script "pre-deinstall:scripts/prerm" --script "post-deinstall:scripts/postrm" \
		--files "$D" --output "$OUT/${NAME}-${FULLVER}.apk"
	echo "built $OUT/${NAME}-${FULLVER}.apk"
else
	echo "WARNING: apk-tools v3 not found, .apk not built" >&2
fi
