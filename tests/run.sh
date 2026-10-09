#!/bin/sh
# SPDX-License-Identifier: MIT
#
# Test bench for luci-app-ps5block on a Linux host, without a router.
#
# The real backend scripts run under busybox ash against the real OpenWrt
# userland tools (uci, jshn, jsonfilter) and the real nft, inside a private
# user + network namespace, so nothing on the host is touched. dnsmasq, ubus,
# logger and the update-server DNS answers are stubs.
#
# Needs: busybox, nft, unshare, ip; uci, jsonfilter (or jsonpath) and jshn.sh
# from OpenWrt libubox/uci/jsonpath built for the host.
#
#   JSHN=/path/to/jshn.sh PATH=/path/to/openwrt-tools/bin:$PATH tests/run.sh
#
HERE="$(cd "$(dirname "$0")/.." && pwd)"
BB="${BUSYBOX:-$(command -v busybox)}"
JSHN="${JSHN:-/usr/share/libubox/jshn.sh}"

# re-run as root of a private user+network namespace
if [ "$(id -u)" != "0" ] || [ -z "${PS5T_NS:-}" ]; then
	PS5T_NS=1 exec unshare -rn "$BB" ash "$0" "$@"
fi

for t in "$BB" nft uci; do command -v "$t" >/dev/null || { echo "missing tool: $t"; exit 2; }; done
[ -f "$JSHN" ] || { echo "missing jshn.sh (set JSHN=)"; exit 2; }

TR="$(mktemp -d /tmp/ps5block-test.XXXXXX)"
trap 'rm -rf "$TR"' EXIT
PASS=0; FAIL=0

