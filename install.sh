#!/usr/bin/env bash
#
# Installs the krieziey.omarchy-xray Omarchy shell widget (v2 — omarchy-xray backend):
#   1. checks prerequisites (omarchy, curl, python3)
#   2. installs the xray core (AUR: xray) if missing
#   3. installs the omarchy-xray manager to ~/.local/bin + systemd user unit
#   4. asks for the subscription URL (or reuses an existing omarchy-xray config)
#   5. copies the plugin into ~/.config/omarchy/plugins/ and enables it
#
# v2rayA is NOT required anymore: its panel (<=2.4.15) cannot pass the new
# VLESS `encryption` parameter, so the widget drives xray directly instead.
#
# Usage:
#   ./install.sh                 # interactive
#   ./install.sh --yes           # assume defaults everywhere
#   ./install.sh --no-deps       # skip package checks entirely
#
set -euo pipefail

PLUGIN_ID="krieziey.omarchy-xray"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/${PLUGIN_ID}"
BIN_DIR="${HOME}/.local/bin"
STATE="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy-xray/state.json"

# Safety rail: this script must only ever write the exact plugin directory.
EXPECTED_DEST="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/${PLUGIN_ID}"
[[ "$DEST" == "$EXPECTED_DEST" ]] || die "internal error: unexpected DEST '$DEST'"
case "$DEST" in
  "$HOME"/.config/omarchy/plugins/*) ;;
  *) die "refusing unsafe destination: $DEST" ;;
esac

ASSUME_YES=0
NO_DEPS=0
for arg in "$@"; do
  case "$arg" in
    --yes) ASSUME_YES=1 ;;
    --no-deps) NO_DEPS=1 ;;
    -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

ask() {
  local question="$1" def="${2:-y}" answer
  if [[ $ASSUME_YES -eq 1 ]]; then
    echo "$question [${def}] → yes"
    [[ "$def" == "y" ]]
    return
  fi
  read -r -p "$question [Y/n] " answer </dev/tty || answer=""
  answer="${answer:-$def}"
  [[ ! "$answer" =~ ^[Nn] ]]
}

say()  { printf '\033[1m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

command -v omarchy  >/dev/null 2>&1 || die "omarchy CLI not found — this installer targets Omarchy Linux"
command -v curl     >/dev/null 2>&1 || die "curl is required"
command -v python3  >/dev/null 2>&1 || die "python3 is required (omarchy-xray manager)"

say "Installing ${PLUGIN_ID} (omarchy-xray backend)"

if [[ $NO_DEPS -eq 0 ]]; then
  # --- Xray core (AUR; not in the official repos) ---------------------------
  if command -v xray &>/dev/null; then
    say "Xray core found: $(xray version 2>/dev/null | head -1)"
  else
    warn "No Xray core found."
    if ask "Install xray from the AUR now?"; then
      omarchy pkg aur add xray || die "failed to install xray from the AUR"
    else
      die "xray is required — install it later with: omarchy pkg aur add xray"
    fi
  fi

  # --- retire v2raya if present ---------------------------------------------
  if systemctl list-unit-files v2raya.service &>/dev/null && systemctl is-enabled v2raya.service &>/dev/null; then
    if ask "v2raya system service is enabled. Disable it? (the widget no longer uses v2rayA)"; then
      sudo systemctl disable --now v2raya.service || warn "could not disable v2raya.service"
    fi
  fi
fi

# --- TUN support: cap_net_admin on the xray binary (best-effort) ---------------
# xray's tun inbounds need CAP_NET_ADMIN to create the TUN device; without it
# TUN mode fails on a fresh machine. Proxy-only usage never needs this, so a
# failure here only disables TUN mode and is never fatal.
if command -v xray &>/dev/null && command -v setcap &>/dev/null; then
  XRAY_BIN="$(command -v xray)"
  if sudo -n setcap cap_net_admin,cap_net_bind_service=+ep "$XRAY_BIN" 2>/dev/null \
     || sudo setcap cap_net_admin,cap_net_bind_service=+ep "$XRAY_BIN" 2>/dev/null; then
    say "TUN capability granted to $XRAY_BIN"
  else
    warn "could not set cap_net_admin on $XRAY_BIN — TUN mode unavailable (proxy mode works)"
  fi
fi

# --- 
# v2.5 used "xraya"; v2.3 and earlier used "xraya-lite".
NEW_CFG="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy-xray"
for LEGACY in xraya-lite xraya; do
  LEGACY_UNIT="$HOME/.config/systemd/user/${LEGACY}.service"
  if [[ -e "$LEGACY_UNIT" || -x "$BIN_DIR/$LEGACY" ]]; then
    systemctl --user disable --now "$LEGACY.service" 2>/dev/null || true
    rm -f "$BIN_DIR/$LEGACY" "$LEGACY_UNIT"
    rm -rf "$LEGACY_UNIT.d"
    echo "removed legacy $LEGACY manager" >&2
  fi
  LEGACY_CFG="${XDG_CONFIG_HOME:-$HOME/.config}/$LEGACY"
  if [[ -d "$LEGACY_CFG" && ! -d "$NEW_CFG" ]]; then
    mv "$LEGACY_CFG" "$NEW_CFG"
    say "Migrated config to $NEW_CFG"
  fi
done
systemctl --user daemon-reload

# --- omarchy-xray manager -------------------------------------------------
mkdir -p "$BIN_DIR"
install -m 755 "$SRC/bin/omarchy-xray" "$BIN_DIR/omarchy-xray"
say "Manager installed to $BIN_DIR/omarchy-xray"
"$BIN_DIR/omarchy-xray" install-unit >/dev/null
say "Systemd user unit installed"

# --- subscription ---------------------------------------------------------------
if [[ -f "$STATE" ]] && python3 -c "import json,sys;json.load(open('$STATE'));sys.exit(0 if json.load(open('$STATE')).get('url') else 1)" 2>/dev/null; then
  say "Existing omarchy-xray configuration found — keeping it"
  "$BIN_DIR/omarchy-xray" update >/dev/null 2>&1 || warn "subscription refresh failed (offline?)"
elif [[ $NO_DEPS -eq 0 ]]; then
  echo
  read -r -p "Paste your subscription URL (Enter to skip): " SUBURL </dev/tty || SUBURL=""
  if [[ -n "${SUBURL// }" ]]; then
    "$BIN_DIR/omarchy-xray" import "$SUBURL" || die "failed to fetch the subscription"
  else
    warn "Skipped. Later run: omarchy-xray import <subscription-url>"
  fi
fi

# --- bring the tunnel up ----------------------------------------------------------
if [[ $NO_DEPS -eq 0 ]] && [[ -f "$STATE" ]]; then
  if ask "Start the Xray service now?"; then
    "$BIN_DIR/omarchy-xray" on || warn "failed to start; try: omarchy-xray on"
    sleep 1
    code="$(curl -s -o /dev/null -w '%{http_code}' --socks5-hostname 127.0.0.1:20170 --max-time 8 https://www.gstatic.com/generate_204 || true)"
    [[ "$code" == "204" || "$code" == "200" ]] \
      && say "Tunnel verified: HTTP $code through 127.0.0.1:20170" \
      || warn "Tunnel check failed (HTTP ${code:-none}). Try: omarchy-xray test"
  fi
fi

# --- copy plugin --------------------------------------------------------------------
mkdir -p "$(dirname "$DEST")"
if command -v rsync >/dev/null 2>&1; then
  mkdir -p "$DEST"
  rsync -a --delete --exclude '.git/' --exclude '.gitignore' "$SRC/" "$DEST/"
else
  rm -rf "$DEST"; cp -r "$SRC" "$DEST"; rm -rf "$DEST/.git"
fi
say "Plugin copied to $DEST"

# --- validate + enable -----------------------------------------------------------------
omarchy plugin validate "$DEST" || die "plugin validation failed"
say "Manifest validated"

if pgrep -x omarchy-shell >/dev/null 2>&1; then
  say "Rescanning plugins in the running shell"
  omarchy-shell shell rescanPlugins || warn "live rescan failed; restart the shell once"
fi

omarchy plugin enable "$PLUGIN_ID" right || die "failed to enable ${PLUGIN_ID}"
say "Widget enabled in the right bar section"

# --- retire the pre-rename plugin ids (krieziey.xray, krieziey.v2raya) ---------
for OLD_ID in krieziey.xray krieziey.v2raya; do
  OLD_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$OLD_ID"
  if [[ -d "$OLD_DIR" ]]; then
    omarchy plugin remove "$OLD_ID" --yes >/dev/null 2>&1 || rm -rf "$OLD_DIR"
    say "Removed old plugin id $OLD_ID"
  fi
done

cat <<EOF

Done. The widget talks to omarchy-xray (no accounts, no passwords):

  omarchy-xray import <url>   set the subscription
  omarchy-xray select <name>  switch node
  omarchy-xray on | off       start / stop the tunnel
  omarchy-xray test           latency-test all nodes

Scripting (Hyprland binds):
  bind = SUPER SHIFT, V, exec, omarchy-shell ${PLUGIN_ID} toggleProxy
  bind = SUPER SHIFT, C, exec, omarchy-shell ${PLUGIN_ID} toggle

Socks proxy: 127.0.0.1:20170   HTTP proxy: 127.0.0.1:20171
EOF
