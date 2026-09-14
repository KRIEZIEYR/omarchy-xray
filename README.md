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
- latency tests (`t` = up to 200 nodes, 10 min cap, through per-node temp xray)
- subscription update without leaving the panel
- keyboard-first: `j/k` move, `Enter` connect, `t` test, `u` update, `c` toggle, `w` config folder
- IPC verbs for Hyprland binds

## Requirements

- Omarchy Quattro (shell plugins)
- Xray core — install yourself from a source you trust (e.g. review the AUR
  package, then `omarchy pkg aur add xray`). The installer never installs it
  for you and never grants capabilities to any binary.
- `python3`, `curl` (already part of Omarchy)

## Install

```bash
git clone https://github.com/KRIEZIEYR/omarchy-xray omarchy-xray
cd omarchy-xray
./install.sh
```

The script puts `omarchy-xray` into `~/.local/bin`, writes the systemd user
unit, asks for your subscription URL (hidden input, passed via environment so
it never appears in `ps` output), verifies the tunnel and enables the widget.
Flags: `--yes`, `--no-deps`.

Remove:

```bash
./uninstall.sh
```

## Daily use

```bash
export OMARCHY_XRAY_SUB_URL=<url>; omarchy-xray import -   # set/replace (also: pipe URL on stdin)
omarchy-xray status                      # JSON state (what the widget reads; URLs redacted)
omarchy-xray select Finland              # switch by name substring or key (n3)
omarchy-xray on | off | restart
omarchy-xray test                        # latency for nodes (first 200, 10 min cap)
```

Plain `import <url>` on argv still works interactively, but the env/stdin
form is preferred — tokens in argv are visible to every local process via
`ps`, and the manager never echoes a URL back (status shows hosts only,
redacted as `scheme://host/***`).

Proxies: socks5 `127.0.0.1:20170`, HTTP `127.0.0.1:20171`.
Private networks (RFC1918, loopback) always bypass the tunnel.

In **proxy mode** the manager also flips the GNOME/GTK system proxy to
127.0.0.1 (http 20171 / socks 20170) while the service runs, so proxy-aware
apps are covered automatically; switching to TUN or turning the VPN off clears it.

Traffic counters: `omarchy-xray stats` (totals + per-call speed via xray's
StatsService on 127.0.0.1:15490, loopback-only).

The service is a **systemd user unit** (`omarchy-xray.service`): it starts on
login, survives widget reloads and terminal closes. The unit sets
`NoNewPrivileges=true` and `PrivateTmp=true`.

## TUN mode (experimental)

Proxy mode needs no privileges. TUN mode needs exactly one privileged setup
step, done explicitly — never by the installer:

- switch modes in the panel (confirm the polkit prompt), or
- manually: `sudo omarchy-xray route-up` (undo: `sudo omarchy-xray route-down`)

What it does: creates the user-owned `xray0` device, addresses it, adds
host bypass routes for the subscription servers and policy rules on dedicated
priorities (table 518, rules 5190/5199) recorded in `/run/omarchy-xray/routes.json`.
`route-down` removes exactly what the marker recorded; without a marker only
the dedicated table is flushed and a foreign `xray0` is never touched.
Rollback on failure, route preflight, and DNS-independent apply (node IPs are
resolved user-side before escalation) are built in.

## Security notes (marketplace review)

- No `setcap` anywhere: the xray binary runs with exactly the privileges your
  package manager gave it. Verify provenance yourself (`pacman -Qo $(command -v xray)`).
- Subscription downloads: HTTPS-only (redirects re-checked, final URL must be
  HTTPS), 2 MiB streaming cap, strict `vless://` schema validation with
  count/string bounds (2000 nodes, 5000 lines), malformed links skipped.
- Secrets: `~/.config/omarchy-xray/` is `0700`, `state.json`/`config.json`
  are atomic `0600` no-follow writes; `import -` reads the URL from
  `$OMARCHY_XRAY_SUB_URL`/stdin; argv URLs accepted but never echoed
  (status/errors show `host/***` only, `subremove` matches by host/index).
- Widget/QML: per-slot hard deadlines (status 30 s, stats 20 s, long ops
  up to 11 min) with SIGKILL + env wipe, 512 KiB stdout cap with tolerant
  JSON extraction, node array capped at 1000 for rendering, input lengths
  bounded, credential-shaped strings scrubbed before display.

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
| `test` | Latency-test nodes (bounded) |
| `updateSubs` | Re-fetch the subscription |
| `startCore` / `stopCore` | `omarchy-xray on` / `off` |
| `importUrl <url>` | Set subscription URL (https-only) and fetch |
| `mode <proxy\|tun>` | Switch mode (TUN needs the privileged step) |
| `webui` | Open the omarchy-xray config folder |

```ini
bind = $mainMod SHIFT, V, exec, omarchy-shell krieziey.omarchy-xray toggleProxy
bind = $mainMod SHIFT, C, exec, omarchy-shell krieziey.omarchy-xray toggle
bind = $mainMod SHIFT, T, exec, omarchy-shell krieziey.omarchy-xray select JP
```

## Development

```bash
node tests/run.js        # model assertions (60)
python3 -m py_compile bin/omarchy-xray
omarchy plugin validate .
./install.sh --no-deps --yes   # re-copy; the shell hot-reloads plugin code
```

Manager internals: state in `~/.config/omarchy-xray/state.json` (subs, nodes,
selected — 0600), generated core config in `config.json` (0600), latency cache
in `latency.json`. Node switching rewrites only the `proxy` outbound tag and
restarts the service.

## Notes

- If your provider rotates keys — just `omarchy-xray update` (or `u` in the panel).
- `route-up`/`route-down` refuse to run as non-root and refuse foreign devices;
  IPv6 TUN rules are best-effort, IPv4 is the supported path.

## License

MIT.