ok()   { PASS=$((PASS + 1)); echo "  ok   $*"; }
bad()  { FAIL=$((FAIL + 1)); echo "  FAIL $*"; }
check() { # description "shell expression" | description command args...
	d="$1"; shift
	if [ $# -eq 1 ]; then ( eval "$1" ) >/dev/null 2>&1; else "$@" >/dev/null 2>&1; fi
	if [ $? = 0 ]; then ok "$d"; else bad "$d"; fi
}
section() { echo; echo "== $*"; }

# ------------------------------------------------------------------ sandbox --
setup() {
	rm -rf "$TR/root" "$TR/bin"
	mkdir -p "$TR/root" "$TR/bin" "$TR/root/var/run" "$TR/root/etc/crontabs" "$TR/uci-tmp"
	cp -R "$HERE/root/." "$TR/root/"
	mkdir -p "$TR/root/etc/config" "$TR/root/etc/init.d"
	cp "$TR/root/usr/share/ps5block/ps5block.default" "$TR/root/etc/config/ps5block"
	cat > "$TR/root/etc/config/dhcp" <<-'EOF'

	config dnsmasq
		option domainneeded '1'
		list address '/my.own.entry/'

	config dhcp 'lan'
		option interface 'lan'
	EOF
	: > "$TR/root/etc/config/firewall"
	rm -f "$TR/root/etc/config/podkop"
	: > "$TR/log"; : > "$TR/leases"; printf 'IP address HW type Flags HW address Mask Device\n' > "$TR/arp"

	# rewrite absolute paths of the installed system into the sandbox
	for f in usr/sbin/ps5block usr/libexec/rpcd/ps5block etc/uci-defaults/90-luci-ps5block \
		etc/hotplug.d/dhcp/90-ps5block etc/hotplug.d/iface/90-ps5block; do
		sed -i -e "1s|^#!/bin/sh|#!$BB ash|" -e "1a . $TR/stubs.sh" \
			-e "s|/usr/share/libubox/jshn.sh|$JSHN|g" \
			-e "s|/usr/share/ps5block|$TR/root/usr/share/ps5block|g" \
			-e "s|/var/run/ps5block|$TR/root/var/run/ps5block|g" \
			-e "s|/var/lock/|$TR/|g" \
			-e "s|/etc/ps5block|$TR/root/etc/ps5block|g" \
			-e "s|/etc/crontabs/root|$TR/root/etc/crontabs/root|g" \
			-e "s|/etc/init.d/|$TR/root/etc/init.d/|g" \
			-e "s|/etc/config/|$TR/root/etc/config/|g" \
			-e "s|/usr/sbin/ps5block|$TR/root/usr/sbin/ps5block|g" \
			-e "s|/lib/functions.sh|$TR/none|g" "$TR/root/$f"
		chmod 755 "$TR/root/$f"
	done

	UCI="$(command -v uci)"
	cat > "$TR/bin/uci" <<-EOF
	#!$BB ash
	exec "$UCI" -c "$TR/root/etc/config" -t "$TR/uci-tmp" "\$@"
	EOF
	cat > "$TR/bin/logger" <<-EOF
	#!$BB ash
	shift 2; echo "\$*" >> "$TR/log"
	EOF
	cat > "$TR/bin/ubus" <<-'EOF'
	#!/bin/sh
	case "$2" in network.interface.lan) echo '{ "up": true, "l3_device": "br-lan", "device": "br-lan" }' ;; *) exit 4 ;; esac
	EOF
	cat > "$TR/bin/pidof" <<-'EOF'
	#!/bin/sh
	exit 1
	EOF
	# nslookup: the router itself (127.0.0.1) answers NXDOMAIN when the dnsmasq
	# entry is present; public resolvers return busybox-style answers from $TR/dns
	cat > "$TR/bin/nslookup" <<-EOF
	#!$BB ash
	type=a; [ "\${1#-type=}" != "\$1" ] && { type="\${1#-type=}"; shift; }
	host="\$1"; srv="\$2"
	printf 'Server:\t\t%s\nAddress:\t%s:53\n\n' "\$srv" "\$srv"
	if [ "\$srv" = "127.0.0.1" ]; then
		if grep -q "/ps5.update.playstation.net/" "$TR/root/etc/config/dhcp"; then
			echo "** server can't find \$host: NXDOMAIN"
		else
			printf 'Name:\t%s\nAddress: 203.0.113.9\n' "\$host"
		fi
		exit 0
	fi
	[ -f "$TR/dns" ] || { echo "** server can't find \$host: NXDOMAIN"; exit 1; }
	echo "Non-authoritative answer:"
	awk -v h="\$host" -v t="\$type" '\$1 == h && \$2 == t { printf "Name:\t%s\nAddress: %s\n\n", h, \$3 }' "$TR/dns"
	EOF
	for s in dnsmasq cron rpcd firewall; do
		printf '#!/bin/sh\necho "%s $*" >> "%s/svc"\n' "$s" "$TR" > "$TR/root/etc/init.d/$s"
		chmod 755 "$TR/root/etc/init.d/$s"
	done
	chmod 755 "$TR/bin/"*
	# a busybox built with SH_STANDALONE runs its own applets before PATH:
	# route the stubbed commands through shell functions instead
	cat > "$TR/stubs.sh" <<-EOF
	nslookup() { "$TR/bin/nslookup" "\$@"; }
	logger() { "$TR/bin/logger" "\$@"; }
	pidof() { return 1; }
	EOF
	: > "$TR/svc"
	nft delete table inet ps5block 2>/dev/null
}

IP="${IP:-/usr/sbin/ip}"; [ -x "$IP" ] || IP=/sbin/ip
NSENTER="${NSENTER:-/usr/bin/nsenter}"
export PATH="$TR/bin:$PATH" PS5BLOCK_LEASES="$TR/leases" PS5BLOCK_ARP="$TR/arp"
P() { "$TR/root/usr/sbin/ps5block" "$@"; }
U() { "$TR/bin/uci" "$@"; }
J() { P status-json | jsonfilter -e "$1"; }
ruleset() { nft list table inet ps5block 2>/dev/null; }
has_rule() { ruleset | grep -q "comment \"$1\""; }
setelems() { nft list set inet ps5block "$1" 2>/dev/null | tr -d '\n\t' | sed -n 's/.*elements = { \([^}]*\) }.*/\1/p'; }

PS5=f8:46:1c:11:22:33          # Sony Interactive OUI
PS5B=00:d9:d1:aa:bb:cc         # second Sony console
PHONE=3c:22:fb:01:02:03
lease() { echo "$(date +%s) $1 $2 $3 *" >> "$TR/leases"; }

