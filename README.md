# luci-app-ps5block — PS5 system update blocker for OpenWrt

[![Release](https://img.shields.io/github/v/release/dyadf/luci-app-ps5block)](https://github.com/dyadf/luci-app-ps5block/releases/latest) [![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE) ![OpenWrt 22.03+](https://img.shields.io/badge/OpenWrt-22.03%2B%20(fw4)-00b5e2)

[Русская версия](README.ru.md)

An OpenWrt package with a LuCI web interface that stops a PlayStation 5 from downloading and installing system software updates. **Games, patches, PSN, the store and every other device on the network keep working.**

- One-click on/off in LuCI (**Services → PS5 Update Block**).
- Automatic console detection by MAC vendor (Sony Interactive Entertainment) and device name. If several consoles are found, LuCI lists them all and any of them can be excluded.
- Two modes: **consoles only** (by MAC) or **whole network**.
- Detailed status: which protection layers are active, drop counters, a DNS check run on the router itself.
- Aware of **podkop** and **zapret/zapret2**: the rules run before them, so update traffic cannot be carried around the block through a proxy.
- Built-in console setup guide.
- One package: `.ipk` for opkg (OpenWrt 22.03–24.10) and `.apk` for apk (OpenWrt 25.x and later).

## How it works

The block has several layers. Each one closes a different way around it:

| # | Layer | What it does | What it stops |
|---|---|---|---|
| 1 | DNS block | dnsmasq answers "no such domain" for `*.ps5.update.playstation.net` | the normal lookup of the update server |
| 2 | DNS redirect | every DNS request from the console (port 53, any server, IPv4/IPv6) is answered by the router | manual DNS on the console (8.8.8.8 etc.) |
| 3 | Strict DNS | external DNS is dropped **before** podkop | podkop routing the console completely and intercepting its DNS |
| 4 | DoT / DoQ | port 853 is dropped | encrypted DNS |
| 5 | DoH | ~90 addresses of public DNS/DoH resolvers are dropped (Cloudflare, Google, Quad9, AdGuard, Yandex, OpenDNS, NextDNS, …) | DNS over HTTPS |
| 6 | L3 | update server IP addresses are dropped; the router resolves them itself and refreshes the list on a schedule | a console that already knows the server IP |

All rules (except the dnsmasq entry) live in a dedicated nftables table `inet ps5block` at priority **−170**. That is before podkop's mangle chain (−150) and before zapret's queues, so a dropped packet never reaches them. Restarting the firewall, podkop or zapret does not touch the table.

```
packet from console ──► ps5block (−170): DoT / DoH / L3 / strict DNS ── drop
                              │
                              ▼
                     podkop mangle (−150) ──► NAT (−100): DNS redirect to dnsmasq
                              │                                 │
                              ▼                                 ▼
                   forward / zapret / WAN           dnsmasq: NXDOMAIN for the update domain
```

Only `ps5.update.playstation.net` and its subdomains are blocked; that is system software. Games and patches come from other domains and keep working.

## What to block

The DNS layer has three presets (**Advanced → "What to block"**, or `option blocklist`):

| Preset | Blocks | Games / store / PSN |
|---|---|---|
| **updates** (default) | system software update servers only (`update.playstation.net` + the Akamai update CDN) | keep working |
| **all** | every PlayStation/PSN server — downloads (incl. games), store, sign-in, community, STUN, APIs, `ribob01.net`, … | cut off |
| **custom** | only the domains you add under "Extra blocked domains" | — |

The preset lists live in `/usr/share/ps5block/domains.updates` and `domains.all`; "Extra blocked domains" are added on top (for **custom**, they are the whole list). The IP-level (L3) layer always targets update servers only.

## Requirements

- OpenWrt **22.03 or later** with firewall4 (nftables). This is the default since 22.03 and is also required by podkop and zapret2.
- LuCI.
- dnsmasq (the default OpenWrt DNS server; `dnsmasq-full` works too).

## Installation

The packages are signed with the project key (not the OpenWrt key). The public keys are in [`keys/`](keys/) and attached to every [release](https://github.com/dyadf/luci-app-ps5block/releases).

### Option 1: package feed (recommended, updates through opkg/apk)

**OpenWrt 22.03–24.10 (opkg):**

```sh
wget -O /etc/opkg/keys/eec9661fb33aa0db https://raw.githubusercontent.com/dyadf/luci-app-ps5block/main/keys/eec9661fb33aa0db
echo "src/gz ps5block https://github.com/dyadf/luci-app-ps5block/releases/latest/download" >> /etc/opkg/customfeeds.conf
opkg update && opkg install luci-app-ps5block
```

**OpenWrt 25.x and later (apk):**

```sh
wget -O /etc/apk/keys/ps5block.pem https://raw.githubusercontent.com/dyadf/luci-app-ps5block/main/keys/ps5block.pem
echo "https://github.com/dyadf/luci-app-ps5block/releases/latest/download/packages.adb" >> /etc/apk/repositories.d/customfeeds.list
apk update && apk add luci-app-ps5block
```

The signature is checked on every `opkg update` / `apk update`; without the key the package does not install. To update: `opkg upgrade luci-app-ps5block` or `apk upgrade luci-app-ps5block`.

### Option 2: package file by hand

Download the `.ipk` or `.apk` from the [releases page](https://github.com/dyadf/luci-app-ps5block/releases) and copy it to the router (`-O` is needed when the router has no sftp server):

```sh
scp -O luci-app-ps5block_1.4.0-r1_all.ipk root@192.168.1.1:/tmp/   # OpenWrt 22.03–24.10
scp -O luci-app-ps5block-1.4.0-r1.apk     root@192.168.1.1:/tmp/   # OpenWrt 25.x and later
```

On the router:

```sh
# OpenWrt 22.03–24.10 (opkg)
opkg install /tmp/luci-app-ps5block_1.4.0-r1_all.ipk

# OpenWrt 25.x and later (apk): with the key from keys/ in /etc/apk/keys/ the
# signature is checked, without it --allow-untrusted is needed
apk add /tmp/luci-app-ps5block-1.4.0-r1.apk
```

File checksums are in `SHA256SUMS` in the release.

Reload LuCI and open **Services → PS5 Update Block**. The package installs **disabled**, unless traces of the older scripts are found; then protection stays on (see "Migrating from the old scripts").

## First start

1. Turn the console on so it gets an address from the router.
2. In LuCI press **"Enable blocking"**.
3. The console appears in the list as **"Blocked"**. A PS5 has different MAC addresses for cable and Wi-Fi; both are detected once the console has used them.
4. Check "Protection layers": every enabled layer should be "Active", and the DNS check should say "update domain does not resolve".

### Console setup

The same guide is at the bottom of the LuCI page.

1. **DNS "Automatic":** Settings → Network → Settings → Set Up Internet Connection → your network → Advanced Settings → DNS Settings: Automatic. Manual DNS is redirected too, but "Automatic" is the most reliable, especially with podkop.
2. **Turn off automatic updates:** Settings → System → System Software → System Software Update and Settings → turn off "Download Update Files Automatically" and "Install Update Files Automatically".
3. **Delete an update that was already downloaded.** The router cannot remove what is already on the console.
4. **Power the console off completely and on again** (not rest mode) so it forgets cached DNS answers.
5. **Check:** … → Update System Software → Update Using Internet. The console must report an error instead of finding a new version.

## Modes

| Setting | Consoles only (default) | Whole network |
|---|---|---|
| Applies to | PlayStation consoles only (by MAC) | every client of the selected networks |
| DNS block | on | on |
| DNS redirect | on | on |
| Strict DNS | auto (only for consoles podkop routes completely) | off |
| DoT / DoQ | on | off |
| DoH | on | off |
| L3 (server IPs) | on | off |

In "Whole network" mode the layers that could affect other devices are off by default. They can be turned on in the "Protection layers" tab.

**When to use "Whole network":** when the console cannot be recognised by MAC (for example, MAC randomisation is on) or when you want a block without exceptions.

## Several consoles

When more than one console is found, LuCI shows a warning and lists them all. With auto-detection on, all of them are blocked. To let a console update, press **"Exclude"** next to it. A console that is not detected can be added under "Consoles added by hand".

## Sending payloads

Independently of the update block, the router can send a homebrew **payload** to a console on the LAN. Next to each console in the status list there is a **"Send payload"** button: pick an ELF/bin file and the router streams it to the console over TCP on port **9021** (configurable under **Advanced → "Payload port"**).

- The console must already be running a payload loader that listens on that port (set up on the console itself, from its browser/exploit entry point). This package does not exploit or modify the console; it only transfers a file you provide to a loader that is already listening.
- The uploaded file lives only in the router's RAM (`/tmp/ps5block-payload/`) and is **deleted right after it is sent**, whether the send succeeds or fails.
- **The port is checked automatically before sending.** The payload is transmitted to the console only if its loader is listening on the port; otherwise nothing is sent and the uploaded file is removed. You can also check on demand with the **"Check port"** button or `ps5block payload-check <MAC|IP>` (open / closed / no IP).
- A loader that accepts only a **single** connection would spend it on the automatic check. For such a loader, send from the command line with the check disabled: `PS5BLOCK_SKIP_PORTCHECK=1 ps5block payload <MAC|IP> <file>`.
- From the command line: `ps5block payload <MAC|IP> <file>` (the file must be in `/tmp/ps5block-payload/`).

This is meant for your own console on your own network.

## podkop, zapret and DoH

- **podkop.** Compatible, including podkop's own DNS handling. podkop (and fw4/AdGuard) redirect LAN DNS at NAT priority −100; this package redirects the console's DNS at −160, so it **claims the console's queries first** and they always reach dnsmasq — the DNS block is not bypassed even when podkop owns port 53. This covers "Automatic" DNS on the console too (all of its port-53 traffic is caught, not only queries to external servers). The DoT/DoH/L3 drops run at −170, before podkop's −150, so update traffic never reaches the proxy. Only the console is affected; other clients keep using podkop's DNS. When the podkop list changes, the rules rebuild themselves on the next refresh (every 20 minutes by default) or at once with "Re-apply rules". **Do not put playstation domains into podkop lists**; the package warns if it finds them.
- **zapret / zapret2.** Compatible. zapret works on outgoing WAN traffic, and dropped packets never get there.
- **DoH on the router (https-dns-proxy etc.).** Compatible: it is dnsmasq's upstream, and the dnsmasq entry answers first.
- **AdGuard Home.** If it replaces dnsmasq on port 53, the DNS layer does not work: add `||ps5.update.playstation.net^` to its blocklist. All other layers keep working.

## Forcing the console's DNS

By default the console's DNS is redirected to the router's dnsmasq (that is how the DNS block works); only the console's DNS aimed at **external** servers is redirected, so "Automatic" DNS on the console keeps working through the router and general internet is never broken.

To make the console use **specific** resolver(s) instead, set **Protection layers → "Force DNS to this server"** (`list dns_server`) — one or more IPs. The console's port-53 is then sent to them, overriding podkop/AdGuard; with several, queries are spread across them. **Make sure the servers are reachable — a dead server here means no DNS for the console.** With a non-router server the built-in dnsmasq block no longer applies to the console; the update block then relies on the IP (L3) and DoT/DoH layers, or on that server's own filtering. (The "Resolvers" field is unrelated — it only tells the router which DNS to use when looking up the update servers' IPs for the L3 layer.)

## Command line

```sh
ps5block status          # detailed status
ps5block enable|disable  # turn on / off
ps5block mode mac|global # mode
ps5block detect          # detected consoles
ps5block add AA:BB:CC:DD:EE:FF "PS5 living room"  # add by hand
ps5block exclude AA:BB:CC:DD:EE:FF                # exclude a console
ps5block remove AA:BB:CC:DD:EE:FF                 # forget a hand-added console
ps5block refresh         # refresh update server IPs and consoles
ps5block ruleset         # print the nftables rules that would be loaded
ps5block payload AA:BB:CC:DD:EE:FF payload.bin   # send /tmp/ps5block-payload/payload.bin, then delete it
ps5block payloads        # list uploaded payloads waiting to be sent (JSON)
ps5block payload-check AA:BB:CC:DD:EE:FF          # is the console listening on the payload port? (JSON)
```

Settings live in `/etc/config/ps5block`; logs: `logread -e ps5block`.

## Migrating from the old scripts

On installation the package cleans up after the earlier scripts:

- **`ps5_update_block.sh`** (pureair): 41 dnsmasq entries, including `gs2.ww.prod.dl…` and `sgst.prod.dl…`, which most likely also blocked game downloads.
- **`ps5block.sh`** (stand-alone script): `ps5blk_*` firewall rules, include, cron, `/etc/ps5block.conf`.

Your own dnsmasq entries, firewall rules and cron jobs are not touched. If the old block was active, the package starts enabled and carries the console MAC addresses over, so protection is never interrupted.

## Removal

```sh
opkg remove luci-app-ps5block   # or: apk del luci-app-ps5block
```

Removal deletes the nftables table, the dnsmasq entry and the cron job. `/etc/config/ps5block` stays; delete it by hand if you no longer need it.

## Troubleshooting

| Symptom | What to check |
|---|---|
| Console not listed | It must get its address from this router. Run `ps5block detect`. If it is missing, add the MAC by hand (PS5: Settings → System → System Software → Console Information). |
| A layer says "Not loaded" | Press "Re-apply rules" and read the nftables error on the page or in `logread -e ps5block`. |
| "update domain still resolves" | DNS is not served by dnsmasq (e.g. AdGuard Home), or the entry was removed by hand. Press "Re-apply rules". |
| The console still found an update | It was downloaded earlier (delete it on the console); the console is on another network; the console is not in the blocked list. |
| Something other than updates breaks | Turn off L3 in "Protection layers": CDN addresses are shared with other services. |

## Limitations

The router only controls its own network. A console connected to another network (phone hotspot, another router), or updated from a USB drive, is not covered. Sony may change the update domains; the domain list can be edited in LuCI ("Advanced" tab).

## Building from source

```sh
# quick .ipk and .apk build without the SDK → dist/
PO2LMO=/path/to/po2lmo APK=/path/to/apk ./build.sh

# signed: .apk + packages.adb (EC P-256) and Packages.sig for opkg (usign)
PO2LMO=... APK=... APK_KEY=~/keys/apk-private.pem \
  USIGN=/path/to/usign USIGN_KEY=~/keys/usign.sec ./build.sh

# or in the OpenWrt SDK: put the directory into feeds/luci/applications/
make package/luci-app-ps5block/compile
```

`po2lmo` is built from `luci/modules/luci-base/src`, `apk` from apk-tools 3.x, `usign` from `git.openwrt.org/project/usign`. The version comes from the `Makefile` (`PKG_VERSION`, `PKG_RELEASE`). Private keys never go into the repository (`.gitignore`); the public keys are in `keys/`.

## Tests

```sh
# backend: busybox ash + the real uci/jshn/jsonfilter (built for the host) + the real nft
# in a private user/network namespace; the host is not touched
JSHN=/path/to/jshn.sh PATH=/path/to/openwrt-host-tools/bin:$PATH tests/run.sh

# LuCI page: strings from the router never end up as HTML
node tests/view.test.js
```

`tests/run.sh` covers enable/disable, the nftables rules, dnsmasq, cron, the update server list, consoles, podkop, rpcd, hotplug, migration from the old scripts and live traffic through a bridge with a "console" and a "phone" (147 checks).

The package was also tested in an emulated OpenWrt environment: busybox ash, the real `uci`, `jshn`, `jsonfilter`, `opkg` and `apk` 3.0 built from OpenWrt sources, the real `nft` with a Linux kernel; installation, reinstallation and removal with opkg and apk, installation from the signed apk feed; rendering of the LuCI page in English and Russian.

**It has not been run on a physical router yet.** If something goes wrong, please open an [issue](https://github.com/dyadf/luci-app-ps5block/issues) with the output of `ps5block status` and `logread -e ps5block`.

## Contributors

See [CONTRIBUTORS.md](CONTRIBUTORS.md). Changes are listed in [CHANGELOG.md](CHANGELOG.md).

## License

[MIT](LICENSE) © 2026 arsutov and contributors.

The MAC prefix list (`oui.txt`) is taken from the public IEEE MA-L registry and the DNS resolver addresses from their operators' public documentation; both are factual data. LuCI, OpenWrt, podkop and zapret are separate projects under their own licenses; none of their code is included. PlayStation and PS5 are trademarks of Sony Interactive Entertainment; this project is not affiliated with Sony.
