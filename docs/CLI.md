# PlayCover command line interface

PlayCover can be driven from a terminal: list, install, configure, launch, clean and uninstall iOS apps
without opening the PlayCover window. Every option in an app's **Settings** window (Keymapping, Graphics,
Fixes and Misc tabs) is available as a command line flag.

The CLI is built into the PlayCover executable itself, so it always matches the app version you have
installed and shares its library, settings and PlayChain/KeyCover data.

- [Setup](#setup)
- [Quick start](#quick-start)
- [Choosing an app](#choosing-an-app)
- [Commands](#commands)
  - [list](#list) · [info](#info) · [devices](#devices) · [launch](#launch) · [settings](#settings)
  - [install](#install) · [export](#export) · [uninstall](#uninstall) · [clear](#clear)
  - [playtools](#playtools) · [plugins](#plugins) · [link](#link) · [help / version](#help--version)
- [Setting options](#setting-options)
- [Output, exit codes and scripting](#output-exit-codes-and-scripting)
- [KeyCover and PlayChain](#keycover-and-playchain)
- [Permissions and troubleshooting](#permissions-and-troubleshooting)

## Setup

Run any command through the executable inside the app bundle:

```bash
/Applications/PlayCover.app/Contents/MacOS/PlayCover help
```

To get a short `playcover` command, let PlayCover install a small wrapper script (default `~/.local/bin`):

```bash
/Applications/PlayCover.app/Contents/MacOS/PlayCover link
```

Use `--dir` for another directory on your `PATH`, e.g. `--dir /opt/homebrew/bin`. The wrapper remembers where
PlayCover.app is, falls back to Spotlight if you move it, and honours a `PLAYCOVER_APP` environment variable:

```bash
PLAYCOVER_APP=~/Downloads/PlayCover.app playcover list
```

Running `PlayCover` with no arguments (or from Finder/Dock) still opens the normal app window. Only a known
command as the first argument switches to the CLI.

## Quick start

```bash
playcover install ~/Downloads/Game.ipa --device ipad-pro-13-m5 --resolution 1440p --category games
playcover list
playcover launch com.example.game
playcover launch "My Game" --keymapping off --resolution 4k   # one-off: restored when the game quits
playcover settings set com.example.game --keymapping on --sensitivity 70
playcover clear com.example.game --playchain --yes
playcover uninstall com.example.game --all --yes
```

## Choosing an app

Commands that act on an installed app take `<app>`, which can be:

| Form | Example |
| --- | --- |
| Bundle identifier (exact) | `com.miHoYo.GenshinImpact` |
| App name, case-insensitive | `"Genshin Impact"` |
| Path to the installed bundle | `~/Library/Containers/io.playcover.PlayCover/Applications/com.miHoYo.GenshinImpact.app` |

If a name matches more than one app, the command fails and lists the bundle identifiers to use instead.

## Commands

All commands accept `--help` (command help) and `--verbose` (print PlayCover's internal log lines to stderr).
Boolean values accept `on/off`, `true/false`, `yes/no`, `1/0`, `enabled/disabled`. Options can be written as
`--name value` or `--name=value`; `--` ends option parsing. An on/off option given without a value means `on`
(`--hide-title-bar` is `--hide-title-bar on`). Other options never take a following `--option` as their value, so
a forgotten value is reported as `--device requires a value`.

### list

```bash
playcover list [--json]
```

Lists installed apps: bundle identifier, name and version. `--json` adds the bundle path and application type.

### info

```bash
playcover info <app> [--json]
```

Shows everything PlayCover knows about one app: version, executable, whether PlayTools is injected, custom
plugins, and the location of its alias, PlayCover settings file, keymaps, data container, preferences file,
PlayChain and entitlements.

### devices

```bash
playcover devices [--json]
```

Lists the iOS devices an app can be told it is running on (`--device`). Either the identifier or the alias can be
passed to `--device`:

| Identifier | Alias | Device | Chip | RAM |
| --- | --- | --- | --- | --- |
| `iPad6,7` | `ipad-pro-12.9-1st-gen` | iPad Pro (12.9-inch) (1st gen) | A9X | 4GB |
| `iPad8,6` | `ipad-pro-12.9-3rd-gen` | iPad Pro (12.9-inch) (3rd gen) | A12X | 4GB |
| `iPad13,8` | `ipad-pro-12.9-m1` | iPad Pro (12.9-inch) (5th gen) — default | M1 | 8GB |
| `iPad14,5` | `ipad-pro-12.9-m2` | iPad Pro (12.9-inch) (6th gen) | M2 | 8GB |
| `iPad16,6` | `ipad-pro-13-m4` | iPad Pro (13-inch) (7th gen) | M4 | 8GB |
| `iPad17,3` | `ipad-pro-13-m5` | iPad Pro (13-inch) (8th gen) | M5 | 12GB |
| `iPhone14,3` | `iphone-13-pro-max` | iPhone 13 Pro Max | A15 | 6GB |
| `iPhone15,3` | `iphone-14-pro-max` | iPhone 14 Pro Max | A16 | 6GB |
| `iPhone16,2` | `iphone-15-pro-max` | iPhone 15 Pro Max | A17 Pro | 8GB |
| `iPhone17,2` | `iphone-16-pro-max` | iPhone 16 Pro Max | A18 Pro | 8GB |
| `iPhone18,3` | `iphone-17` | iPhone 17 | A19 | 8GB |
| `iPhone18,4` | `iphone-air` | iPhone Air | A19 Pro | 12GB |
| `iPhone18,1` | `iphone-17-pro` | iPhone 17 Pro | A19 Pro | 12GB |
| `iPhone18,2` | `iphone-17-pro-max` | iPhone 17 Pro Max | A19 Pro | 12GB |

### launch

```bash
playcover launch <app> [setting options] [--save] [--wait] [--lldb | --lldb-terminal] [--keycover-password-stdin]
```

Runs the same steps as the Play button — prohibited-app checks, PlayTools plugin/localization install,
entitlement and Info.plist re-signing when needed, refreshing `~/Library/Frameworks/PlayTools.framework`,
architecture validation, KeyCover unlock — and then opens the app. It never shows dialogs; problems are printed
and reflected in the exit code. The "a newer version is available in your sources" prompt of the GUI is skipped.

| Flag | Meaning |
| --- | --- |
| *setting options* | Any [setting option](#setting-options). Without `--save` they apply **to this launch only**: the previous settings are written back as soon as the app quits. |
| `--save` | Keep the setting options permanently (same as `settings set` followed by `launch`). |
| `--wait` | Stay in the foreground until the app quits. While waiting, the display is kept awake whenever the app is frontmost (as PlayCover does). |
| `--lldb` | Start the app under `lldb` attached to this terminal (`-o run`). |
| `--lldb-terminal` | Start the app under `lldb` in a new Terminal window (the GUI's "Open in terminal"). |
| `--keycover-password-stdin` | Read the KeyCover master password from the first line of stdin, see [KeyCover](#keycover-and-playchain). |

The CLI waits for the app to quit automatically when it has something to undo afterwards (one-off settings, or a
PlayChain it unlocked and must lock again), and says so on stderr. Pressing Ctrl-C while it waits restores the
settings and relocks PlayChain right away; the game itself keeps running.

```bash
# Test a game as an iPhone 17 Pro Max at 1440p without changing its saved settings
playcover launch com.example.game --device iphone-17-pro-max --resolution 1440p

# Change and keep
playcover launch com.example.game --keymapping off --save

# Use in a script that must block until the game is closed
playcover launch com.example.game --wait && echo "game closed"
```

### settings

```bash
playcover settings show  <app> [--json]
playcover settings set   <app> <setting options>
playcover settings reset <app> [--yes]
```

- `show` prints the app's saved settings (the raw keys of `App Settings/<bundle id>.plist`) plus the bundle-level
  ones: `introspection`, `iosFrameworks`, `applicationCategoryType` and `playTools`.
- `set` writes the given [setting options](#setting-options) permanently.
- `reset` restores PlayCover's defaults, exactly like **Reset settings** in the settings window. Asks for
  confirmation unless `--yes` is given.

### install

```bash
playcover install <file.ipa> [--playtools on|off] [setting options] [--launch]
```

Installs a **decrypted** IPA into the PlayCover library, like dropping it on the window.

| Flag | Meaning |
| --- | --- |
| `--playtools on\|off` | Inject PlayTools (keymapping, display control, bypasses). Default `on`, the install dialog's default answer. The "Inject PlayTools?" dialog is never shown. |
| `--category <type>` | Application type, set before the app is signed (otherwise the default from PlayCover's Install preferences is used). |
| *setting options* | Applied to the freshly installed app. |
| `--launch` | Launch the app once it is installed. |

Install steps are echoed to stderr. If the app is also available natively for macOS on the App Store, a warning
is printed instead of the GUI's dialog and installation continues. Encrypted IPAs are rejected.

```bash
playcover install ~/Downloads/Game.ipa --device ipad-pro-13-m5 --resolution auto --scale 2 \
    --playchain on --category games --launch
```

### export

```bash
playcover export <file.ipa>
```

Injects PlayTools into an IPA for sideloading (the same export the PlayCover menu offers) and prints the path
of the new IPA, which is written to `~/Documents/<app name>.ipa`.

### uninstall

```bash
playcover uninstall <app> [--data] [--preferences] [--keymap] [--settings] [--entitlements] [--playchain] [--all] [--yes]
```

Removes the app and its `~/Applications/PlayCover` alias. By default nothing else is touched — unlike the GUI, the
CLI does not follow the "When uninstalling" preferences; name what should go:

| Flag | Removes |
| --- | --- |
| `--data` | The app's data container and its entries in `~/Library/Caches`, `HTTPStorages`, `Application Scripts` and `Saved Application State` (moved to the Trash) |
| `--preferences` | Only the app's own preferences file (`Data/Library/Preferences/<bundle id>.plist` in its container) |
| `--keymap` | All of the app's keymaps |
| `--settings` | The app's PlayCover settings |
| `--entitlements` | The entitlements PlayCover saved for the app |
| `--playchain` | The app's PlayChain (and its KeyCover-encrypted copy) |
| `--all` | All of the above |

The app must not be running. You are asked to confirm unless `--yes` is given; without a terminal (scripts, CI)
`--yes` is required.

### clear

```bash
playcover clear <app> [--data] [--preferences] [--playchain] [--settings] [--keymap] [--all] [--yes]
```

Resets parts of an app without uninstalling it. At least one of the flags is required:

| Flag | Clears |
| --- | --- |
| `--data` | App data: same as **Clear App Data** in the app's context menu (container and caches moved to the Trash). Logs you out of most games. |
| `--preferences` | App preferences: deletes only the app's own preferences plist, keeping saves and downloaded data. |
| `--playchain` | PlayChain data: the emulated keychain (`.db` and `.keyCover` copies). Use it when a game is stuck on a stale login. |
| `--settings` | PlayCover settings for the app (same as `settings reset`). |
| `--keymap` | All of the app's keymaps. |
| `--all` | All of the above. |

The app must not be running. Asks for confirmation unless `--yes` is given.

```bash
playcover clear com.example.game --playchain --preferences --yes
```

### playtools

```bash
playcover playtools <app> status|install|remove
```

Shows whether PlayTools is injected, injects it into an app installed without it, or removes it (the button at
the bottom of the Misc tab).

### plugins

```bash
playcover plugins <app> list
playcover plugins <app> add <file.dylib>
playcover plugins <app> remove <name>
```

Manages the custom dylib plugins that PlayTools loads into the app (Misc tab › Custom plugins). Only available for
apps with PlayTools injected. Plugins run inside the game with its privileges: only add code you trust.

### link

```bash
playcover link [--dir <directory>]
```

Writes the `playcover` wrapper script described in [Setup](#setup). It only overwrites a file it created itself.

### help / version

```bash
playcover help                 # command overview
playcover help <command>       # one command, including setting options where they apply
playcover help options         # every setting option
playcover version
```

## Setting options

The same options are accepted by `launch`, `settings set` and `install`. Options are applied in the order given.

### Keymapping

| Option | Values | Settings window |
| --- | --- | --- |
| `--keymapping` | on/off | Keymapping |
| `--smart-keymap` | on/off | Smart Keymap (turn keymapping off while typing into a text field) |
| `--scroll-wheel` | on/off | Enable Scroll Wheel |
| `--disable-builtin-mouse` | on/off | Disable Built-in Mouse Support |
| `--sensitivity` | 0–100 | Sensitivity |

### Graphics

| Option | Values | Settings window |
| --- | --- | --- |
| `--device` | identifier or alias, see [devices](#devices) | iOS device |
| `--resolution` | `app-default`, `auto`, `1080p`, `1440p`, `4k`, `custom`, `resizable` | Resolution |
| `--aspect-ratio` | `4:3`, `16:9`, `16:10` | Aspect ratio (for 1080p, 1440p and 4K) |
| `--width`, `--height` | pixels | Custom width / height. Given without `--resolution`, they switch it to `custom`. |
| `--scale` | 0.5–10 | Resolution Scaler |
| `--resizable-aspect-ratio` | `free`, `custom`, `4:3`, `16:9`, `16:10` | Aspect ratio of the **Resizable** window |
| `--resizable-aspect-width`, `--resizable-aspect-height` | number | Custom resizable ratio. Given without `--resizable-aspect-ratio`, they switch it to `custom`. |
| `--window-fix` | on/off | Fix window display issues (effective with `--resolution app-default`) |
| `--window-fix-method` | `normal`, `alternate` | Window fix method |
| `--rotation` | `default`, `portrait`, `landscape-right`, `portrait-upside-down`, `flip-fix` | Device Orientation |
| `--disable-display-sleep` | on/off | Disable display sleep |
| `--hide-title-bar` | on/off | Hide titlebar |
| `--floating-window` | on/off | Floating window |

`auto` picks the resolution from your main display when the app starts, like the GUI. As in the settings window,
a warning is printed when width × height × scale is high enough to crash some apps.

### Fixes

| Option | Values | Settings window |
| --- | --- | --- |
| `--playchain` | on/off | Enable PlayChain |
| `--playchain-debugging` | on/off | PlayChain debugging |
| `--jailbreak-bypass` | on/off | Enable Jailbreak Bypass |
| `--introspection` | on/off | Insert Introspection libraries (edits `LSEnvironment` and re-signs the app) |
| `--ios-frameworks` | on/off | Force Insert iOS Frameworks (edits `LSEnvironment` and re-signs the app) |
| `--mic-permission-sync` | on/off | Check Microphone Permission Synchronously |
| `--block-sleep-spamming` | on/off | Prevent usleep call spamming |

### Misc

| Option | Values | Settings window |
| --- | --- | --- |
| `--category` | `games`, `entertainment`, `utilities`, … or `none` (any `public.app-category.*` suffix) | Application Type (re-signs the app) |
| `--metal-hud` | on/off | Metal HUD |
| `--root-work-dir` | on/off | Start app at root directory |
| `--limit-motion-updates` | on/off | Limit motion sensor update frequency |
| `--ignore-unity-keyboard-error` | on/off | Ignore Unity keyboard initialization error |
| `--discord` | on/off | Enable Discord activity |
| `--discord-app-id`, `--discord-details`, `--discord-state`, `--discord-image` | text | Custom Discord activity fields |

Launch-only debugging options (`--lldb`, `--lldb-terminal`) are listed under [launch](#launch); PlayTools injection and
custom plugins have their own commands ([playtools](#playtools), [plugins](#plugins)).

## Output, exit codes and scripting

- Command results go to **stdout**; progress, warnings and errors go to **stderr**. Internal log lines from the
  PlayCover code are hidden unless `--verbose` is given (then they go to stderr), so stdout stays parseable.
- `--json` (`list`, `info`, `devices`, `settings show`) prints pretty, key-sorted JSON.

| Exit code | Meaning |
| --- | --- |
| `0` | Success |
| `1` | The command failed (app not found, install failed, signing error, …) |
| `2` | Usage error (unknown option, bad value, missing argument, confirmation required) |
| `128 + n` | Interrupted by signal *n* while waiting (e.g. `130` for Ctrl-C); settings were restored first |

```bash
# Every installed bundle id
playcover list --json | jq -r '.[].bundleIdentifier'

# Switch every installed app to report as an M5 iPad Pro
playcover list --json | jq -r '.[].bundleIdentifier' | while read -r id; do
  playcover settings set "$id" --device ipad-pro-13-m5
done

# Is keymapping on?
playcover settings show com.example.game --json | jq .keymapping
```

## KeyCover and PlayChain

When KeyCover encrypts an app's PlayChain, `launch` unlocks it before starting the app and locks it again after
the app quits (so the CLI waits in that case):

- **Self-generated password** (the default): the key is read from your login keychain, nothing to type.
- **Your own master password**: you are prompted for it in the terminal (input hidden). In scripts, pipe it in with
  `--keycover-password-stdin`, e.g. `security find-generic-password -w -s my-keycover | playcover launch … --keycover-password-stdin`.
  Avoid putting the password itself on the command line.
- Without a usable password, PlayChain is disabled for that launch only (as in the GUI) and a warning is printed.

## Permissions and troubleshooting

- **"Could not move … to the Trash"** (`clear --data`, `uninstall --data`): macOS protects
  `~/Library/Containers`. Give your terminal app **Full Disk Access** (System Settings › Privacy & Security), or
  delete the folder yourself.
- **Keychain prompt "PlayCover wants to use … in your keychain"** on `launch`: appears when the PlayCover binary is
  not the one that stored the KeyCover key, typically a build you made yourself. Choose *Always Allow*; release
  builds do not ask.
- **"PlayTools are not installed! Please move PlayCover.app into Applications!"**: run PlayCover from
  `/Applications` (or `~/Applications`) once.
- **"… is running. Quit it first."**: `clear` and `uninstall` refuse to touch a running app.
- Commands run as your user, read the same files as the PlayCover window and can be used while it is open. Avoid
  editing the same app's settings in the window and the CLI at the same time: the last write wins.
