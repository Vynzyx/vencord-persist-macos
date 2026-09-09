#!/usr/bin/env bash
#
# Re-applies the Vencord injection to the official Discord.app on macOS and
# restarts Discord so it loads. Triggered by the launchd agent when Discord's
# per-user data changes (i.e. an update), at login, and hourly.
#
# Unlike the app.asar method, this NEVER touches the code-signed .app bundle, so
# it works with System Integrity Protection ENABLED. See README.md for the why.
#
# Injection point (a plain JS file in the home folder, outside the signature):
#   ~/Library/Application Support/discord/app-<ver>/modules/
#       discord_desktop_core-<n>/discord_desktop_core/index.js
# Normally this is just `module.exports = require('./core.asar')`. We replace it
# with a shim that hooks electron.BrowserWindow via Vencord's patcher.js, then
# loads ./core.asar. Vencord's patcher expects the app.asar layout (it loads the
# "original" from a sibling _app.asar), so the shim fakes require.main and points
# it at a local symlink `vc_shim/_app.asar -> ../core.asar`.

set -uo pipefail

DATA_DIR="${VENCORD_PERSIST_HOME:-$HOME/.vencord-persist}"
DISCORD_DATA="$HOME/Library/Application Support/discord"
VENCORD_PATCHER="${VENCORD_PATCHER:-$HOME/Library/Application Support/Vencord/dist/patcher.js}"
LOG="$DATA_DIR/reinject.log"
LOCK="$DATA_DIR/.reinject.lock"
MARKER="Vencord injection (module method"   # sentinel identifying our shim

log() { printf '%s %s\n' "$(date '+%FT%T')" "$*" >>"$LOG"; }

mkdir -p "$DATA_DIR"
[ -d "$DISCORD_DATA" ]     || exit 0                       # Discord never launched
[ -f "$VENCORD_PATCHER" ]  || { log "Vencord patcher missing: $VENCORD_PATCHER"; exit 0; }

# Single-instance lock. mkdir is atomic, so overlapping triggers (the WatchPaths
# event also fires on our own writes) exit here instead of racing the restart.
# Self-heal a lock left by a crash if it is older than two minutes.
if ! mkdir "$LOCK" 2>/dev/null; then
  lock_age=$(( $(date +%s) - $(stat -f%m "$LOCK" 2>/dev/null || echo "$(date +%s)") ))
  if [ "$lock_age" -gt 120 ]; then
    rmdir "$LOCK" 2>/dev/null && mkdir "$LOCK" 2>/dev/null || exit 0
  else
    exit 0
  fi
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

patched_any=0

# Patch every desktop_core index.js that is not already our shim.
while IFS= read -r index; do
  [ -f "$index" ] || continue
  core_dir="$(dirname "$index")"

  grep -q "$MARKER" "$index" 2>/dev/null && continue        # already patched
  [ -f "$core_dir/core.asar" ] || { log "skip (no core.asar): $core_dir"; continue; }

  # Preserve the pristine vanilla index.js once, for a clean uninstall.
  [ -f "$core_dir/index.js.orig" ] || cp "$index" "$core_dir/index.js.orig"

  # Controlled symlink so the patcher's "load original" resolves to core.asar
  # instead of a nonexistent _app.asar beside the signed bundle.
  mkdir -p "$core_dir/vc_shim/app.asar"
  ln -sf "../core.asar" "$core_dir/vc_shim/_app.asar"

  # Write the shim. Unquoted heredoc so $VENCORD_PATCHER expands; the JS body
  # contains no other shell metacharacters.
  cat > "$index" <<EOF
// --- Vencord injection (module method; signed bundle untouched, SIP-safe) ---
// Managed by vencord-persist-macos. Original saved as index.js.orig.
const path = require("path");
const Mod = require("module");
const realMain = process.mainModule;
try {
  const fake = new Mod(path.join(__dirname, "vc_shim", "app.asar", "index.js"), null);
  fake.filename = path.join(__dirname, "vc_shim", "app.asar", "index.js");
  fake.path = path.join(__dirname, "vc_shim", "app.asar");
  process.mainModule = fake;              // patcher reads require.main to find the "original"
  require("$VENCORD_PATCHER");            // hooks BrowserWindow, then loads original -> core.asar via symlink
} catch (e) {
  console.log("[Vencord shim] patcher error:", e && e.message);
} finally {
  process.mainModule = realMain;          // restore before the real core runs
}
module.exports = require("./core.asar");
EOF

  log "patched module: $index"
  patched_any=1
done < <(find "$DISCORD_DATA" -path "*discord_desktop_core*/discord_desktop_core/index.js" 2>/dev/null)

# Restart only after a real (re)patch, and only if Discord is running. The lock is
# held across the whole quit/relaunch so no second run can spawn a duplicate.
if [ "$patched_any" -eq 1 ] && pgrep -x Discord >/dev/null 2>&1; then
  log "restarting Discord to load Vencord"
  osascript -e 'quit app "Discord"' >>"$LOG" 2>&1 || true
  for _ in $(seq 1 15); do pgrep -x Discord >/dev/null 2>&1 || break; sleep 1; done
  pkill -9 -x Discord 2>/dev/null || true
  sleep 2
  open -a Discord >>"$LOG" 2>&1 && log "relaunched Discord"
fi

exit 0
