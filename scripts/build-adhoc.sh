#!/bin/sh
# Builds PlayCover without an Apple developer account (ad-hoc signed).
#
# usage: scripts/build-adhoc.sh [Release|Nightly] [derived data path]
#
# The app is written to <derived data path>/Build/Products/<configuration>/PlayCover.app (default: build/...).
# The Bootstrap carthage build phase runs 'carthage update' first, so PlayTools is built as part of this.
#
# Keychain note: an ad-hoc signed app is identified to the keychain by the hash of that exact build, so every
# rebuild asks again before it can read the KeyCover key ("Always Allow" only covers the build that was running).
# Signing with an Apple Development certificate, even from a free personal team, gives a stable Team ID and
# avoids that; see docs/BUILDING.md.
set -eu

CONFIGURATION="${1:-Release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="${2:-$ROOT/build}"

# ENABLE_HARDENED_RUNTIME=NO: library validation would refuse the ad-hoc signed Sparkle framework
xcodebuild -project "$ROOT/PlayCover.xcodeproj" -scheme PlayCover -configuration "$CONFIGURATION" \
    -destination 'generic/platform=macOS' -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= \
    ENABLE_HARDENED_RUNTIME=NO \
    build

echo "Built $DERIVED_DATA/Build/Products/$CONFIGURATION/PlayCover.app"
