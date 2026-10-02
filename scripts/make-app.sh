#!/bin/zsh
# Sestaví build/RYRY.app (RYRY, release, App Sandbox) a podepíše ho pro vývoj.
# Pro App Store: scripts/release-appstore.sh (volá tento skript a znovu podepíše certifikátem Apple Distribution).
#
# Podpis (SIGN_ID):
#   nenastaveno → „Apple Development“ z klíčenky, jinak ad-hoc.
#                 Se stabilním podpisem si macOS pamatuje povolení mikrofonu i po novém sestavení.
#   SIGN_ID=-   → ad-hoc (macOS se na mikrofon zeptá po každém sestavení).
#   SIGN_ID=<SHA-1 nebo název> → konkrétní identita.
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
    swift build -c release --arch "$a" --product RYRY
    PARTS+=("$(swift build -c release --arch "$a" --show-bin-path)/RYRY")
done
BIN=build/RYRY.universal
mkdir -p build
lipo -create "${PARTS[@]}" -output "$BIN"
APP=build/RYRY.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/RYRY"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp COPYING COPYING.LESSER "$APP/Contents/Resources/"
cp Resources/cty.dat "$APP/Contents/Resources/"      # DXCC (AD1C country file)
cp Resources/container-migration.plist "$APP/Contents/Resources/"   # přechod nastavení z DMG verze do sandboxu
cp Resources/demo-rtty.wav "$APP/Contents/Resources/"   # ukázkový signál (Nápověda → Přehrát ukázkový signál)
cp -R Resources/Languages "$APP/Contents/Resources/"   # jazyky rozhraní (JSON)
rm -rf "$APP/Contents/Resources/Help"; cp -R docs/html "$APP/Contents/Resources/Help"   # příručka (Nápověda)
# ikona: formát macOS 26 (Resources/AppIcon.icon → Assets.car + záložní AppIcon.icns přes actool), jinak jen .icns
if ! xcrun actool Resources/AppIcon.icon --compile "$APP/Contents/Resources" --platform macosx --minimum-deployment-target 14.0 \
        --app-icon AppIcon --output-partial-info-plist build/icon-partial.plist >/dev/null 2>&1; then
    echo "actool neumí .icon – použita jen Resources/AppIcon.icns"
    cp Resources/AppIcon.icns "$APP/Contents/Resources/"
fi
# číslo sestavení = počet commitů
BUILD_NO=$(git rev-list --count HEAD 2>/dev/null || echo 1)
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NO" "$APP/Contents/Info.plist"

# Identita podle SHA-1 (codesign podle jména s diakritikou/e-mailem identitu někdy nenajde).
ID_NAME="ad-hoc"; ID="-"
if [[ -n "${SIGN_ID:-}" ]]; then
    ID="$SIGN_ID"; ID_NAME="$SIGN_ID"
else
    IDS=$(security find-identity -v -p codesigning 2>/dev/null || true)
    for kind in "Apple Development"; do
        LINE=$(print -r -- "$IDS" | grep -m1 "\"$kind" || true)
        if [[ -n "$LINE" ]]; then
            ID=$(print -r -- "$LINE" | awk '{print $2}')
            ID_NAME=$(print -r -- "$LINE" | sed -E 's/.*"(.*)"/\1/')
            break
        fi
    done
fi
# Vývojový podpis se sandboxem; pro App Store aplikaci znovu podepíše release-appstore.sh (Apple Distribution).
codesign --force --sign "$ID" --entitlements Resources/RYRY.entitlements --options runtime "$APP"
echo "Podpis: $ID_NAME"
echo "Hotovo: $APP (verze $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist") ($BUILD_NO))"
