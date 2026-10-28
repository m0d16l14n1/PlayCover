# Building PlayCover

PlayCover is an AppKit/SwiftUI macOS app (deployment target macOS 12) that embeds the
[PlayTools](https://github.com/m0d16l14n1/PlayTools) framework, built with Carthage as a Mac Catalyst
xcframework.

## Supported toolchains

| macOS | Xcode | Status |
| --- | --- | --- |
| 27 | 27.1 | Verified locally on macOS 27.2: PlayTools and PlayCover (Release and Nightly) build, SwiftLint clean |
| 26 Tahoe | 26.x | Built by CI (`Build check` workflow, Xcode 26.6 on `macos-26`) |
| 15 Sequoia | 16.x | Built by CI (`Build check` workflow, Xcode 16.4 on `macos-15`) |

GitHub-hosted runners do not offer macOS 27 yet. Once they do, add a `macos-27` entry to the matrix in
`.github/workflows/build-check.yml` (here and in PlayTools).

What was needed for the macOS 27 SDK:

- **PlayTools**: `VSSubscription` is marked unavailable on Mac Catalyst in the macOS 27 SDK, which broke
  `NSObject+Swizzle.m`. The hook now takes `id`; the class is still resolved at runtime, so behaviour is unchanged
  and older SDKs build as before.
- **PlayCover**: the *Codesign sparkle* build phase passed `EXPANDED_CODE_SIGN_IDENTITY_NAME` to `codesign`. For
  *Sign to Run Locally* that is a display name codesign cannot resolve, so builds without a developer team failed.
  It now uses `EXPANDED_CODE_SIGN_IDENTITY` (the certificate hash, or `-` for ad-hoc) and skips signing when
  `CODE_SIGNING_ALLOWED=NO`.

## Requirements

- An Apple Silicon Mac
- Xcode (see the table above), opened once so it can install its components
- [Homebrew](https://brew.sh) packages:

```bash
brew install carthage swiftlint
```

SwiftLint runs as a build phase in both projects and fails the build when it is missing.

## 1. Build PlayTools

`Cartfile` points at the PlayTools fork branch that matches this PlayCover branch:

```
github "m0d16l14n1/PlayTools" "feature/new-devices-and-tahoe-27"
```

Build it into `Carthage/Build/PlayTools.xcframework`:

```bash
carthage update --use-xcframeworks
```

To work on PlayTools and PlayCover side by side, point the Cartfile at your local checkout instead (commit
your PlayTools changes first: Carthage builds the committed branch):

```
git "file:///Users/you/Documents/GitHub/PlayTools" "feature/new-devices-and-tahoe-27"
```

Re-run `carthage update --use-xcframeworks` after every PlayTools change.

## 2. Build PlayCover

The project has two configurations, **Release** and **Nightly** (there is no Debug configuration).

### In Xcode

Open `PlayCover.xcodeproj`, select the **PlayCover** scheme and press ⌘B / ⌘R. Without the PlayCover team's
Developer ID certificate, set *Signing & Capabilities › Team* to your own team, or to *None* with
*Sign to Run Locally*.

### From the command line (no Apple developer account needed)

```bash
xcodebuild -scheme PlayCover -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath build \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= \
  ENABLE_HARDENED_RUNTIME=NO \
  build
```

The app is written to `build/Build/Products/Release/PlayCover.app`. Copy it to `/Applications` before use:
PlayCover installs PlayTools system-wide from its own bundle and expects to live in an Applications folder.

`ENABLE_HARDENED_RUNTIME=NO` is required for ad-hoc builds: with the hardened runtime on, library validation
refuses to load the ad-hoc signed Sparkle framework ("different Team IDs") and PlayCover exits at launch.
Release builds signed with a Developer ID keep the hardened runtime.

An ad-hoc build has a different code signature from an installed release, so the first time it reads the KeyCover
key macOS asks for keychain access; choose *Always Allow*.

### Release builds (maintainers)

`fastlane release` / `fastlane nightly` (see `fastlane/Fastfile`) run Carthage and build with the Developer ID
certificate from `match`. They are unchanged.

## 3. Check the build

```bash
APP=build/Build/Products/Release/PlayCover.app/Contents/MacOS/PlayCover
"$APP" version
"$APP" devices
"$APP" list
```

See [CLI.md](CLI.md) for everything the command line interface can do.

## Continuous integration

`.github/workflows/build-check.yml` builds PlayTools via Carthage and PlayCover (ad-hoc signed) on every push and
pull request with Xcode 16.4 (macOS 15) and Xcode 26.6 (macOS 26), then smoke-tests the CLI. PlayTools has a
matching workflow that builds the framework for Mac Catalyst. The existing release, nightly and SwiftLint
workflows are unchanged.
