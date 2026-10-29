#!/bin/sh
# Builds AutoTest.ipa, a small iOS app for trying and testing 'playcover automate':
# a UIKit button with a counter, a text field, a swipe/long-press pad and a SwiftUI button, each of which shows
# what happened as text that 'find' can read back.
#
#   scripts/automation-fixture/build.sh                 # writes build/AutoTest.ipa
#   playcover install build/AutoTest.ipa --automation
#   playcover launch AutoTest
#   playcover automate AutoTest run scripts/automation-fixture/flow.txt
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$HERE/../../build}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

APP="$WORK/Payload/AutoTest.app"
mkdir -p "$APP" "$OUT"
xcrun -sdk iphoneos swiftc -target arm64-apple-ios15.0 -O -o "$APP/AutoTest" "$HERE/main.swift"
cp "$HERE/Info.plist" "$APP/Info.plist"
(cd "$WORK" && ditto -c -k --norsrc --keepParent Payload AutoTest.ipa)
mv "$WORK/AutoTest.ipa" "$OUT/AutoTest.ipa"
echo "Built $OUT/AutoTest.ipa"
