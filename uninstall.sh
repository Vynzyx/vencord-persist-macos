#!/usr/bin/env bash
set -euo pipefail

LABEL="com.vynzyx.vencord-reinject"
DATA_DIR="$HOME/.vencord-persist"
PLIST_DEST="$HOME/Library/LaunchAgents/$LABEL.plist"

info() { printf '==> %s\n' "$*"; }

if [ -f "$PLIST_DEST" ]; then
  info "Unloading agent"
  launchctl unload "$PLIST_DEST" 2>/dev/null || true
  rm -f "$PLIST_DEST"
fi

info "Removing $DATA_DIR"
rm -rf "$DATA_DIR"

info "Done. Discord is left untouched (Vencord stays patched)."
info "To remove Vencord itself, use the official installer's uninstall."
