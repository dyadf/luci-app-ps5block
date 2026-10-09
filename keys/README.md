# Package signing keys (public)

| File | Used by | Install on the router as |
|---|---|---|
| `eec9661fb33aa0db` | opkg (OpenWrt 22.03–24.10), usign key that signs the feed index `Packages` | `/etc/opkg/keys/eec9661fb33aa0db` |
| `ps5block.pem` | apk (OpenWrt 25.x+), EC P-256 key that signs every `.apk` and `packages.adb` | `/etc/apk/keys/ps5block.pem` |

Check the usign key fingerprint: `usign -F -p eec9661fb33aa0db` → `eec9661fb33aa0db`.

The private keys are kept by the maintainer and are never committed.
