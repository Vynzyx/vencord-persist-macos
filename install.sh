#!/usr/bin/env bash
set -euo pipefail

# Installs the launchd agent that keeps Vencord injected into the official
# Discord.app on macOS across updates. Works with SIP ENABLED: it injects through
# Discord's desktop_core module in your home folder, never the signed .app bundle.

LABEL="com.vynzyx.vencord-reinject"
DATA_DIR="$HOME/.vencord-persist"
DISCORD_DATA="$HOME/Library/Application Support/discord"
VENCORD_PATCHER="$HOME/Library/Application Support/Vencord/dist/patcher.js"
PLIST_DEST="$HOME/Library/LaunchAgents/$LABEL.plist"

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die()  { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '==> %s\n' "$*"; }

[ "$(uname)" = "Darwin" ] || die "macOS only."
[ -d "/Applications/Discord.app" ] || die "Discord.app not found in /Applications. Install Discord first."

# Vencord must already be installed (we reuse its patcher.js). It ships no
# uninstall footprint we depend on beyond dist/patcher.js.
if [ ! -f "$VENCORD_PATCHER" ]; then
  die "Vencord not found at:
  $VENCORD_PATCHER
Install Vencord first with the official installer (https://vencord.dev/download),
then re-run this. (You do NOT need to keep Vencord's own auto-patch enabled.)"
fi

info "Installing reinject script into $DATA_DIR"
mkdir -p "$DATA_DIR"
install -m 755 "$SRC_DIR/reinject.sh" "$DATA_DIR/reinject.sh"

info "Writing launchd agent"
mkdir -p "$HOME/Library/LaunchAgents"
sed -e "s|{{SCRIPT}}|$DATA_DIR/reinject.sh|g" \
    -e "s|{{WATCHDIR}}|$DISCORD_DATA|g" \
    -e "s|{{ERRLOG}}|$DATA_DIR/launchd.err.log|g" \
    "$SRC_DIR/$LABEL.plist" >"$PLIST_DEST"

info "Loading agent"
launchctl unload "$PLIST_DEST" 2>/dev/null || true
launchctl load "$PLIST_DEST"

# launchctl load is asynchronous; give the service a moment to register.
loaded=0
for _ in 1 2 3 4 5; do
  if launchctl list "$LABEL" >/dev/null 2>&1; then loaded=1; break; fi
  sleep 1
done
[ "$loaded" -eq 1 ] || die "agent failed to load; check $DATA_DIR/launchd.err.log"

info "Applying the injection now"
VENCORD_PERSIST_HOME="$DATA_DIR" VENCORD_PATCHER="$VENCORD_PATCHER" bash "$DATA_DIR/reinject.sh" || true

info "Installed. Vencord will be re-applied automatically after every Discord update."
info "Restart Discord once now if it is open, to load Vencord this session."