# ==================================================================== tests ==
section "syntax"
for f in root/usr/sbin/ps5block root/etc/init.d/ps5block root/etc/hotplug.d/dhcp/90-ps5block \
	root/etc/hotplug.d/iface/90-ps5block root/etc/uci-defaults/90-luci-ps5block \
	root/usr/libexec/rpcd/ps5block scripts/postinst scripts/prerm scripts/postrm build.sh; do
	check "ash -n $f" "$BB" ash -n "$HERE/$f"
done
for f in root/usr/share/luci/menu.d/luci-app-ps5block.json root/usr/share/rpcd/acl.d/luci-app-ps5block.json \
	root/usr/share/ucitrack/luci-app-ps5block.json; do
	check "json $f" jsonfilter -i "$HERE/$f" -e '@'
done

section "installed disabled"
setup
lease "$PS5" 192.168.1.50 PS5-123
lease "$PHONE" 192.168.1.60 phone
P apply
check "no nft table while disabled" '! nft list table inet ps5block'
check "no dnsmasq entry while disabled" "! grep -q playstation '$TR/root/etc/config/dhcp'"
check "status-json is valid JSON" "[ \"\$(J '@.enabled')\" = false ]"

section "enable, consoles mode"
P enable >/dev/null
check "nft table loaded" nft list table inet ps5block
check "console MAC in set" "setelems consoles | grep -q '$PS5'"
check "phone MAC not in set" "! setelems consoles | grep -q '$PHONE'"
check "lan_if = br-lan" "setelems lan_if | grep -q br-lan"
check "force_dns rule" has_rule force_dns
check "dot rule" has_rule dot
check "doh4 + doh6 rules" 'has_rule doh4 && has_rule doh6'
check "l3 rules" 'has_rule l3_v4 && has_rule l3_v6'
check "no strict DNS without podkop" '! has_rule dns_strict'
check "rules match console MAC" "ruleset | grep 'comment \"dot\"' | grep -q 'ether saddr @consoles'"
check "DoH rule spares port 53" "ruleset | grep 'comment \"doh4\"' | grep -q 'th dport != 53'"
check "chains at -170 / -160" "nft -y list table inet ps5block | grep -q 'priority -170' && nft -y list table inet ps5block | grep -q 'priority -160'"
check "dnsmasq entry added" grep -q "/ps5.update.playstation.net/" "$TR/root/etc/config/dhcp"
check "own dnsmasq entry kept" grep -q "/my.own.entry/" "$TR/root/etc/config/dhcp"
check "dnsmasq restarted" grep -q "dnsmasq restart" "$TR/svc"
check "cron line */20" grep -q '^\*/20 \* \* \* \* .*ps5block refresh .*#ps5block$' "$TR/root/etc/crontabs/root"
check "status: applied, 1 console active" "[ \"\$(J '@.applied')\" = true ] && [ \"\$(J '@.consoles[@.active=true].mac')\" = '$PS5' ]"
check "status: DNS test blocked" "[ \"\$(J '@.layers.dns.test')\" = blocked ]"
check "status: no warnings" "[ -z \"\$(J '@.warnings[*]')\" ]"
check "status text" "P status | grep -q 'Consoles'"
: > "$TR/svc"; P apply >/dev/null
check "re-apply does not restart dnsmasq" "! grep -q dnsmasq '$TR/svc'"
check "re-apply does not rewrite dns state" "[ \"\$(cat '$TR/root/etc/ps5block.dns')\" = ps5.update.playstation.net ]"

