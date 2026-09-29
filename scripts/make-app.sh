#!/bin/zsh
# Sestaví build/mmtty4mac.app (release) a podepíše ho.
#
# Podpis (SIGN_ID):
#   nenastaveno → „Developer ID Application“, jinak „Apple Development“ z klíčenky, jinak ad-hoc.
#                 Se stabilním podpisem si macOS pamatuje povolení mikrofonu i po novém sestavení.
#   SIGN_ID=-   → ad-hoc (macOS se na mikrofon zeptá po každém sestavení).
#   SIGN_ID="Developer ID Application: …" → konkrétní identita.
#
# Architektury (MMTTY_ARCHS): výchozí „arm64 x86_64“ = univerzální aplikace (Apple Silicon i Intel, lipo).
#   MMTTY_ARCHS=arm64 → rychlé sestavení jen pro Apple Silicon (vývoj).
#   (Ne ARCHS – tu exportuje Xcode a skript spuštěný z jeho build fáze by ji převzal.)
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
ARCH_LIST=(${=MMTTY_ARCHS:-arm64 x86_64})
PARTS=()
for a in $ARCH_LIST; do
    swift build -c release --arch "$a" --product MMTTY4MacApp
    PARTS+=("$(swift build -c release --arch "$a" --show-bin-path)/MMTTY4MacApp")
done
BIN=build/MMTTY4MacApp.universal
mkdir -p build
lipo -create "${PARTS[@]}" -output "$BIN"
APP=build/mmtty4mac.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MMTTY4MacApp"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp COPYING COPYING.LESSER "$APP/Contents/Resources/"
cp Resources/cty.dat "$APP/Contents/Resources/"      # DXCC (AD1C country file)
cp -R Resources/Languages "$APP/Contents/Resources/"   # jazyky rozhraní (JSON)
rm -rf "$APP/Contents/Resources/Help"; cp -R docs/html "$APP/Contents/Resources/Help"   # příručka (Nápověda)
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
