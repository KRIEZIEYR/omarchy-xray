#!/usr/bin/env bash
#
# Removes the krieziey.omarchy-xray Omarchy shell widget.
# Does not touch v2rayA itself, its data, or the systemd service.
#
# Usage:
#   ./uninstall.sh [--yes]
#
set -euo pipefail

PLUGIN_ID="krieziey.omarchy-xray"
DEST="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/${PLUGIN_ID}"

ASSUME_YES=0
[[ "${1:-}" == "--yes" || "${1:-}" == "-y" ]] && ASSUME_YES=1

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }

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
  read -r -p "Also remove the omarchy-xray manager, user service and config? [y/N] " a2 </dev/tty || a2=""
  if [[ "$a2" =~ ^[Yy] ]]; then
    systemctl --user disable --now omarchy-xray.service 2>/dev/null || true
    rm -f "$HOME/.local/bin/omarchy-xray" "$HOME/.config/systemd/user/omarchy-xray.service"
    rm -rf "$HOME/.config/systemd/user/omarchy-xray.service.d"
    # legacy names
    for LEGACY in xraya xraya-lite; do
      systemctl --user disable --now "$LEGACY.service" 2>/dev/null || true
      rm -f "$HOME/.local/bin/$LEGACY" "$HOME/.config/systemd/user/$LEGACY.service"
      rm -rf "$HOME/.config/systemd/user/$LEGACY.service.d"
      rm -rf "${XDG_CONFIG_HOME:-$HOME/.config}/$LEGACY"
    done
    systemctl --user daemon-reload
    rm -rf "${XDG_CONFIG_HOME:-$HOME/.config}/omarchy-xray"
    echo "omarchy-xray removed (your subscription URL is gone too)."
  else
    echo "omarchy-xray left in place; the tunnel keeps working: omarchy-xray status"
  fi
fi

say "Removed ${PLUGIN_ID}"