section "update server list (L3)"
cat > "$TR/dns" <<-'EOF'
dus01.ps5.update.playstation.net a 23.45.67.89
dus01.ps5.update.playstation.net a 10.0.0.1
dus01.ps5.update.playstation.net a 198.18.0.5
fus01.ps5.update.playstation.net a 23.45.67.90
dus01.ps5.update.playstation.net aaaa 2a02:26f0:1::1
dus01.ps5.update.playstation.net aaaa fd00::1
EOF
P refresh >/dev/null
check "public IPv4 loaded" "setelems upd4 | grep -q 23.45.67.89 && setelems upd4 | grep -q 23.45.67.90"
check "private / fake-ip filtered" "! setelems upd4 | grep -qE '10.0.0.1|198.18.0.5'"
check "resolver addresses not taken as answers" "! setelems upd4 | grep -qE '1.1.1.1|8.8.8.8'"
check "global IPv6 loaded, ULA filtered" "setelems upd6 | grep -q 2a02:26f0:1::1 && ! setelems upd6 | grep -q fd00"
check "status: L3 counts" "[ \"\$(J '@.layers.l3.v4')\" = 2 ] && [ \"\$(J '@.layers.l3.v6')\" = 1 ]"
n="$(grep -c 'update server list' "$TR/log")"
P refresh >/dev/null
check "unchanged refresh is silent" "[ \"\$(grep -c 'update server list' '$TR/log')\" = '$n' ]"
rm -f "$TR/dns"; P refresh >/dev/null
check "failed resolve keeps the list" "setelems upd4 | grep -q 23.45.67.89"
echo "999.1.2.3" > "$TR/root/var/run/ps5block/upd4"
P apply >/dev/null
check "bad cache: apply self-heals" "nft list table inet ps5block && [ ! -s '$TR/root/var/run/ps5block/upd4' ]"

section "consoles"
lease "$PS5B" 192.168.1.51 PS5-456
P sync
check "second console picked up by sync" "setelems consoles | grep -q '$PS5B'"
check "warning multiple_consoles" "J '@.warnings[*]' | grep -q multiple_consoles"
P exclude "$PS5B" >/dev/null
check "excluded console removed from set" "! setelems consoles | grep -q '$PS5B'"
check "status: excluded shown inactive" "[ \"\$(J \"@.consoles[@.mac='$PS5B'].active\")\" = false ]"
P console-set "$PS5B" 1 "PS5 kids" >/dev/null
check "included again with a name" "setelems consoles | grep -q '$PS5B' && [ \"\$(J \"@.consoles[@.mac='$PS5B'].name\")\" = 'PS5 kids' ]"
P add AA:BB:CC:00:00:01 "Manual" >/dev/null
check "manual MAC lowercased and active" "setelems consoles | grep -q aa:bb:cc:00:00:01"
P remove aa:bb:cc:00:00:01 >/dev/null
check "manual MAC removed" "! setelems consoles | grep -q aa:bb:cc:00:00:01"
check "invalid MAC rejected" "! P add 12:34 x"
check "is-console by OUI" P is-console F8:46:1C:00:00:01
check "is-console by hostname" P is-console 02:00:00:00:00:01 PlayStation5
check "phone is not a console" "! P is-console '$PHONE' phone"

section "podkop fully_routed_ips"
cat > "$TR/root/etc/config/podkop" <<-'EOF'

config main 'main'
	list fully_routed_ips '192.168.1.48/30'
EOF
P refresh >/dev/null
check "strict DNS rule added for podkop subnet" "ruleset | grep 'comment \"dns_strict\"' | grep -q 'ip saddr @podkop_routed'"
check "warning podkop_strict:<ip>" "J '@.warnings[*]' | grep -q 'podkop_strict:192.168.1.50'"
U set ps5block.main.dns_strict=0; U commit ps5block; P apply >/dev/null
check "strict off -> warning podkop_ip" "J '@.warnings[*]' | grep -q 'podkop_ip:192.168.1.50' && ! has_rule dns_strict"
U set ps5block.main.dns_strict=1; U commit ps5block; P apply >/dev/null
check "strict on -> applies to all consoles" "ruleset | grep 'comment \"dns_strict\"' | grep -qv podkop_routed"
U set ps5block.main.dns_strict=auto; U add_list podkop.main.domains=playstation.net; U commit; P apply >/dev/null
check "warning podkop_domains" "J '@.warnings[*]' | grep -q podkop_domains"
rm -f "$TR/root/etc/config/podkop"; P refresh >/dev/null
check "podkop gone -> strict rule removed on refresh" '! has_rule dns_strict'

section "options"
U set ps5block.main.dns_block=0; U commit ps5block; P apply >/dev/null
check "dns_block off removes dnsmasq entry" "! grep -q playstation '$TR/root/etc/config/dhcp'"
check "DNS test skipped when DNS layer is off" "[ \"\$(J '@.layers.dns.test')\" = skipped ]"
U set ps5block.main.dns_block=1; U set ps5block.main.refresh_interval=90; U commit ps5block; P apply >/dev/null
check "cron for 90 min" grep -q '^30 \*/1 \* \* \* ' "$TR/root/etc/crontabs/root"
U set ps5block.main.refresh_interval=junk; U commit ps5block; P apply >/dev/null
check "junk interval falls back to 20" "grep -q '^\*/20 ' '$TR/root/etc/crontabs/root' && [ \"\$(J '@.layers.l3.interval')\" = 20 ]"
U set ps5block.main.refresh_interval=20; U commit ps5block

