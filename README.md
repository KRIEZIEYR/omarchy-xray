# Xray for Omarchy

An [Omarchy](https://omarchy.org) shell widget that runs your Xray
subscription in the background and gives you a remote control in the bar:
connect/disconnect, node switching, latency tests, subscription updates.

```
Panel.qml ──▶ omarchy-xray (manager, ~/.local/bin) ──▶ systemd --user omarchy-xray.service
                                                          └── /usr/bin/xray (your nodes)
```

No daemon accounts, no passwords, no REST — the widget just runs
`omarchy-xray` commands and reads JSON back.

**Why not v2rayA anymore?** v1 of this widget drove a local v2rayA daemon,
but v2rayA (≤ 2.4.15) does not support the new **VLESS `encryption`**
parameter (mlkem768 post-quantum): its link parser drops the field and its
core sends `encryption: none`, which servers with encryption enabled reject.
If your subscription uses VLESS Encryption, v2rayA cannot work with it —
so the widget now drives `/usr/bin/xray` directly through a tiny manager.

## Features

- connect / disconnect with one click or the hero toggle
- every node from the subscription, filter as you type
- switch nodes instantly (config regen + service restart, ~1 s)
- live traffic counters and speeds (xray StatsService, loopback-only API)
- latency tests (right-click a node = single; `t` = all, through per-node temp xray)
- subscription update without leaving the panel
- keyboard-first: `j/k` move, `Enter` connect, `t` test, `u` update, `c` toggle, `w` config folder
- IPC verbs for Hyprland binds

## Requirements

- Omarchy Quattro (shell plugins)
- Xray core — AUR package `xray` (not in the official repos)
- `python3`, `curl` (already part of Omarchy)

## Install

```bash
git clone <this repo> omarchy-v2raya
cd omarchy-v2raya
./install.sh
```

The script installs `xray` (AUR) if needed, puts `omarchy-xray` into
`~/.local/bin`, writes the systemd user unit, asks for your subscription
URL, verifies the tunnel and enables the widget. Flags: `--yes`, `--no-deps`.

Remove:

```bash
./uninstall.sh
```

## Daily use

```bash
omarchy-xray import <subscription-url>   # set/replace subscription
omarchy-xray status                      # JSON state (what the widget reads)
omarchy-xray select Finland              # switch by name substring or key (n3)
omarchy-xray on | off | restart
omarchy-xray test                        # latency for every node
```

Proxies: socks5 `127.0.0.1:20170`, HTTP `127.0.0.1:20171`.
Private networks (RFC1918, loopback) always bypass the tunnel.

In **proxy mode** the manager also flips the GNOME/GTK system proxy to
127.0.0.1 (http 20171 / socks 20170) while the service runs, so proxy-aware
apps are covered automatically; switching to TUN or turning the VPN off clears it.

Traffic counters: `omarchy-xray stats` (totals + per-call speed via xray's
StatsService on 127.0.0.1:15490, loopback-only).

The service is a **systemd user unit** (`omarchy-xray.service`): it starts on
login, survives widget reloads and terminal closes.

## Widget settings

| Setting | Default | Description |
|---|---|---|
| Refresh interval | `20` s | Closed-panel poll; open panel polls every 2 s. |
| Bar label | `speed` | `icon` — shield only; `node` — current node name; `speed` — live download speed (polls stats every 2 s). |

Credentials/API settings from v1 are gone — there is nothing to authenticate to.

## Scripting

`omarchy-shell krieziey.omarchy-xray VERB`:

| Verb | Effect |
|---|---|
| `toggle` / `open` / `close` | Panel |
| `status` | One-line summary (current node) |
| `connect` / `toggleProxy` | Connect to last/first node, disconnect if connected |
| `disconnect` | Stop the service |
| `select <name>` | Switch to first node whose name matches |
| `test` | Latency-test all nodes |
| `updateSubs` | Re-fetch the subscription |
| `startCore` / `stopCore` | `omarchy-xray on` / `off` |
| `importUrl <url>` | Set subscription URL and fetch |
| `webui` | Open the omarchy-xray config folder |

```ini
bind = $mainMod SHIFT, V, exec, omarchy-shell krieziey.omarchy-xray toggleProxy
bind = $mainMod SHIFT, C, exec, omarchy-shell krieziey.omarchy-xray toggle
bind = $mainMod SHIFT, T, exec, omarchy-shell krieziey.omarchy-xray select JP
```

## Development

```bash
node tests/run.js        # model assertions (53)
omarchy plugin validate .
./install.sh --no-deps --yes   # re-copy; the shell hot-reloads plugin code
```

Manager internals: state in `~/.config/omarchy-xray/state.json` (URL, nodes,
selected), generated core config in `config.json`, latency cache in
`latency.json`. Node switching rewrites only the `proxy` outbound tag and
restarts the service.

## Notes

- TUN/transparent mode is out of scope: apps use the socks/http inbounds or
  your own per-app proxy settings. (v2rayA-style transparent redirect can be
  added later via iptables, but it needs root and careful loopback rules.)
- If your provider rotates keys — just `omarchy-xray update` (or `u` in the panel).

## License

MIT.
