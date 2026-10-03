# Product

<!-- impeccable:product-schema 1 -->

## Platform

desktop: a Qt Quick (QML) bar widget and panel inside the Omarchy shell on Hyprland. Not a web page; browser-only tooling (live, generate, detect) does not apply.

## Users

Two groups, one panel:

- Omarchy users in countries with internet censorship (Russia and the regions in the routing presets) who have a subscription from a VPN provider. Their job: get past blocking without touching a terminal.
- Experienced Linux users on Omarchy/Hyprland who know Xray and want fast, keyboard-first control from the bar.

The panel must stay usable for the first group and fast for the second.

## Product Purpose

Runs an Xray subscription in the background and gives a remote control in the Omarchy bar. The controls cover connect/disconnect, node switching or Auto (best ping), proxy or TUN mode, routing presets, latency tests, subscription updates and live traffic. Success: the user connects in one click or one key and always knows whether traffic is protected.

## Positioning

Native to Omarchy. It is a bar widget installed with `omarchy plugin add`, not a separate app or web UI like v2rayA, Nekoray or Hiddify. It is keyboard-first and follows Omarchy's own conventions.

## Operating Context

- Opened from the bar shield: click opens the panel, right-click toggles, middle-click refreshes. Hyprland binds call IPC verbs.
- The shield is filled in TUN mode, half-filled in proxy mode, an outline when off.
- The panel drives `bin/omarchy-xray`, which returns JSON; live traffic comes from xray metrics on loopback.
- First run asks for a subscription URL. The same field also accepts share links or Xray JSON, which go to a Manual group.

## Capabilities and Constraints

- Protocols: VLESS, VMess, Trojan, Shadowsocks (including 2022), Hysteria2, and Xray-JSON subscriptions. Every transport of the current Xray core.
- Modes: proxy (no privileges) and TUN (one-time setup through polkit/sudo).
- Security constraints are binding (marketplace review, capabilities `service-management` and `privilege`): xray never gets a capability; secrets never go in argv; state files are `0600`; the root TUN unit is started and stopped only through its ownership check.
- Interface language: English only.

## Evidence on Hand

- Listed on the Omarchy plugin marketplace (omacom/omarchy-plugin-marketplace), validated commit `b702b2d`, maintainer-reviewed 2026-10-01.
- Screenshot: `preview.png` on main.
- No testimonials, user counts or benchmarks exist. Do not invent them.

## Product Principles

1. Protection state is never ambiguous: on, off, proxy-only, blocked.
2. Keyboard and mouse are equal; typing never triggers a command.
3. Security before convenience: no shortcut that weakens the review model.
4. Native to Omarchy: no separate windows, daemons or web UIs.
