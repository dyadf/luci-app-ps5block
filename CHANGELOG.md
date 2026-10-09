# Changelog

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
