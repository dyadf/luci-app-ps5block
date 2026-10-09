# Contributors

People and tools that took part in luci-app-ps5block. Listed in order of joining.

| Who | Role |
|---|---|
| [dyadf](https://github.com/dyadf) | Author and maintainer: idea, requirements, router setup (GL-MT6000, podkop, zapret2, DoH), review and testing |
| Claude (Anthropic AI model) | Co-author: backend, LuCI view, translation, build and signing scripts, test bench, documentation |

## Acknowledgements

- **pureair** — author of the earlier `ps5_update_block.sh` script; the package migrates and replaces its dnsmasq entries.
- The [OpenWrt](https://openwrt.org/) and [LuCI](https://github.com/openwrt/luci) projects — `uci`, `jshn`, `jsonfilter`, `usign`, `po2lmo`, firewall4 and the LuCI JavaScript API this package is built on.
- [apk-tools](https://gitlab.alpinelinux.org/alpine/apk-tools) — `apk` v3 for packaging and signing.
- The [podkop](https://github.com/itdoginfo/podkop) and zapret projects, whose rule layout the package is designed around.

## Contributing

Bug reports and pull requests are welcome. Please include the output of
`ps5block status` and `logread -e ps5block`, your OpenWrt version and router model.
Before sending a change, run `tests/run.sh` and `node tests/view.test.js` (see README → Tests).
By contributing you agree that your contribution is licensed under the MIT license.
