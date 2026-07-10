# vencord-persist-macos

Keeps [Vencord](https://vencord.dev) patched into the **official Discord.app on macOS**, and re-applies the patch automatically after Discord updates.

Vencord works by replacing Discord's `Contents/Resources/app.asar` with a small loader that pulls in the Vencord patcher. Every full Discord app update overwrites that file with a vanilla archive, silently removing Vencord until you re-run the installer. This tool watches the bundle and restores the loader within seconds of an update, then restarts Discord so the patch takes effect — no manual step.

If you don't specifically need the official client, [Vesktop](https://github.com/Vencord/Vesktop) ships Vencord built in and needs none of this. This project exists for people who want Vencord inside the real Discord.app.

## How it works

A `launchd` agent (`com.vynzyx.vencord-reinject`) runs `reinject.sh` on three triggers:

- **`WatchPaths`** on the Discord bundle — fires the moment an update swaps `app.asar`.
- **`RunAtLoad`** — at login.
- **`StartInterval` (hourly)** — a backstop in case a watch event is missed.

`reinject.sh` restores a saved copy of the loader stub whenever `app.asar` is no longer it. A few details that matter:

- **Detection is a byte comparison** (`cmp`), never a `grep` for `"vencord"` — the real 2.3 MB archive contains those bytes and would false-positive as "already patched."
- **An atomic `mkdir` lock** guarantees a single instance. The `WatchPaths` event also fires on the script's own write, so without the lock overlapping runs race the restart and spawn duplicate Discord processes.
- **A size guard** skips partial `app.asar` writes mid-update, so a half-written file is never preserved as the "real" archive.
- **Discord is only restarted after an actual repatch**, and only if it's running.

## Requirements

- macOS.
- Vencord already installed via the [official installer](https://vencord.dev/download). This tool captures the loader from your patched Discord — it does not ship one.
- **System Integrity Protection (SIP) disabled.**

### About SIP

macOS protects other apps' bundles (App Management / SIP), so a background process cannot modify `Discord.app` while SIP is enabled. Disabling SIP (`csrutil disable` from Recovery) is what makes the automatic re-patch possible.

**This is a real security tradeoff.** SIP is a core macOS protection; turning it off weakens your system's defenses against tampering. Understand what you're giving up before doing this, and consider [Vesktop](https://github.com/Vencord/Vesktop) instead if you're not comfortable with it. `install.sh` refuses to run while SIP is enabled.

## Install

```sh
git clone https://github.com/Vynzyx/vencord-persist-macos
cd vencord-persist-macos
./install.sh
```

The installer verifies your environment, captures the loader stub into `~/.vencord-persist/`, generates the `launchd` agent with the correct paths, and loads it.

## Uninstall

```sh
./uninstall.sh
```

Removes the agent and `~/.vencord-persist/`. Discord and Vencord are left as they are; use the official installer's uninstall to remove Vencord itself.

## Layout

| Path | Purpose |
| --- | --- |
| `~/.vencord-persist/reinject.sh` | The re-patch script (installed copy). |
| `~/.vencord-persist/vencord-app.asar` | Captured Vencord loader stub. |
| `~/.vencord-persist/reinject.log` | Activity log. |
| `~/Library/LaunchAgents/com.vynzyx.vencord-reinject.plist` | The agent. |

## Caveats

- Files re-patch within seconds, but Vencord only loads at Discord launch. If an update relaunches Discord faster than the watch fires, that one session runs vanilla until the next restart.
- A repatch during an active call will restart Discord and drop the call. This only happens at the moment of a full app update.

## License

MIT — see [LICENSE](LICENSE).
