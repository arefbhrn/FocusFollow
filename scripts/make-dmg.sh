#!/usr/bin/env bash
# Builds a Release FocusFollow.app (Apple silicon) and packs it into a DMG.
# Needs Xcode and create-dmg (brew install create-dmg). The window background comes from make-dmg-background.swift.
# Usage: scripts/make-dmg.sh [output-dir]   (default: ./dist)
set -euo pipefail

# Resolve the output directory before changing into the repo root.
out="${1:-}"
if [ -n "$out" ]; then
  out="$(mkdir -p "$out" && cd "$out" && pwd)"
fi
cd "$(dirname "$0")/.."
out="${out:-$PWD/dist}"

build="$(mktemp -d)"
stage="$(mktemp -d)"
art="$(mktemp -d)"
trap 'rm -rf "$build" "$stage" "$art"' EXIT

command -v create-dmg >/dev/null || { echo "create-dmg not found: brew install create-dmg" >&2; exit 1; }

log="$build/xcodebuild.log"
if ! xcodebuild -project FocusFollow.xcodeproj -scheme FocusFollow -configuration Release \
  -derivedDataPath "$build" ARCHS=arm64 ONLY_ACTIVE_ARCH=NO -allowProvisioningUpdates build >"$log" 2>&1; then
  grep -E "error:" "$log" >&2 || tail -50 "$log" >&2
  echo "Build failed" >&2
  exit 1
fi

app="$build/Build/Products/Release/FocusFollow.app"
[ -d "$app" ] || { echo "Build produced no app at $app" >&2; exit 1; }

version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")"
dmg="$out/FocusFollow-$version-arm64.dmg"
mkdir -p "$out"
rm -f "$dmg"

cp -R "$app" "$stage/"

# Background with an arrow from the app to Applications, as a 1x + 2x TIFF so it is sharp on Retina.
swift scripts/make-dmg-background.swift "$art" >/dev/null
# tiffutil only warns when the 1x and 2x images don't match, so treat any warning as a failure.
# Its normal "images written" note also goes to stderr, hence the filter.
output="$(tiffutil -cathidpicheck "$art/background.png" "$art/background@2x.png" -out "$art/background.tiff" 2>&1 >/dev/null)" \
  || { echo "$output" >&2; exit 1; }
warnings="$(printf '%s\n' "$output" | grep -v 'images written' || true)"
[ -z "$warnings" ] || { echo "$warnings" >&2; exit 1; }

create-dmg --volname "FocusFollow $version" --background "$art/background.tiff" \
  --window-size 540 380 --icon-size 100 \
  --icon "FocusFollow.app" 140 180 --app-drop-link 400 180 --no-internet-enable \
  "$dmg" "$stage"

echo "Built $dmg"
shasum -a 256 "$dmg"
