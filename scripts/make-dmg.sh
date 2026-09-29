#!/bin/zsh
# Sestaví build/mmtty4mac-<verze>.dmg (aplikace + odkaz na /Applications + licence a návod).
#
#   ./scripts/make-dmg.sh                         # sestaví aplikaci i DMG
#   SKIP_BUILD=1 ./scripts/make-dmg.sh            # použije existující build/mmtty4mac.app
#   NOTARY_PROFILE=mmtty4mac ./scripts/make-dmg.sh
#       → navíc notarizace (xcrun notarytool, profil z `xcrun notarytool store-credentials`) a staple.
#         Vyžaduje podpis „Developer ID Application“ (viz docs/distribution.md).
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -n "${SKIP_BUILD:-}" ]] || ./scripts/make-app.sh
APP="${APP:-build/mmtty4mac.app}"
VER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
STAGE=build/dmg
DMG="build/mmtty4mac-$VER.dmg"
rm -rf "$STAGE" "$DMG"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp README.md COPYING COPYING.LESSER "$STAGE/"
cp docs/prirucka.md "$STAGE/Příručka.md"; cp docs/manual.md "$STAGE/Manual.md"
hdiutil create -volname "mmtty4mac $VER" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

SIGNER=$(codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=//p' | head -1)
# DMG podepsat jen lokálním klíčem Developer ID (cloudový z Xcode lokálně není – pak zůstane nepodepsané;
# aplikace uvnitř je notarizovaná s lístkem, to Gatekeeperu stačí)
HASH=$(security find-identity -v -p codesigning | grep -m1 "\"$SIGNER\"" | awk '{print $2}' || true)
if [[ "$SIGNER" == Developer\ ID* && -n "$HASH" ]]; then
    codesign --force --sign "$HASH" --timestamp "$DMG"
fi
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    [[ "$SIGNER" == Developer\ ID* && -n "$HASH" ]] || { echo "Notarizace DMG přes notarytool vyžaduje lokální klíč Developer ID (s účtem v Xcode použijte scripts/release.sh)" >&2; exit 1; }
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    spctl -a -t open --context context:primary-signature -v "$DMG" || true
fi
echo "Hotovo: $DMG (podpis aplikace: ${SIGNER:-ad-hoc})"
