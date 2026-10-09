# Changelog

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
