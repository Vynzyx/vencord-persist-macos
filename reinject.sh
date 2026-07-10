#!/usr/bin/env bash
#
# Re-applies the Vencord patch to Discord.app and restarts Discord so it loads.
# Triggered by the launchd agent on bundle changes, at login, and hourly.
# Requires SIP disabled so the .app bundle is writable (see README).
set -euo pipefail

DATA_DIR="${VENCORD_PERSIST_HOME:-$HOME/.vencord-persist}"
RES="/Applications/Discord.app/Contents/Resources"
STUB="$DATA_DIR/vencord-app.asar"
LOG="$DATA_DIR/reinject.log"
LOCK="$DATA_DIR/.reinject.lock"

log() { printf '%s %s\n' "$(date '+%FT%T')" "$*" >>"$LOG"; }

[ -d "$RES" ]  || exit 0            # Discord not installed
[ -f "$STUB" ] || exit 0            # no captured stub to restore

# The stub is a ~231B loader; refuse to treat anything larger as one.
stub_size=$(stat -f%z "$STUB" 2>/dev/null || echo 0)
[ "$stub_size" -gt 0 ] && [ "$stub_size" -lt 4096 ] || exit 0

# Single-instance lock. mkdir is atomic, so overlapping triggers (the WatchPaths
# event also fires on our own cp below) exit here instead of racing the restart.
mkdir "$LOCK" 2>/dev/null || exit 0
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

# Patched already? app.asar is byte-identical to the stub. Byte-compare, never
# grep: the real ~2.3MB archive contains the bytes "vencord" and false-positives.
cmp -s "$RES/app.asar" "$STUB" && exit 0

# Not the stub. Guard against a partial mid-update write before overwriting.
size=$(stat -f%z "$RES/app.asar" 2>/dev/null || echo 0)
if [ "$size" -lt 500000 ]; then
  log "app.asar=${size}B: neither stub nor full archive, skipping (partial write?)"
  exit 0
fi

log "Discord unpatched (app.asar=${size}B), restoring stub"
cp -f "$RES/app.asar" "$RES/_app.asar" || { log "failed to preserve real archive"; exit 1; }
cp -f "$STUB" "$RES/app.asar"          || { log "failed to install stub"; exit 1; }
cmp -s "$RES/app.asar" "$STUB"         || { log "re-injection failed"; exit 1; }
log "re-injected"

# Restart only after a real repatch, and only if Discord is running. The lock is
# held across the whole quit/relaunch so no second run can spawn a duplicate.
if pgrep -x Discord >/dev/null 2>&1; then
  log "restarting Discord"
  osascript -e 'quit app "Discord"' >>"$LOG" 2>&1 || true
  for _ in $(seq 1 15); do pgrep -x Discord >/dev/null 2>&1 || break; sleep 1; done
  pkill -9 -x Discord 2>/dev/null || true
  sleep 2
  open -a Discord && log "relaunched Discord"
else
  log "Discord not running, patch ready for next launch"
fi
