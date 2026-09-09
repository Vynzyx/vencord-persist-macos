#!/usr/bin/env bash
set -euo pipefail

# Removes the agent and reverts every patched desktop_core module back to vanilla.
# Discord and Vencord themselves are left installed.

LABEL="com.vynzyx.vencord-reinject"
DATA_DIR="$HOME/.vencord-persist"
DISCORD_DATA="$HOME/Library/Application Support/discord"
PLIST_DEST="$HOME/Library/LaunchAgents/$LABEL.plist"
MARKER="Vencord injection (module method"

info() { printf '==> %s\n' "$*"; }

if [ -f "$PLIST_DEST" ]; then
  info "Unloading agent"
  launchctl unload "$PLIST_DEST" 2>/dev/null || true
  rm -f "$PLIST_DEST"
fi

info "Reverting patched desktop_core modules to vanilla"
if [ -d "$DISCORD_DATA" ]; then
  while IFS= read -r index; do
    [ -f "$index" ] || continue
    grep -q "$MARKER" "$index" 2>/dev/null || continue
    core_dir="$(dirname "$index")"
    if [ -f "$core_dir/index.js.orig" ]; then
      mv -f "$core_dir/index.js.orig" "$index"
    else
      printf "module.exports = require('./core.asar');\n" >"$index"
    fi
    rm -rf "$core_dir/vc_shim"
    info "reverted: $index"
  done < <(find "$DISCORD_DATA" -path "*discord_desktop_core*/discord_desktop_core/index.js" 2>/dev/null)
fi

info "Removing $DATA_DIR"
rm -rf "$DATA_DIR"

info "Done. Restart Discord to run it vanilla again."
info "To remove Vencord itself, use the official Vencord installer's uninstall."
