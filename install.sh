#!/usr/bin/env bash
#
# Installs the krieziey.omarchy-xray Omarchy shell widget (v3):
#   1. checks prerequisites (omarchy, python3, xray core)
#   2. installs the omarchy-xray manager to ~/.local/bin + systemd user units
#   3. asks for the subscription URL (or refreshes an existing config)
#   4. copies the plugin into ~/.config/omarchy/plugins/ and enables it
#   5. optionally (default: no) runs the one-time TUN setup
#
# The installer never escalates on its own and never grants capabilities:
#   - the xray core is NOT installed automatically (review the package first)
#   - no setcap, no sudoers; TUN mode is an explicit, opt-in polkit step that
#     installs a system unit + a polkit rule scoped to that one unit
#   - the subscription URL is passed via environment, never argv
#
# Usage:
#   ./install.sh                 # interactive
#   ./install.sh --yes           # assume defaults everywhere (TUN setup: no)
#   ./install.sh --no-deps       # skip package checks entirely
#   ./install.sh --tun           # also run the one-time TUN setup
#
set -euo pipefail

say()  { printf '\033[1m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

PLUGIN_ID="krieziey.omarchy-xray"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/${PLUGIN_ID}"
BIN_DIR="${HOME}/.local/bin"
MANAGER="$BIN_DIR/omarchy-xray"
# The manager always keeps its state in ~/.config/omarchy-xray.
STATE="$HOME/.config/omarchy-xray/state.json"

# Safety rail: this script must only ever write the exact plugin directory.
case "$DEST" in
  "$HOME"/*/omarchy/plugins/"$PLUGIN_ID") ;;
  *) die "refusing unsafe destination: $DEST" ;;
esac

ASSUME_YES=0
NO_DEPS=0
WANT_TUN=0
for arg in "$@"; do
  case "$arg" in
    --yes) ASSUME_YES=1 ;;
    --no-deps) NO_DEPS=1 ;;
    --tun) WANT_TUN=1 ;;
    -h|--help) sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

[[ $EUID -ne 0 ]] || die "run the installer as your user, not root"

ask() {
  local question="$1" def="${2:-y}" answer hint="[Y/n]"
  [[ "$def" == "n" ]] && hint="[y/N]"
  if [[ $ASSUME_YES -eq 1 ]]; then
    echo "$question $hint → $def"
    [[ "$def" == "y" ]]
    return
  fi
  read -r -p "$question $hint " answer </dev/tty || answer=""
  answer="${answer:-$def}"
  [[ "$answer" =~ ^[Yy] ]]
}

command -v omarchy >/dev/null 2>&1 || die "omarchy CLI not found — this installer targets Omarchy Linux"
[[ -x /usr/bin/python3 ]] || die "/usr/bin/python3 is required (omarchy-xray manager)"

say "Installing ${PLUGIN_ID} (omarchy-xray backend)"

if [[ $NO_DEPS -eq 0 ]]; then
  # Deliberately NOT installed here: review the package source yourself.
  if command -v xray &>/dev/null; then
    say "Xray core found: $(xray version 2>/dev/null | head -1)"
    say "Verify it came from a source you trust: $(command -v xray) ($(pacman -Qo "$(command -v xray)" 2>/dev/null || echo 'not owned by any package'))"
  else
    die "xray core not found — review the package first, then install it (e.g. omarchy pkg aur add xray)"
  fi
  command -v curl >/dev/null 2>&1 || warn "curl not found — latency tests and live traffic need it"
  command -v tun2socks >/dev/null 2>&1 || say "Optional: TUN mode needs tun2socks (review it, then: omarchy pkg aur add tun2socks)"

  if systemctl list-unit-files v2raya.service &>/dev/null && systemctl is-enabled v2raya.service &>/dev/null; then
    warn "v2raya system service is enabled, but the widget no longer uses v2rayA."
    warn "Disable it yourself when ready: sudo systemctl disable --now v2raya.service"
  fi
fi

# --- legacy managers (v2.5 "xraya", v2.3 and earlier "xraya-lite") ----------
NEW_CFG="$HOME/.config/omarchy-xray"
for LEGACY in xraya-lite xraya; do
  LEGACY_UNIT="$HOME/.config/systemd/user/${LEGACY}.service"
  if [[ -e "$LEGACY_UNIT" || -x "$BIN_DIR/$LEGACY" ]]; then
    systemctl --user disable --now "$LEGACY.service" 2>/dev/null || true
    rm -f "$BIN_DIR/$LEGACY" "$LEGACY_UNIT"
    rm -rf "$LEGACY_UNIT.d"
    echo "removed legacy $LEGACY manager" >&2
  fi
  LEGACY_CFG="$HOME/.config/$LEGACY"
  if [[ -d "$LEGACY_CFG" && ! -d "$NEW_CFG" ]]; then
    mv "$LEGACY_CFG" "$NEW_CFG"
    say "Migrated config to $NEW_CFG"
  fi
done

# --- omarchy-xray manager -----------------------------------------------------
mkdir -p "$BIN_DIR"
install -m 755 "$SRC/bin/omarchy-xray" "$MANAGER"
say "Manager installed to $MANAGER"
"$MANAGER" install-unit >/dev/null
say "Systemd user units installed"

# --- subscription -------------------------------------------------------------
if [[ -f "$STATE" ]] && /usr/bin/python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1])).get("subs") else 1)' "$STATE" 2>/dev/null; then
  say "Existing omarchy-xray configuration found — refreshing it"
  "$MANAGER" update >/dev/null || warn "subscription refresh failed (offline?) — later: omarchy-xray update"
elif [[ $NO_DEPS -eq 0 ]]; then
  echo
  SUBURL=""
  # no terminal (scripted run): skip quietly instead of printing a /dev/tty error
  if { : </dev/tty; } 2>/dev/null; then
    read -r -s -p "Paste your subscription URL (Enter to skip; hidden input): " SUBURL </dev/tty || SUBURL=""
  fi
  echo
  if [[ -n "${SUBURL// }" ]]; then
    # via environment so the secret never appears in argv/ps output
    OMARCHY_XRAY_SUB_URL="$SUBURL" "$MANAGER" import - >/dev/null || die "failed to fetch the subscription"
    unset SUBURL
    say "Subscription imported"
  else
    warn "Skipped. Later: export OMARCHY_XRAY_SUB_URL=<url>; omarchy-xray import -"
  fi
fi

# --- optional TUN setup -------------------------------------------------------
if [[ $NO_DEPS -eq 0 ]]; then
  if [[ $WANT_TUN -eq 1 ]] || ask "Set up TUN mode now? (one-time sudo/polkit prompt; proxy mode needs none)" n; then
    "$MANAGER" tun-setup >/dev/null && say "TUN mode ready (switch in the panel or: omarchy-xray mode tun)" \
      || warn "TUN setup skipped/failed — later: omarchy-xray tun-setup"
  fi
fi

# --- bring the tunnel up ------------------------------------------------------
if [[ $NO_DEPS -eq 0 ]] && [[ -f "$STATE" ]]; then
  if ask "Start the Xray service now?"; then
    "$MANAGER" on >/dev/null || warn "failed to start; see: omarchy-xray logs"
    sleep 1
    # Best-effort tunnel probe (non-fatal) through the local HTTP proxy.
    code="$(/usr/bin/python3 - <<'PYPROBE'
try:
    import urllib.request, urllib.error
    proxy = urllib.request.ProxyHandler({
        "http": "http://127.0.0.1:20171",
        "https": "http://127.0.0.1:20171",
    })
    r = urllib.request.build_opener(proxy).open(
        "https://www.gstatic.com/generate_204", timeout=8)
    print(r.status)
except urllib.error.HTTPError as e:
    print(e.code)
except Exception:
    print(0)
PYPROBE
)"
    [[ "$code" == "204" || "$code" == "200" ]] \
      && say "Tunnel verified: HTTP $code through 127.0.0.1:20171" \
      || warn "Tunnel check failed (HTTP ${code:-none}). Try: omarchy-xray test / omarchy-xray doctor"
  fi
fi

# --- copy plugin --------------------------------------------------------------
UPGRADE=0; [[ -d "$DEST" ]] && UPGRADE=1
mkdir -p "$(dirname "$DEST")"
if command -v rsync >/dev/null 2>&1; then
  mkdir -p "$DEST"
  rsync -a --delete --exclude '.git/' --exclude '.gitignore' --exclude 'tests/' "$SRC/" "$DEST/"
else
  rm -rf "$DEST"; cp -r "$SRC" "$DEST"; rm -rf "$DEST/.git" "$DEST/tests"
fi
say "Plugin copied to $DEST"

# --- validate + enable ----------------------------------------------------------
omarchy plugin validate "$DEST" || die "plugin validation failed"
say "Manifest validated"

if omarchy-shell shell ping >/dev/null 2>&1; then
  say "Rescanning plugins in the running shell"
  omarchy-shell shell rescanPlugins || warn "live rescan failed; restart the shell once"
fi

omarchy plugin enable "$PLUGIN_ID" right || die "failed to enable ${PLUGIN_ID}"
say "Widget enabled in the right bar section"

# A live rescan keeps serving the QML the shell already loaded for this plugin
# (the old widget then ignores the new manager's status: endless "Loading…"),
# so an upgrade only takes effect after a full shell restart.
if [[ $UPGRADE -eq 1 ]] && omarchy-shell shell ping >/dev/null 2>&1; then
  say "Restarting the shell to load the new widget code"
  omarchy-restart-shell >/dev/null || warn "shell restart failed — run: omarchy restart shell"
fi

# --- retire the pre-rename plugin ids (krieziey.xray, krieziey.v2raya) --------
for OLD_ID in krieziey.xray krieziey.v2raya; do
  OLD_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$OLD_ID"
  if [[ -d "$OLD_DIR" ]]; then
    omarchy plugin remove "$OLD_ID" --yes >/dev/null 2>&1 || rm -rf "$OLD_DIR"
    say "Removed old plugin id $OLD_ID"
  fi
done

cat <<EOF

Done. The widget talks to omarchy-xray (no accounts, no passwords):

  export OMARCHY_XRAY_SUB_URL=<url>; omarchy-xray import -   # add a subscription
  omarchy-xray select <name|auto>  switch node (auto = best ping)
  omarchy-xray on | off            start / stop the tunnel
  omarchy-xray test                latency-test nodes
  omarchy-xray doctor              check the environment

TUN mode (optional, needs tun2socks): omarchy-xray tun-setup — one polkit/sudo
prompt, once. It installs a root unit that only creates the xray0 device and
its routes, plus a polkit rule for exactly that unit; xray and tun2socks run as
you without privileges. Switching TUN on/off needs no password afterwards.
Undo: omarchy-xray tun-remove

Scripting (Hyprland binds):
  bind = SUPER SHIFT, V, exec, omarchy-shell ${PLUGIN_ID} toggleProxy
  bind = SUPER SHIFT, C, exec, omarchy-shell ${PLUGIN_ID} toggle

Socks proxy: 127.0.0.1:20170   HTTP proxy: 127.0.0.1:20171
EOF
