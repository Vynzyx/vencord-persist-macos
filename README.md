# vencord-persist-macos

Keeps [Vencord](https://vencord.dev) injected into the **official Discord.app on macOS**, and re-applies it automatically after every Discord update — **with System Integrity Protection (SIP) left enabled** and the signed Discord app never modified.

Use the real Discord client (for working screen-share **with audio**, which [Vesktop](https://github.com/Vencord/Vesktop) can't do on macOS) *and* have Vencord — persistently, without disabling SIP or breaking Discord's code signature.

## Why this exists

The usual way to get Vencord into the real Discord replaces `Discord.app/Contents/Resources/app.asar`. That file lives **inside the code-signed `.app` bundle**, so editing it invalidates Discord's Developer ID signature. On modern macOS (especially Apple Silicon) that means:

- macOS refuses to launch it — *"Discord is damaged and can't be opened"* — unless you either **disable SIP** or **ad-hoc re-sign** the app.
- Ad-hoc re-signing changes the app's identity, which **breaks the keychain** ("Discord Safe Storage" password prompts every launch), **strips the entitlements** Electron and audio capture need, and makes Discord **self-terminate a few seconds into launch** on the normal Dock path.

So the classic approach forces a bad trade: turn SIP off, or fight the signature forever.

**This project avoids the bundle entirely.**

## How it works

On macOS, Discord's `.app` in `/Applications` is just a bootstrap. The actual client code is loaded from an **unsigned module in your home folder**:

```
~/Library/Application Support/discord/app-<version>/modules/
    discord_desktop_core-<n>/discord_desktop_core/index.js
```

By default that file is a one-liner:

```js
module.exports = require('./core.asar');
```

Because it's a plain JS file **outside the `.app` bundle and outside the code signature**, we can replace it freely. This tool swaps it for a small shim that:

1. Hooks `electron.BrowserWindow` (via Vencord's `patcher.js`) **before** `core.asar` loads, so every window Discord opens gets Vencord's preload injected — exactly what the app.asar method achieves, but from outside the bundle.
2. Loads the real `./core.asar` so Discord runs normally.

Vencord's `patcher.js` is built for the app.asar layout — during setup it loads the "original app" from a sibling `_app.asar`. To satisfy that with no bundle involved, the shim briefly fakes `require.main` and points it at a local symlink (`vc_shim/_app.asar → ../core.asar`) so the patcher cleanly loads `core.asar`.

The result:

- ✅ **SIP stays on.**
- ✅ Discord keeps its **real Developer ID signature and entitlements** — no "damaged", no keychain prompts, mic/screen-share audio intact, normal Dock launch.
- ✅ Every update rebuilds the module vanilla; a `launchd` agent re-applies the shim within seconds and restarts Discord so Vencord loads.

### The agent

A `launchd` agent (`com.vynzyx.vencord-reinject`) runs `reinject.sh` on three triggers:

- **`WatchPaths`** on `~/Library/Application Support/discord` — fires when an update stages a new `app-<version>` folder.
- **`RunAtLoad`** — at login.
- **`StartInterval` (hourly)** — a backstop in case a watch event is missed.

`reinject.sh` is idempotent and safe:

- **A sentinel comment** marks an already-injected module, so re-runs are no-ops (never double-patches).
- **An atomic `mkdir` lock** guarantees a single instance; the `WatchPaths` event also fires on the script's own writes, so without the lock overlapping runs would race the restart.
- **The pristine `index.js` is saved** as `index.js.orig` for a clean revert.
- **Discord is only restarted after an actual (re)patch**, and only if it's running.

## Requirements

- macOS (Apple Silicon or Intel). **SIP can stay enabled.**
- Discord installed in `/Applications`.
- **Vencord installed** via the [official installer](https://vencord.dev/download) — this tool reuses its `dist/patcher.js`. You do **not** need to keep Vencord's own auto-patch/"Patch Discord" enabled; this replaces it with an update-proof one.

## Install

```sh
git clone https://github.com/Vynzyx/vencord-persist-macos
cd vencord-persist-macos
./install.sh
```

The installer verifies your environment, installs `reinject.sh` into `~/.vencord-persist/`, generates the `launchd` agent with the correct paths, loads it, and injects immediately. Restart Discord once to load Vencord this session.

## Uninstall

```sh
./uninstall.sh
```

Unloads the agent and reverts every patched module back to vanilla (`index.js.orig`). Discord and Vencord are left installed; use the official Vencord installer to remove Vencord itself.

## Layout

| Path | Purpose |
| --- | --- |
| `~/.vencord-persist/reinject.sh` | The re-injection script (installed copy). |
| `~/.vencord-persist/reinject.log` | Activity log. |
| `~/Library/LaunchAgents/com.vynzyx.vencord-reinject.plist` | The agent. |
| `…/discord_desktop_core/index.js` | Injection point (replaced with the shim). |
| `…/discord_desktop_core/index.js.orig` | Saved pristine original, for revert. |

## Caveats

- The shim relies on Discord's `desktop_core` module layout and Vencord's patcher internals. Both are stable in practice, but a future major change to either could need a tweak — the agent re-applies cleanly regardless.
- A repatch happens at the moment of a full Discord update and restarts Discord, which would drop an active call at that instant.
- Vencord only loads at Discord launch; the agent restarts Discord after re-patching so this is automatic.

## License

MIT — see [LICENSE](LICENSE).