section "whole network mode"
P mode global >/dev/null
check "no MAC match" "! ruleset | grep -q 'ether saddr'"
check "force_dns on" has_rule force_dns
check "dot/doh/l3 off by default" '! has_rule dot && ! has_rule doh4 && ! has_rule l3_v4'
U set ps5block.main.global_block_dot=1; U commit ps5block; P apply >/dev/null
check "global dot can be enabled" "has_rule dot && ruleset | grep 'comment \"dot\"' | grep -q 'iifname @lan_if th\\|iifname @lan_if meta'"
P mode mac >/dev/null

section "stop / disable"
P stop
check "stop removes only the table" "! nft list table inet ps5block && grep -q playstation '$TR/root/etc/config/dhcp'"
P apply >/dev/null
P disable >/dev/null
check "disable: table removed" '! nft list table inet ps5block'
check "disable: dnsmasq entry removed" "! grep -q playstation '$TR/root/etc/config/dhcp' && grep -q my.own.entry '$TR/root/etc/config/dhcp'"
check "disable: dns state removed" "[ ! -e '$TR/root/etc/ps5block.dns' ]"
check "disable: cron line removed" "! grep -q ps5block '$TR/root/etc/crontabs/root'"

section "rpcd"
R() { "$TR/root/usr/libexec/rpcd/ps5block" "$@"; }
check "list is valid JSON" "R list | jsonfilter -e '@.console.mac'"
check "toggle on" "echo '{\"enabled\":true}' | R call toggle | grep -q '\"result\": 0' && nft list table inet ps5block"
check "status" "R call status | jsonfilter -e '@.version'"
check "console: bad action" "echo '{\"mac\":\"$PS5\",\"action\":\"x\"}' | R call console | grep -q 'bad action'"
check "console: invalid MAC reports error" "echo '{\"mac\":\"zz\",\"action\":\"include\"}' | R call console | grep -q 'invalid MAC'"
check "console: exclude" "echo '{\"mac\":\"$PS5\",\"action\":\"exclude\"}' | R call console | grep -q '\"result\": 0' && ! setelems consoles | grep -q '$PS5'"
check "toggle off" "echo '{\"enabled\":false}' | R call toggle >/dev/null && ! nft list table inet ps5block"

section "hotplug"
setup
lease "$PS5" 192.168.1.50 PS5-123
P enable >/dev/null
U delete ps5block.main.autodetect; U commit ps5block
check "dhcp hotplug: phone ignored" "ACTION=add MACADDR='$PHONE' HOSTNAME=phone '$BB' ash '$TR/root/etc/hotplug.d/dhcp/90-ps5block'; [ \$? = 0 ]"
check "iface hotplug: other iface ignored" "ACTION=ifup INTERFACE=wan '$BB' ash '$TR/root/etc/hotplug.d/iface/90-ps5block'"

section "migration from the old scripts (uci-defaults)"
setup
rm -f "$TR/root/etc/config/ps5block"
printf 'ENABLED=1\nPS5_MAC="F8:46:1C:11:22:33 00:D9:D1:AA:BB:CC"\n' > "$TR/root/etc/ps5block.conf"
cat > "$TR/root/etc/config/firewall" <<-'EOF'

config rule 'ps5blk_dot'
	option name 'ps5blk dot'

config rule 'user_rule'
	option name 'mine'
EOF
for a in /dus01.ps5.update.playstation.net/ /fjp01.ps5.update.playstation.net/ /gs2.ww.prod.dl.playstation.net/ /sgst.prod.dl.playstation.net/; do
	U add_list dhcp.@dnsmasq[0].address="$a"
