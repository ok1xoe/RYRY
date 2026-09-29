#!/bin/zsh
# Sestaví build/mmtty4mac.app (release, ad-hoc podpis).
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
swift build -c release --product MMTTY4MacApp
BIN="$(swift build -c release --show-bin-path)/MMTTY4MacApp"
APP=build/mmtty4mac.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MMTTY4MacApp"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp COPYING COPYING.LESSER "$APP/Contents/Resources/"
codesign --force --sign - --entitlements Resources/mmtty4mac.entitlements --options runtime "$APP"
echo "Hotovo: $APP"
