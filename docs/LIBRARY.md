# Library location

PlayCover keeps its library (installed apps, their settings, keymaps, entitlements and PlayChain) in

```
~/Library/Application Support/io.playcover.PlayCover/
├── Applications/        installed apps (<bundle id>.app)
├── App Settings/        per-app settings read by PlayTools
├── Keymapping/          per-app keymaps
├── PlayChain/           emulated keychains (.db, or .keyCover when encrypted by KeyCover)
├── Entitlements/        entitlements recorded at install
├── PlayTools/           custom plugins
└── Sources.plist, CACHE, VERSION
```

The Launchpad aliases are in `~/Applications/PlayCover`.

## Why it moved

Earlier versions used `~/Library/Containers/io.playcover.PlayCover`. That folder is a protected app container: since
macOS 14, any other app that opens it makes macOS ask whether *"<app>" would like to access data from other apps*.
Every game ran from that folder and PlayTools read the game's settings, keymaps and PlayChain from it, so games
triggered the prompt. macOS only skips it for apps signed by the same developer team, which ad-hoc signed games never
are, and on macOS 26 the answer only lasts for that process, so the prompt came back at every launch.

`~/Library/Application Support` is not a container, so games no longer touch another app's data.

Launching also no longer breaks a game's code signature: PlayCover used to copy PlayTools' plugin bundle into the
game before every launch without signing it again, which left the game's code seal invalid. Now it only copies what
changed and re-signs when it did, so a game keeps the same valid identity from launch to launch, which is what macOS
privacy permissions are remembered against.

## Moving an existing library

The first time PlayCover starts after the update (the app or any `playcover` command), it moves its library over:

- Items are renamed on the same disk, never copied and deleted. Nothing already in the new library is overwritten:
  such items stay in the old folder and PlayCover says which.
- Only PlayCover's own items move. Other files in the old folder stay where they are, and so do PlayChain files of
  apps PlayCover does not know.
- Keymap configs store absolute paths; they are rewritten to the new location before any app is loaded (a config
  pointing at missing files would otherwise replace them with blank keymaps). Configs still pointing into the old
  folder are also repaired at every start.
- Every moved app is re-signed so its sandbox allows the new location, including when started from Launchpad, and
  its alias is rebuilt.
- It waits while PlayCover is open elsewhere or a game from the old folder is running, and tries again next time.

PlayTools reads the new location and falls back to the old one when the new library has no `App Settings` folder
(an older PlayCover). The old container keeps its macOS metadata file; it cannot be removed by apps and is harmless.

Going back to an older PlayCover: move the folders listed above back into `~/Library/Containers/io.playcover.PlayCover`.