done
U commit dhcp
echo "*/30 * * * * /root/ps5block.sh refresh" > "$TR/root/etc/crontabs/root"
echo "0 4 * * * /root/backup.sh" >> "$TR/root/etc/crontabs/root"
( cd "$TR/root/etc/uci-defaults" && . ./90-luci-ps5block )
check "config created and enabled" "[ \"\$(U get ps5block.main.enabled)\" = 1 ]"
check "old consoles migrated (lowercase)" "U show ps5block | grep -q \"mac='f8:46:1c:11:22:33'\" && U show ps5block | grep -q \"mac='00:d9:d1:aa:bb:cc'\""
check "old firewall rules removed, user rule kept" "! U -q get firewall.ps5blk_dot && U get firewall.user_rule"
check "old dnsmasq entries removed (incl. game domains)" "! grep -qE 'dus01|fjp01|gs2.ww|sgst' '$TR/root/etc/config/dhcp'"
check "own dnsmasq entry kept" grep -q my.own.entry "$TR/root/etc/config/dhcp"
check "old cron line removed, user cron kept" "! grep -q ps5block.sh '$TR/root/etc/crontabs/root' && grep -q backup.sh '$TR/root/etc/crontabs/root'"
check "old conf removed" "[ ! -e '$TR/root/etc/ps5block.conf' ]"
U set ps5block.main.mode=global; U commit ps5block
( cd "$TR/root/etc/uci-defaults" && . ./90-luci-ps5block )
check "second run keeps user settings" "[ \"\$(U get ps5block.main.mode)\" = global ]"

# --------------------------------------------------------- live traffic ------
section "live traffic (bridge, console + phone)"
if [ -x "$IP" ] && [ -x "$NSENTER" ] && "$IP" link add br-lan type bridge 2>/dev/null; then
	setup
	"$IP" addr add 192.168.1.1/24 dev br-lan; "$IP" link set br-lan up; "$IP" link set lo up
	pids=""
	for h in console phone; do
		unshare -n "$BB" sleep 600 & pid=$!; pids="$pids $pid"; sleep 0.2
		eval "PID_$h=$pid"
		"$IP" link add "v-$h" type veth peer name eth0 netns "$pid"
		"$IP" link set "v-$h" master br-lan up
	done
	inns() { n="$1"; shift; "$NSENTER" -t "$(eval echo \$PID_$n)" -n "$@"; }
	inns console "$IP" link set eth0 address "$PS5"
	inns phone "$IP" link set eth0 address "$PHONE"
	inns console "$IP" addr add 192.168.1.50/24 dev eth0; inns phone "$IP" addr add 192.168.1.60/24 dev eth0
	for h in console phone; do
		inns $h "$IP" link set eth0 up; inns $h "$IP" link set lo up; inns $h "$IP" route add default via 192.168.1.1
	done
	lease "$PS5" 192.168.1.50 PS5-123; lease "$PHONE" 192.168.1.60 phone
	P enable >/dev/null
	send() { # host ip port: one UDP datagram and one TCP SYN
		inns "$1" "$BB" sh -c "echo x | $BB nc -u -w1 $2 $3; $BB nc -w1 $2 $3 </dev/null" >/dev/null 2>&1
	}
	cnt() { nft list table inet ps5block | grep "comment \"$1\"" | sed -n 's/.*packets \([0-9]*\).*/\1/p' | head -1; }
	sleep 1
	send console 1.1.1.1 443; send console 9.9.9.9 853; send console 8.8.8.8 53
	check "console: DoH to 1.1.1.1:443 dropped" "[ \"\$(cnt doh4)\" -gt 0 ]"
	check "console: DoT to :853 dropped" "[ \"\$(cnt dot)\" -gt 0 ]"
	check "console: DNS to 8.8.8.8 redirected" "[ \"\$(cnt force_dns)\" -gt 0 ]"
	d1="$(cnt doh4)"; t1="$(cnt dot)"; f1="$(cnt force_dns)"
	send phone 1.1.1.1 443; send phone 9.9.9.9 853; send phone 8.8.8.8 53
	check "phone: not touched" "[ \"\$(cnt doh4)\" = '$d1' ] && [ \"\$(cnt dot)\" = '$t1' ] && [ \"\$(cnt force_dns)\" = '$f1' ]"
	check "status: packet counters" "[ \"\$(J '@.layers.dot.packets')\" -gt 0 ]"
	kill $pids 2>/dev/null
else
	echo "  skip (cannot create a bridge here)"
fi

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" = 0 ]
