#!/usr/bin/env bash
set -euo pipefail

LABEL="com.vynzyx.vencord-reinject"
DATA_DIR="$HOME/.vencord-persist"
PLIST_DEST="$HOME/Library/LaunchAgents/$LABEL.plist"
RES="/Applications/Discord.app/Contents/Resources"
STUB_MAX=4096

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die()  { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '==> %s\n' "$*"; }

[ "$(uname)" = "Darwin" ] || die "macOS only."
[ -d "$RES" ] || die "Discord.app not found in /Applications."

if csrutil status 2>/dev/null | grep -qi enabled; then
  die "System Integrity Protection is enabled, so the Discord bundle is not writable.
Read the README's security section before disabling it."
fi

# Discord must already be Vencord-patched so we can capture the loader stub.
# The stub is ~231B; a vanilla archive is ~2.3MB.
[ -f "$RES/app.asar" ] || die "no app.asar in the Discord bundle."
app_size=$(stat -f%z "$RES/app.asar")
if [ "$app_size" -ge "$STUB_MAX" ]; then
  die "Discord is not patched (app.asar is ${app_size}B).
Install Vencord first via the official installer (https://vencord.dev/download), then re-run this."
fi

info "Capturing Vencord loader stub"
mkdir -p "$DATA_DIR"
cp -f "$RES/app.asar" "$DATA_DIR/vencord-app.asar"

info "Installing reinject script"
install -m 755 "$SRC_DIR/reinject.sh" "$DATA_DIR/reinject.sh"

info "Writing launchd agent"
mkdir -p "$HOME/Library/LaunchAgents"
sed -e "s|{{SCRIPT}}|$DATA_DIR/reinject.sh|g" \
    -e "s|{{ERRLOG}}|$DATA_DIR/launchd.err.log|g" \
    "$SRC_DIR/$LABEL.plist" >"$PLIST_DEST"

info "Loading agent"
launchctl unload "$PLIST_DEST" 2>/dev/null || true
launchctl load "$PLIST_DEST"

if launchctl list | grep -q "$LABEL"; then
  info "Installed. $LABEL is loaded and watching the Discord bundle."
else
  die "agent failed to load; check $DATA_DIR/launchd.err.log"
fi
