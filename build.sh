#!/bin/sh
# SPDX-License-Identifier: MIT
#
# Build luci-app-ps5block as .ipk (opkg, OpenWrt <= 24.10) and .apk (apk v3,
# OpenWrt 25.x+) without the OpenWrt SDK, and optionally a signed package feed.
#
#   PO2LMO=/path/to/po2lmo APK=/path/to/apk ./build.sh
#
# Optional signing (private keys must never be committed):
#   APK_KEY=/path/to/apk-private.pem       sign the .apk and packages.adb (EC P-256)
#   USIGN=/path/to/usign USIGN_KEY=/path/to/usign.sec
#                                          sign the opkg feed index (Packages.sig)
#   APK_KEYS_DIR=keys                      public keys mkndx checks the .apk against
#   OUT=dist                               output directory (default: dist)
#
# Output: $OUT/*.ipk, $OUT/*.apk and, when the tools are available,
#         $OUT/Packages, Packages.gz, Packages.sig (opkg feed) and packages.adb (apk feed).
set -e
cd "$(dirname "$0")"
TOP="$(pwd)"

mkvar() { sed -n "s/^$1:=//p" Makefile; }
NAME="$(mkvar PKG_NAME)"
VERSION="$(mkvar PKG_VERSION)"
RELEASE="$(mkvar PKG_RELEASE)"
FULLVER="$VERSION-r$RELEASE"
MAINT="$(mkvar PKG_MAINTAINER)"
URL="$(mkvar PKG_URL)"
LICENSE="$(mkvar PKG_LICENSE)"
DESC="PS5 system update blocker for OpenWrt with LuCI: DNS, forced DNS, DoT/DoH and L3 blocking, console auto-detection, podkop/zapret aware"
DEPS="luci-base firewall4"

grep -q "^VERSION=\"$VERSION\"" root/usr/sbin/ps5block || {
	echo "ERROR: VERSION in root/usr/sbin/ps5block does not match PKG_VERSION $VERSION in Makefile" >&2; exit 1; }

OUT="${OUT:-dist}"
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
if [ -z "$SOURCE_DATE_EPOCH" ]; then
	SOURCE_DATE_EPOCH="$(git log -1 --format=%ct 2>/dev/null || date +%s)"
fi
EPOCH="$SOURCE_DATE_EPOCH"

B="$(mktemp -d)"; trap 'rm -rf "$B"' EXIT
D="$B/data"; mkdir -p "$D/www"
cp -R root/. "$D/"
cp -R htdocs/. "$D/www/"
if [ -n "$PO2LMO" ] && [ -x "$PO2LMO" ]; then
	mkdir -p "$D/usr/lib/lua/luci/i18n"
	for po in po/*/ps5block.po; do
		lang="$(basename "$(dirname "$po")")"; [ "$lang" = templates ] && continue
		"$PO2LMO" "$po" "$D/usr/lib/lua/luci/i18n/ps5block.$lang.lmo"
	done
else
	echo "WARNING: po2lmo not found, building without translations" >&2
fi

# permissions do not depend on the checkout (Windows, umask): scripts 755, rest 644
find "$D" -type d -exec chmod 755 {} +
find "$D" -type f -exec chmod 644 {} +
find "$D" -type f -exec sh -c 'for f; do [ "$(head -c 2 "$f")" = "#!" ] && chmod 755 "$f"; done; true' sh {} +
SIZE="$(du -sk "$D" | cut -f1)"

TAR="tar --owner=0 --group=0 --numeric-owner --sort=name --mtime=@$EPOCH"
targz() { # out dir files...
	out="$1"; dir="$2"; shift 2
	( cd "$dir" && $TAR -cf - "$@" ) | gzip -9n > "$out"
}

# ---------------- ipk ----------------
IPK="${NAME}_${FULLVER}_all.ipk"
C="$B/control"; mkdir -p "$C"
cat > "$C/control" <<CTL
Package: $NAME
Version: $FULLVER
Depends: libc, $(echo "$DEPS" | sed 's/ /, /g')
Source: feeds/luci/applications/$NAME
SourceName: $NAME
License: $LICENSE
Section: luci
SourceDateEpoch: $EPOCH
URL: $URL
Maintainer: $MAINT
Architecture: all
Installed-Size: $((SIZE * 1024))
Description: $DESC
CTL
cp scripts/postinst scripts/prerm scripts/postrm "$C/"
chmod 644 "$C/control"; chmod 755 "$C/postinst" "$C/prerm" "$C/postrm"
targz "$B/data.tar.gz" "$D" .
targz "$B/control.tar.gz" "$C" .
echo "2.0" > "$B/debian-binary"
targz "$OUT/$IPK" "$B" ./debian-binary ./data.tar.gz ./control.tar.gz
echo "built $OUT/$IPK"

# opkg feed index: control fields + Filename/Size/SHA256sum
{
	grep -vE '^(Source|SourceName|SourceDateEpoch):' "$C/control" | grep -v '^Description:'
	echo "Filename: $IPK"
	echo "Size: $(wc -c < "$OUT/$IPK" | tr -d ' ')"
	echo "SHA256sum: $(sha256sum "$OUT/$IPK" | cut -d' ' -f1)"
	grep '^Description:' "$C/control"
	echo
} > "$OUT/Packages"
gzip -9nc "$OUT/Packages" > "$OUT/Packages.gz"
rm -f "$OUT/Packages.sig"
if [ -n "$USIGN_KEY" ]; then
	"${USIGN:-usign}" -S -m "$OUT/Packages" -s "$USIGN_KEY" -x "$OUT/Packages.sig"
	echo "signed $OUT/Packages.sig"
fi

# ---------------- apk ----------------
APKF="${NAME}-${FULLVER}.apk"
if [ -n "$APK" ] && [ -x "$APK" ]; then
	set --
	[ -n "$APK_KEY" ] && set -- --sign-key "$APK_KEY"
	rm -f "$OUT/$APKF" "$OUT/packages.adb"
	SOURCE_DATE_EPOCH="$EPOCH" "$APK" mkpkg "$@" \
		--info "name:$NAME" --info "version:$FULLVER" --info "description:$DESC" \
		--info "arch:noarch" --info "license:$LICENSE" --info "origin:$NAME" \
		--info "url:$URL" --info "maintainer:$MAINT" \
		--info "depends:$DEPS" \
		--script "post-install:$TOP/scripts/postinst" --script "post-upgrade:$TOP/scripts/postinst" \
		--script "pre-deinstall:$TOP/scripts/prerm" --script "post-deinstall:$TOP/scripts/postrm" \
		--files "$D" --output "$OUT/$APKF"
	echo "built $OUT/$APKF${APK_KEY:+ (signed)}"
	# apk feed index (packages.adb), signed with the same key; mkndx checks the
	# package signature against the public keys in keys/ (APK_KEYS_DIR)
	if [ -n "$APK_KEY" ]; then
		set -- "$@" --keys-dir "${APK_KEYS_DIR:-$TOP/keys}"
	else
		set -- --allow-untrusted
	fi
	( cd "$OUT" && "$APK" mkndx "$@" --output packages.adb "$APKF" )
	echo "built $OUT/packages.adb${APK_KEY:+ (signed)}"
else
	echo "WARNING: apk-tools v3 not found, .apk not built" >&2
fi

( cd "$OUT" && sha256sum ./*.ipk ./*.apk 2>/dev/null | sed 's# \./# #' > SHA256SUMS )
echo "built $OUT/SHA256SUMS"
