# Changelog

## 1.5.0-r1 — 2026-10-10

### Added
- **L3 (IP-level) drop for all PSN servers in "all" mode.** In `blocklist=all` mode,
  all PlayStation / PSN domains are now resolved into IP addresses and populated into
  the L3 drop sets (`@upd4` / `@upd6`) alongside the system update servers. Shared CDN/DNS
  domains (`a192.d.akamai.net`, `sony.akadns.net`) are skipped from IP drops to protect
  unrelated traffic.
  This ensures that even when "Force DNS to this server" is not configured (or when the
  router's DNS dispatcher directs traffic away from dnsmasq), the console's connections
  to PSN servers are dropped at the firewall level (`filter prerouting -170`), independent
  of DNS.
- **DNS blocking preserved when "Force DNS to this server" (`dns_server`) is configured.**
  Previously, pointing `dns_server` to an external resolver bypassed the router's DNS
  block rules via direct DNAT, leaving DNS blocking inactive on the console.
  `ps5block` now launches an isolated, lightweight local dnsmasq forwarder on port 5553
  whenever custom `dns_server` entries are configured. The forwarder serves the active
  blocklists (update servers, presets, and custom domains) directly as NXDOMAIN, while
  forwarding allowed queries to the specified upstream server(s). Redirect rules in
  nftables send console port-53 queries to this dedicated forwarder, preserving full DNS
  blocking while honoring the chosen DNS server.
- **Expanded PSN domain list in `domains.all`.** Added apex domains (`playstation.com`,
  `playstation.net`, `psndl.net`), dedicated download/API endpoints (`feature.api.playstation.com`,
  `gst.prod.dl.playstation.net`, `ena.net.playstation.net`, `post.net.playstation.net`),
  and regional PlayStation TLDs.
- **Wildcard normalization.** Domain entries with `*.` (e.g. `*.playstation.com`) are
  automatically normalized to their apex domain for dnsmasq, ensuring valid dnsmasq syntax
  while cleanly blocking the domain and all its subdomains.
- **Test suite synchronization.** Added stub locking in the test harness to serialize
  background and foreground refreshes; test suite expanded to 158 checks.

## 1.4.0-r1 — 2026-10-09

### Fixed (important)
- **No internet when "Force DNS" was not configured.** 1.2.1 made force-DNS grab *all* of
  the console's port-53 traffic, including queries aimed at the router, and send it to
  dnsmasq. On routers where the working resolver is not dnsmasq (podkop/AdGuard own DNS),
  that broke name resolution for the console entirely. force-DNS again only redirects the
  console's DNS to **external** servers (`fib daddr type != local`); DNS the console already
  sends to the router ("Automatic") is left on the router's own resolver path, so general
  internet is never broken.

### Added
- **"Force DNS to this server" now takes several servers** (`list dns_server`). With more
  than one, the console's DNS is spread across them (`numgen`-based DNAT). A set server
  forces the console's DNS (including "Automatic") onto it; the other IP family still goes
  to the router. Make sure the servers are reachable — a dead one means no DNS for the
  console. The status page lists the active target(s).

## 1.3.0-r1 — 2026-10-09

### Added
- **"Force DNS to this server" (`dns_server`).** Optionally send the console's DNS to a
  specific resolver instead of the router's dnsmasq — the console's port-53 is DNAT'd to
  that server at priority −160, overriding podkop/AdGuard. Empty = the router (default,
  needed for the built-in dnsmasq block). With a non-router server the dnsmasq block does
  not apply to the console; blocking then relies on the L3/DoT/DoH layers or that server's
  own filtering. The status page shows the active DNS target. (Note: the separate
  "Resolvers" field only feeds the update-server IP lookup; it never changed the console's
  DNS — this new option does.)

## 1.2.1-r1 — 2026-10-09

### Fixed (works without any manual router steps)
- **DNS redirect now catches the console even on "Automatic" DNS.** The force-DNS rule
  dropped its `fib daddr type != local` condition, so it redirects *all* of the console's
  port-53 traffic — including queries already aimed at the router — to dnsmasq. Our chain
  runs at priority −160, before fw4/podkop/AdGuard DNS dispatchers at −100, so it claims the
  NAT first and the console always resolves via dnsmasq (the update block is no longer
  bypassed by a DNS redirector). Other clients are untouched (the rule is console-scoped).
- **L3 no longer depends on a single resolver.** Public fallbacks (1.1.1.1, 8.8.8.8, 9.9.9.9)
  are always queried alongside the configured one, so a dead/misconfigured resolver can no
  longer leave the update-server IP list empty. The L3 layer drops update servers by IP at
  −170 (before podkop), so it works even where a DNS dispatcher owns port 53.

## 1.2.0-r1 — 2026-10-09

### Added
- **Blocklist modes (DNS).** New `blocklist` setting / "What to block" selector:
  - **updates** (default) — system software update servers only (`update.playstation.net`
    and the Akamai update CDN); games, the store and PSN keep working.
  - **all** — every PlayStation/PSN server aggregated from a real AdGuard Home list
    (downloads incl. games, store, sign-in, community, STUN, APIs, ribob01.net, …);
    the console is fully cut off from Sony.
  - **custom** — only the domains you list.
  Shipped lists: `/usr/share/ps5block/domains.{updates,all}`. The `domain` list is now
  *extra* domains added on top of the preset. Russian translation added.

## 1.1.2-r1 — 2026-10-09

### Fixed
- **Payload send and port check failed on a real router** with a busybox `nc` usage error.
  OpenWrt's busybox `nc` is the minimal build (`nc IPADDR PORT`, no `-w`); the code now
  bounds `nc` with the `timeout` applet instead of passing `-w`.

### Changed
- **The port is now checked automatically before a payload is sent.** Nothing is transmitted
  to the console unless its loader is listening; otherwise the upload is removed and the LuCI
  page reports the closed port. For a one-shot loader, send from the CLI with
  `PS5BLOCK_SKIP_PORTCHECK=1`. `ps5block payload` exit codes: 0 sent, 3 no IP, 4 port closed.

## 1.1.1-r1 — 2026-10-09

### Added
- **Payload port status check.** A "Check port" button next to each console (and
  `ps5block payload-check <MAC|IP>`) reports whether the console's loader is listening
  on the payload port: open / closed / no IP. It is an explicit action and is never run
  automatically before a send, because a one-shot loader could treat the probe as its
  one accepted connection. rpcd method `payload_check`; Russian translation; 120 checks.

## 1.1.0-r1 — 2026-10-09

### Added
- **Send a homebrew payload to a console.** Each console in the status list gets a
  "Send payload" button: upload an ELF/bin file and the router streams it to the
  console's payload loader over TCP (default port **9021**, configurable under
  Advanced → "Payload port"). The uploaded file is held only in tmpfs and is
  **deleted from the router right after sending**. The console must already be
  running a payload loader; this only transfers the file.
