# Xray for Omarchy

An [Omarchy](https://omarchy.org) shell widget that runs your Xray
subscription in the background and gives you a remote control in the bar:
connect/disconnect, node switching (or **Auto** — best ping), proxy or
**TUN** mode, routing presets, latency tests, subscription updates and live
traffic.

```
Panel.qml ──▶ omarchy-xray (manager, ~/.local/bin)
                 ├─ proxy mode ─▶ systemd --user  omarchy-xray.service      ─┐
                 └─ TUN mode   ─▶ systemd system  omarchy-xray-tun.service  ─┴─▶ /usr/bin/xray
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
- routing presets: **Global** / **RU direct**, optional **Adblock**
- `custom.json` for anything else the core can do (rules, DNS, mux, fragment…)
- subscription info: traffic used/total and expiry (`subscription-userinfo`),
  `profile-title`, automatic refresh (`profile-update-interval`, default 24 h)
- latency tests: batched and parallel, one xray process per 32 nodes
- live traffic counters and speeds from xray's metrics endpoint (loopback)
- keyboard-first: `j/k` move, `Enter` connect, `t` test, `u` update, `c` toggle, `w` config folder
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
- Xray core **≥ 26.6.1** (TUN mode needs ≥ 26.4.13; tested with 26.6.1 and
  26.9.9) — install it yourself from a source you trust (e.g. review the AUR
  package, then `omarchy pkg aur add xray`). The installer never installs it
  for you and never grants capabilities to any binary. Older cores still work
  for most nodes; whatever they reject is skipped with a reason, and
  `omarchy-xray doctor` warns about the version.
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
omarchy-xray routing global|ru-direct
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

TUN routes all system traffic (TCP, UDP, ICMP echo) through Xray.

**Why it needs a setup step.** Xray creates and configures its TUN device
itself (netlink: MTU, link up, addresses, routes), which needs
`CAP_NET_ADMIN`. A `systemd --user` service cannot receive that capability
(`AmbientCapabilities=` in a user unit has no effect, and `NoNewPrivileges`
disables file capabilities), which is why TUN mode in v2 never came up.

**What `omarchy-xray tun-setup` does** — once, through one polkit (pkexec)
prompt, or `sudo omarchy-xray tun-install` from a terminal:

| File (root:root 0644) | Purpose |
|---|---|
| `/etc/systemd/system/omarchy-xray-tun.service` | runs `/usr/bin/xray run -c ~/.config/omarchy-xray/config.json` **as your user** with `AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE`, `NoNewPrivileges`, `ProtectSystem=strict`, `ProtectHome=read-only`, `PrivateTmp` and more; `ExecStartPost=+` runs `udevadm wait` and `resolvectl` (DNS of `xray0` → through the tunnel) with fixed arguments |
| `/etc/polkit-1/rules.d/49-omarchy-xray.rules` | lets **only your user** `start`/`stop`/`restart` **only that unit** without a password |
| `/etc/systemd/network/10-omarchy-xray.network` | only if systemd-networkd is active: keeps networkd away from `xray0` |

The setup reads nothing but your uid (from `PKEXEC_UID`/`SUDO_UID`), refuses
an xray binary that is not root-owned or is group/world-writable, and removes
v2 leftovers (ip rules 5190/5199, table 518, a persistent `xray0`). After it,
root only ever executes root-owned system binaries (`xray` as your user,
`udevadm`, `resolvectl`); this script is never run as root again. No setcap,
no sudoers. Undo with `omarchy-xray tun-remove`.

**How routing works.** The TUN inbound uses Xray's own `gateway`
(`198.18.0.1/30`, plus a ULA /126 when the host has IPv6),
`autoSystemRoutingTable` (default routes via `xray0`, IPv6 only when the host
has a v6 default route) and `autoOutboundsInterface: "auto"`: every socket
Xray opens is bound to the physical interface and follows default-route
changes (Wi-Fi ↔ Ethernet), so there are no routing loops for the proxy or
for `direct`. The device is not persistent: if xray dies, `xray0` and its
routes disappear and the normal network takes over.

DNS: systemd-resolved sends everything to `198.18.0.2` on `xray0`; Xray
answers it with a `dns` outbound. Queries go over DoH (`1.1.1.1`) through the
proxy; the server hostnames themselves are resolved by bootstrap servers
(the link's DHCP DNS + `1.1.1.1`, sent direct) so the tunnel never waits on
itself. Override with `bootstrapDns` / `dns` in `custom.json`.

Manual check after `tun-setup` and `omarchy-xray mode tun && omarchy-xray on`:

```bash
omarchy-xray doctor
ip addr show xray0                 # 198.18.0.1/30
ip route | grep xray0              # default dev xray0 metric 1
resolvectl status xray0            # DNS Servers: 198.18.0.2, DNS Domain: ~.
curl -s https://ifconfig.me        # the server's IP
```

## Routing presets and Auto

- **Global** — everything except private networks through the proxy.
- **RU direct** — `.ru`, `.su`, `.рф` (and `geosite:category-ru` +
  `geoip:ru` when geo data is installed) go direct.
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

- Proxy mode ships no privileged component. TUN mode is opt-in; its one-time
  setup is the only privileged step and installs the three files above —
  root afterwards runs only root-owned system binaries; the polkit rule is
  scoped to one user, one unit and three verbs. No setcap, no sudoers.
- The manager refuses to run as root except for `tun-install`/`tun-uninstall`,
  uses `#!/usr/bin/python3 -I`, calls tools by absolute path and gives child
  processes an explicit environment allowlist. The widget starts processes
  with a cleared environment plus an allowlist.
- Subscription downloads: HTTPS-only (redirects re-checked, final URL must be
  HTTPS), 2 MiB streaming cap, strict per-protocol link validation with
  count/string bounds (2000 nodes, 5000 lines), malformed links skipped.
- Secrets: `~/.config/omarchy-xray/` is `0700`, `state.json`/`config.json`
  are atomic `0600` no-follow writes; `import -` reads the URL from
  `$OMARCHY_XRAY_SUB_URL`/stdin; argv URLs accepted but never echoed
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
| `importUrl <url>` | Add a subscription (https-only) and fetch |
| `subRemove <index>` | Remove a subscription |
| `mode <proxy\|tun>` | Switch mode (TUN runs the one-time setup first if needed) |
| `routing <global\|ru-direct>` | Routing preset |
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
  kernel, TUN files, polkit agent, resolved/networkd, v2 leftovers, service state.
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
./install.sh --no-deps --yes   # re-copy; the shell hot-reloads plugin code
```

Manager internals: state in `~/.config/omarchy-xray/state.json` (subscriptions
with their info, nodes with stable ids and their prepared outbound, selection,
mode, presets — 0600), generated core config in `config.json` (0600), latency
cache in `latency.json` keyed by node id.

## License

MIT.
