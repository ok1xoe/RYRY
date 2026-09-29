#!/bin/zsh
# Sestaví build/mmtty4mac.app (release) a podepíše ho.
#
# Podpis (SIGN_ID):
#   nenastaveno → „Developer ID Application“, jinak „Apple Development“ z klíčenky, jinak ad-hoc.
#                 Se stabilním podpisem si macOS pamatuje povolení mikrofonu i po novém sestavení.
#   SIGN_ID=-   → ad-hoc (macOS se na mikrofon zeptá po každém sestavení).
#   SIGN_ID="Developer ID Application: …" → konkrétní identita.
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
cp Resources/cty.dat "$APP/Contents/Resources/"      # DXCC (AD1C country file)
cp -R Resources/Languages "$APP/Contents/Resources/"   # jazyky rozhraní (JSON)
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
# číslo sestavení = počet commitů
BUILD_NO=$(git rev-list --count HEAD 2>/dev/null || echo 1)
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NO" "$APP/Contents/Info.plist"

# Identita podle SHA-1 (codesign podle jména s diakritikou/e-mailem identitu někdy nenajde).
ID_NAME="ad-hoc"; ID="-"
if [[ -n "${SIGN_ID:-}" ]]; then
    ID="$SIGN_ID"; ID_NAME="$SIGN_ID"
else
    IDS=$(security find-identity -v -p codesigning 2>/dev/null || true)
    for kind in "Developer ID Application" "Apple Development"; do
        LINE=$(print -r -- "$IDS" | grep -m1 "\"$kind" || true)
        if [[ -n "$LINE" ]]; then
            ID=$(print -r -- "$LINE" | awk '{print $2}')
            ID_NAME=$(print -r -- "$LINE" | sed -E 's/.*"(.*)"/\1/')
            break
        fi
    done
fi
if [[ "$ID" == "-" ]]; then
    codesign --force --sign - --entitlements Resources/mmtty4mac.entitlements --options runtime "$APP"
elif [[ "$ID_NAME" == Developer\ ID* ]]; then   # pro notarizaci: hardened runtime + časové razítko
    codesign --force --sign "$ID" --entitlements Resources/mmtty4mac.entitlements --options runtime --timestamp "$APP"
else
    codesign --force --sign "$ID" --entitlements Resources/mmtty4mac.entitlements --options runtime "$APP"
fi
echo "Podpis: $ID_NAME"
echo "Hotovo: $APP (verze $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist") ($BUILD_NO))"
