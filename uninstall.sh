#!/usr/bin/env bash
#
# Removes the krieziey.omarchy-xray Omarchy shell widget and, on request,
# the omarchy-xray manager, its user units, the TUN setup and its config.
#
# Usage:
#   ./uninstall.sh [--yes]
#
set -euo pipefail

PLUGIN_ID="krieziey.omarchy-xray"
DEST="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/${PLUGIN_ID}"
MANAGER="$HOME/.local/bin/omarchy-xray"

ASSUME_YES=0
[[ "${1:-}" == "--yes" || "${1:-}" == "-y" ]] && ASSUME_YES=1

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }

[[ $EUID -ne 0 ]] || { echo "run as your user, not root" >&2; exit 1; }

if [[ $ASSUME_YES -eq 0 ]]; then
  read -r -p "Remove ${PLUGIN_ID} from the Omarchy shell? [Y/n] " answer </dev/tty || answer=""
  [[ "$answer" =~ ^[Nn] ]] && { echo "aborted"; exit 0; }
fi

command -v omarchy >/dev/null 2>&1 && omarchy plugin disable "$PLUGIN_ID" >/dev/null 2>&1 || true
omarchy plugin remove "$PLUGIN_ID" --yes >/dev/null 2>&1 || rm -rf "$DEST"
# pre-rename plugin ids
for OLD_ID in krieziey.xray krieziey.v2raya; do
  omarchy plugin remove "$OLD_ID" --yes >/dev/null 2>&1 \
    || rm -rf "${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$OLD_ID"
done

if [[ $ASSUME_YES -eq 0 ]]; then
  read -r -p "Also remove the omarchy-xray manager, units, TUN setup and config? [y/N] " a2 </dev/tty || a2=""
  if [[ "$a2" =~ ^[Yy] ]]; then
    if [[ -x "$MANAGER" ]]; then
      "$MANAGER" off >/dev/null 2>&1 || true
      if [[ -e /etc/systemd/system/omarchy-xray-tun.service || -e /etc/polkit-1/rules.d/49-omarchy-xray.rules ]]; then
        "$MANAGER" tun-remove >/dev/null || echo "TUN files left in /etc — remove with: sudo $MANAGER tun-uninstall" >&2
      fi
    fi
    for UNIT in omarchy-xray.service omarchy-xray-tun2socks.service omarchy-xray-tun-login.service xraya.service xraya-lite.service; do
      systemctl --user disable --now "$UNIT" 2>/dev/null || true
      rm -f "$HOME/.config/systemd/user/$UNIT"
      rm -rf "$HOME/.config/systemd/user/$UNIT.d"
    done
    systemctl --user unset-environment http_proxy https_proxy all_proxy no_proxy \
      HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY 2>/dev/null || true
    systemctl --user daemon-reload
    rm -f "$MANAGER" "$HOME/.local/bin/xraya" "$HOME/.local/bin/xraya-lite"
    rm -rf "$HOME/.config/omarchy-xray" "$HOME/.config/xraya" "$HOME/.config/xraya-lite"
    rm -rf "${XDG_RUNTIME_DIR:-/run/user/$UID}/omarchy-xray"
    echo "omarchy-xray removed (your subscription URL is gone too)."
  else
    echo "omarchy-xray left in place; the tunnel keeps working: omarchy-xray status"
  fi
fi

say "Removed ${PLUGIN_ID}"