- CLI: `ps5block payload <MAC|IP> <file>` and `ps5block payloads`.
- rpcd methods `payload`, `payload_prepare`, `payloads`; ACL for `cgi-io` upload to
  `/tmp/ps5block-payload/`. Russian translation for the new strings.
- Tests: payload port sanitization, listing, error paths, and live delivery to a
  listener in the console namespace over the bridge (114 checks total).

## 1.0.1-r1 — 2026-10-09

First public release.

### Fixed
- LuCI: console names, hostnames, nftables errors and backend error messages were inserted
  into the page as HTML; they are now shown as text.
- LuCI: an error from the "Exclude" / "Block" / "Forget" buttons was lost because the page
  reloaded at once; the page now stays and shows the message.
- Hotplug detection by device name was case-sensitive (`PS5-123`, `PlayStation5` were not
  recognised until the next periodic refresh).
- DNS check reported "still resolves" when the DNS layer was turned off; it is now skipped.
- A non-numeric refresh interval broke the background refresh; it now falls back to 20 minutes.
- Update server lookups: the resolver's own address line is no longer read as an answer.

### Changed
- The update server refresh logs only when the address list changes (no syslog line every 20 minutes).
- `/etc/ps5block.dns` is written only when it changes (less flash wear) and is kept across sysupgrade.
- Disabling the block no longer enables the cron service.
- Build: version and maintainer come from the `Makefile`; file permissions no longer depend on the
  checkout (Windows); reproducible gzip; signed `.apk`; signed opkg (`Packages.sig`) and apk
  (`packages.adb`) feeds; `SHA256SUMS`.
- Test bench (`tests/run.sh`, 98 checks incl. live traffic) and LuCI view test (`tests/view.test.js`).

## 1.0.0-r1

Initial version (not published).
