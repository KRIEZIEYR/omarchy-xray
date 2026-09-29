# Xray for Omarchy

An [Omarchy](https://omarchy.org) shell widget that runs your Xray
subscription in the background and gives you a remote control in the bar:
connect/disconnect, node switching (or **Auto** — best ping), proxy or
**TUN** mode, routing presets, latency tests, subscription updates and live
traffic.

```
Panel.qml ──▶ omarchy-xray (manager, ~/.local/bin)
                 ├─ both modes ─▶ systemd --user  omarchy-xray.service  ─▶ /usr/bin/xray (no privileges)
                 └─ TUN mode   ─▶ systemd --user  omarchy-xray-tun2socks.service ─▶ tun2socks (no privileges)
                                   └─ starts ─▶ systemd system  omarchy-xray-tun.service (root: ip + resolvectl only)
Panel.qml ──▶ curl 127.0.0.1:15491/debug/vars  (live traffic, straight from xray)
```

No daemon accounts, no passwords, no REST — the widget runs `omarchy-xray`
commands and reads JSON back.

## Features

- every node from your subscriptions, grouped per subscription, filter as you type
- **VLESS, VMess, Trojan, Shadowsocks (incl. 2022), Hysteria2** share links,
  plus Xray-JSON subscriptions (Remnawave/Marzban style)
- **every transport the current Xray core supports** (see the table below)
- **Auto** node: Xray's observatory + `leastPing` balancer picks the best live node
- **proxy mode** (no privileges) and **TUN mode** (whole system, one-time setup)
- routing presets: **Global** / **Direct** for one region (RU, BY, KZ, UZ, TM, CN, IR, TR, AE, SA, EG, PK, VN, MM), optional **Adblock**
- `custom.json` for anything else the core can do (rules, DNS, mux, fragment…)
- subscription info: traffic used/total and expiry (`subscription-userinfo`),
  `profile-title`, automatic refresh (`profile-update-interval`, default 24 h)
- latency tests: batched and parallel, one xray process per 32 nodes
- live traffic counters and speeds from xray's metrics endpoint (loopback)
- keyboard-first: `j/k` move through the MODE/ROUTE rows and the nodes, `h/l` choose, `Enter` apply/connect, `/` filter, `t` test (again to stop), `u` update, `c` toggle, `w` config folder
- IPC verbs for Hyprland binds

## Protocols and transports

| Link | Xray outbound |
|---|---|
| `vless://` | VLESS, incl. `flow` (Vision) and **VLESS Encryption** (`mlkem768x25519plus…`, ML-KEM keys) |
| `vmess://` | VMess (base64 JSON form and `vmess://uuid@host` form) |
| `trojan://` | Trojan |
| `ss://` | Shadowsocks: SIP002, legacy base64, 2022-blake3-* (plugins are not supported by Xray) |
| `hysteria2://`, `hy2://` | Hysteria2 (`auth`, `sni`, `obfs=salamander`, `pinSHA256`; port hopping uses the first port) |

| `type=` | Xray transport | Notes |
|---|---|---|
| `tcp` / `raw` | RAW | `headerType=http` (host/path) supported |
| `ws` | WebSocket | `host`, `path` (incl. `?ed=` early data) |
| `grpc` | gRPC | `serviceName`, `authority`, `mode=multi` |
| `xhttp` / `splithttp` | XHTTP | `mode`, `host`, `path`, `extra` (JSON) |
| `httpupgrade` | HTTPUpgrade | `host`, `path` |
| `kcp` / `mkcp` | mKCP | `seed` and `headerType` via Xray's `finalmask` (`mkcp-legacy`) |
| (Hysteria2) | hysteria | QUIC, salamander via `finalmask` |
| `h2`, `http`, `h3`, `quic` | — | **removed from Xray-core** — such nodes are skipped with a reason (use XHTTP) |

Security: `tls` (`sni`, `fp`, `alpn`, `ech`, `pcs`, `vcn`), `reality`
(`pbk`, `sid`, `spx`, `pqv` / ML-DSA-65), `none`. Unknown fingerprints fall
back to `chrome`. Xray-core no longer supports `allowInsecure`; such links
are used with normal certificate verification (pin with `pcs` instead), and
VLESS/Trojan without TLS/REALITY/VLESS-encryption to a public server is
refused by the core (Xray ≥ 26.7), so those nodes are skipped with that reason.

After every fetch the node list is checked against **your installed core**
(`xray run -test`): a node the core rejects is dropped with a reason instead
of breaking the tunnel. Only the selected node (or the Auto members) goes
into `config.json`, and every generated config is tested before it replaces
the running one.

## Requirements

- Omarchy Quattro (shell plugins)
- Xray core **≥ 26.6.1** (tested with 26.6.1 and 26.9.9) — install it yourself from a source you trust (e.g. review the AUR
  package, then `omarchy pkg aur add xray`). The installer never installs it
  for you and never grants capabilities to any binary. Older cores still work
  for most nodes; whatever they reject is skipped with a reason, and
  `omarchy-xray doctor` warns about the version.
- TUN mode only: [tun2socks](https://github.com/xjasonlyu/tun2socks) ≥ 2.5
  (`omarchy pkg aur add tun2socks`; review the package first). It runs as your
  user without privileges.
- optional geo data for the presets (`geoip.dat`, `geosite.dat`; on Arch:
  `v2ray-geoip`, `v2ray-domain-list-community`). Found automatically in
  `$XRAY_LOCATION_ASSET`, next to the xray binary, `/usr/share/xray` or
  `/usr/share/v2ray`.
- `/usr/bin/python3`, `curl` (already part of Omarchy)

## Install

```bash
git clone https://github.com/KRIEZIEYR/omarchy-xray omarchy-xray
cd omarchy-xray
./install.sh            # add --tun to also run the one-time TUN setup
```

The script puts `omarchy-xray` into `~/.local/bin`, writes the systemd user
units, asks for your subscription URL (hidden input, passed via environment
so it never appears in `ps` output), optionally sets up TUN (default: no),
verifies the tunnel and enables the widget. Flags: `--yes`, `--no-deps`, `--tun`.

Remove: `./uninstall.sh` (also offers to remove the manager, the TUN setup and the config).

## Daily use

```bash
export OMARCHY_XRAY_SUB_URL=<url>; omarchy-xray import -   # add a subscription (also: pipe URL on stdin)
omarchy-xray status                 # JSON state (what the widget reads; URLs redacted)
omarchy-xray select Finland         # switch by name substring, key (k…), n<index> or "auto"
omarchy-xray on | off | restart
omarchy-xray mode proxy|tun
omarchy-xray routing global|<region>-direct   # e.g. kz-direct
omarchy-xray adblock on|off
omarchy-xray update [index]         # refresh all subscriptions or one
omarchy-xray test [key…]            # latency (first 200 nodes or the given keys, 10 min cap)
omarchy-xray stats                  # traffic totals + speed
omarchy-xray logs [n]               # journal of the active service
omarchy-xray doctor                 # environment checks
```

Proxies: socks5 `127.0.0.1:20170`, HTTP `127.0.0.1:20171`. Private networks
always bypass the tunnel.

In **proxy mode** the manager also sets the GNOME/GTK system proxy and the
session environment (`http_proxy`, `https_proxy`, `all_proxy`, `no_proxy` via
`systemctl --user set-environment`), so apps launched afterwards — Omarchy
starts them through uwsm — use the proxy automatically. Switching to TUN or
turning the tunnel off clears both.

## TUN mode

TUN routes all system traffic (TCP, UDP) through Xray. **Xray never gets a
capability**: root only creates the device and the routes, everything that
touches your traffic runs as your user.

```
apps ─▶ routes ─▶ xray0 ─▶ tun2socks (you) ─▶ 127.0.0.1:20170 ─▶ xray (you) ─▶ physical link ─▶ server
```

**What `omarchy-xray tun-setup` does** — once, through one polkit (pkexec)
prompt, or `sudo omarchy-xray tun-install` from a terminal:

| File (root:root 0644) | Purpose |
|---|---|
| `/etc/systemd/system/omarchy-xray-tun.service` | root **oneshot** that runs only `ip`, `udevadm` and `resolvectl` with fixed arguments: creates `xray0` owned by your uid (`ip tuntap add … user <uid>`), `198.18.0.1/30` (+ a ULA /126), routes (below) and resolved DNS for `xray0`; stopping it deletes the device and its rules. `CapabilityBoundingSet=CAP_NET_ADMIN`, `NoNewPrivileges`, `ProtectSystem=strict`, `ProtectHome` and more |
| `/etc/polkit-1/rules.d/49-omarchy-xray.rules` | lets **only your user** `start`/`stop`/`restart` **only that unit** without a password |
| `/etc/systemd/network/10-omarchy-xray.network` | only if systemd-networkd is active: keeps networkd away from `xray0` |

The setup reads nothing but your uid (from `PKEXEC_UID`/`SUDO_UID`) and
writes its files all-or-nothing (a failed write restores the previous ones).
No third-party binary ever runs as root or with capabilities, so there is
nothing to pin or re-attest after an xray or tun2socks update. This script is
never run as root again. No setcap, no sudoers. Undo with
`omarchy-xray tun-remove`.

The user unit `omarchy-xray-tun2socks.service` starts the root unit, runs
`omarchy-xray tun-run` (tun2socks on `xray0` → xray's socks port) and stops the
root unit when it stops, so the device lives exactly as long as TUN mode.

**How routing works.** The default route into `xray0` lives in its own table
(`18180`), selected by three `ip rule`s (prefs 18180–18182; IPv6 has two):
`main` first but without its default route (LAN stays local), then lookups
with no source address yet or from `198.18.0.1` go to the tunnel. Xray binds
every connection it makes to the physical interface (`sockopt.interface`,
unprivileged `SO_BINDTODEVICE`, Linux ≥ 5.7), so it never loops back into
`xray0`; its replies are looked up from the physical address and pass a strict
`rp_filter` (ufw sets `rp_filter=1`). `tun-run` follows default-route changes
(Wi-Fi ↔ Ethernet) and rebinds xray within ~5 s. If tun2socks stops, its unit
stops the root unit and the normal network takes over.

DNS: systemd-resolved sends everything to `198.18.0.2` on `xray0`; Xray
answers it with a `dns` outbound. Queries go over DoH (`1.1.1.1`) through the
proxy; the server hostnames themselves are resolved by bootstrap servers
(the link's DHCP DNS + `1.1.1.1`, sent direct) so the tunnel never waits on
itself. Override with `bootstrapDns` / `dns` in `custom.json`.

Manual check after `tun-setup` and `omarchy-xray mode tun && omarchy-xray on`:

```bash
omarchy-xray doctor
ip addr show xray0                 # 198.18.0.1/30
ip rule | grep 1818                # the three rules
ip route show table 18180          # default dev xray0
resolvectl status xray0            # DNS Servers: 198.18.0.2, DNS Domain: ~.
curl -s https://ifconfig.me        # the server's IP
```

## Routing presets and Auto

- **Global** — everything except private networks through the proxy.
- **Direct: region** — pick one country with heavy censorship (panel: ROUTE → `BYPASS`, country chip next to it; `ALL` sends everything through the VPN):
  its ccTLDs and `geoip:<code>` go direct, plus a geosite list where one exists
  (RU: `.ru/.su/.рф` + `geosite:category-ru`, CN: `geosite:cn`, IR:
  `geosite:category-ir`). Regions: RU BY KZ UZ TM CN IR TR AE SA EG PK VN MM.
  Without geo data only the ccTLDs apply.
- **Adblock** — `geosite:category-ads-all` → blackhole (needs geo data).
- **Auto** (first row in the node list) — up to 32 nodes (best tested latency
  first) behind a `leastPing` balancer fed by Xray's observatory
  (`generate_204` every minute). The bar shows `Auto → <current pick>`.

## custom.json

`~/.config/omarchy-xray/custom.json` is merged into every generated config,
and the result is validated by `xray run -test` — an invalid combination is
refused with the core's error (the running config stays untouched).

| Key | Merge |
|---|---|
| `routing.rules` | inserted before the preset rules |
| `routing.balancers` | appended; other `routing` keys override |
| `dns.servers` | prepended; other `dns` keys override |
| `outbounds`, `inbounds` | appended (reserved tags: `proxy`, `direct`, `block`, `dns-out`, `tun-in`, `socks-in`, `http-in`, `auto`, `node-*`) |
| `proxyPatch` | deep-merged into the proxy outbound(s) (mux, sockopt, …) |
| `bootstrapDns` | list of IPs that resolve the server hostnames in TUN mode |
| anything else | deep-merged at the top level (`log`, `policy`, …); keys starting with `_` are ignored |

Example — fragment the TLS ClientHello, send a domain direct, enable mux:

```json
{
  "_comment": "merged by omarchy-xray",
  "outbounds": [
    { "tag": "fragment", "protocol": "freedom",
      "settings": { "fragment": { "packets": "tlshello", "length": "100-200", "interval": "10-20" } } }
  ],
  "proxyPatch": {
    "streamSettings": { "sockopt": { "dialerProxy": "fragment" } },
    "mux": { "enabled": true, "concurrency": 8 }
  },
  "routing": { "rules": [ { "domain": ["domain:example.org"], "outboundTag": "direct" } ] }
}
```

Run `omarchy-xray restart` after editing.

## Security notes (marketplace review)

- Xray and tun2socks never run as root or with a capability, in either mode.
  TUN mode is opt-in; its one-time setup is the only privileged step and
  installs the three files above — root afterwards runs only `ip`, `udevadm`
  and `resolvectl` with fixed arguments; the polkit rule is scoped to one
  user, one unit and three verbs. No setcap, no sudoers.
- The manager refuses to run as root except for `tun-install`/`tun-uninstall`,
  uses `#!/usr/bin/python3 -I`, calls tools by absolute path and gives child
  processes an explicit environment allowlist. The widget starts processes
  with a cleared environment plus an allowlist.
- Subscription downloads: HTTPS-only (redirects re-checked, final URL must be
  HTTPS), 2 MiB streaming cap, strict per-protocol link validation with
  count/string bounds (2000 nodes, 5000 lines), malformed links skipped.
- Secrets: `~/.config/omarchy-xray/` is `0700`, `state.json`/`config.json`
  are atomic `0600` no-follow writes; `import -` reads the URL from
  `$OMARCHY_XRAY_SUB_URL`/stdin; a URL in argv is refused (argv is world-readable)
  (status/errors show `host/***` only). Temporary test configs live in
  `$XDG_RUNTIME_DIR/omarchy-xray` (`0700`).
- Loopback-only listeners: socks 20170, http 20171, metrics 15491.
- Widget: per-slot hard deadlines with SIGKILL + env wipe, 512 KiB stdout cap
  with tolerant JSON extraction, node array capped at 1000 for rendering,
  bounded input, credential-shaped strings scrubbed before display.

## Widget settings

| Setting | Default | Description |
|---|---|---|
| Refresh interval | `20` s | Closed-panel poll; open panel polls every 2 s. |
| Bar label | `speed` | `icon` — shield only; `node` — current node name; `speed` — live download speed. |

## Scripting

`omarchy-shell krieziey.omarchy-xray VERB`:

| Verb | Effect |
|---|---|
| `toggle` / `open` / `close` | Panel |
| `status` | One-line summary (current node) |
| `connect` / `toggleProxy` | Connect to last/first node, disconnect if connected |
| `disconnect` | Stop the tunnel |
| `select <name>` | Switch to the first node whose name matches |
| `test` | Latency-test nodes (bounded) |
| `updateSubs` | Re-fetch the subscriptions |
| `startCore` / `stopCore` | `omarchy-xray on` / `off` |
| `subRemove <index>` | Remove a subscription |
| `mode <proxy\|tun>` | Switch mode (TUN runs the one-time setup first if needed) |
| `routing <global\|<region>-direct>` | Routing preset (`ru-direct`, `kz-direct`, …) |
| `adblock <on\|off>` | Ad blocking |
| `tunSetup` | Run the one-time TUN setup |
| `webui` | Open the omarchy-xray config folder |

```ini
bind = $mainMod SHIFT, V, exec, omarchy-shell krieziey.omarchy-xray toggleProxy
bind = $mainMod SHIFT, C, exec, omarchy-shell krieziey.omarchy-xray toggle
bind = $mainMod SHIFT, T, exec, omarchy-shell krieziey.omarchy-xray select JP
```

## Troubleshooting

- `omarchy-xray doctor` — core version and ownership, geo data, `/dev/net/tun`,
  kernel, tun2socks, TUN files, polkit agent, resolved/networkd, v2 leftovers, service state.
- `omarchy-xray logs` — the journal of the active unit (the panel also shows
  the last error line when the service failed).
- "N nodes skipped (…)" under the mode switch tells you why links were not
  imported (removed transport, unsupported method, rejected by the core…).

## Development

```bash
node tests/run.js                                   # widget model
python3 -m unittest discover -s tests/manager       # manager (links, config, TUN files)
OMARCHY_XRAY_TEST_BIN=/path/to/xray python3 -m unittest discover -s tests/manager
                                                    # …plus `xray run -test` on every generated config
python3 -m py_compile bin/omarchy-xray
omarchy plugin validate .
./install.sh --no-deps --yes   # re-copy; restarts the shell (live rescan keeps old QML)
```

Manager internals: state in `~/.config/omarchy-xray/state.json` (subscriptions
with their info, nodes with stable ids and their prepared outbound, selection,
mode, presets — 0600), generated core config in `config.json` (0600), latency
cache in `latency.json` keyed by node id.

## License

MIT.
