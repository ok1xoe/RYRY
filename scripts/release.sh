#!/bin/zsh
# Vydání pro distribuci mimo App Store přes účet přihlášený v Xcode (cloudový certifikát Developer ID):
#   1. make-app.sh → build/mmtty4mac.app
#   2. .xcarchive + xcodebuild -exportArchive (developer-id, destination upload) → podpis Developer ID a odeslání k notarizaci
#   3. čekání na notarizaci, xcodebuild -exportNotarizedApp → build/notarized/mmtty4mac.app (s lístkem)
#   4. kontrola (stapler, spctl) a DMG build/mmtty4mac-<verze>.dmg
# Bez hesel: používá účet v Xcode → Settings → Accounts. TEAM_ID lze přepsat proměnnou.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
TEAM_ID="${TEAM_ID:-GN8G426WK4}"
./scripts/make-app.sh
APP=build/mmtty4mac.app
V=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
B=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")
A=build/mmtty4mac.xcarchive
rm -rf "$A" build/export-upload build/notarized
mkdir -p "$A/Products/Applications"
cp -R "$APP" "$A/Products/Applications/"
cat > "$A/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>ApplicationProperties</key><dict>
    <key>ApplicationPath</key><string>Applications/mmtty4mac.app</string>
    <key>Architectures</key><array><string>$(uname -m)</string></array>
    <key>CFBundleIdentifier</key><string>cz.ok1xoe.mmtty4mac</string>
    <key>CFBundleShortVersionString</key><string>$V</string>
    <key>CFBundleVersion</key><string>$B</string>
    <key>Team</key><string>$TEAM_ID</string>
  </dict>
  <key>ArchiveVersion</key><integer>2</integer>
  <key>CreationDate</key><date>$(date -u +%Y-%m-%dT%H:%M:%SZ)</date>
  <key>Name</key><string>mmtty4mac</string>
  <key>SchemeName</key><string>mmtty4mac</string>
</dict></plist>
PL
OPTS=build/export-devid-upload.plist
cat > "$OPTS" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>destination</key><string>upload</string>
</dict></plist>
PL
echo "Podpis Developer ID a odeslání k notarizaci…"
xcodebuild -exportArchive -archivePath "$A" -exportOptionsPlist "$OPTS" -exportPath build/export-upload \
    -allowProvisioningUpdates -quiet
echo "Čekám na notarizaci…"
for i in {1..40}; do
    if xcodebuild -exportNotarizedApp -archivePath "$A" -exportPath build/notarized -quiet 2>/dev/null; then break; fi
    (( i == 40 )) && { echo "Notarizace nedokončena (zkontrolujte Xcode → Window → Organizer)" >&2; exit 1; }
    sleep 30
done
xcrun stapler validate build/notarized/mmtty4mac.app
spctl -a -vv -t execute build/notarized/mmtty4mac.app
SKIP_BUILD=1 APP=build/notarized/mmtty4mac.app ./scripts/make-dmg.sh

# Appcast pro kontrolu aktualizací (docs/distribution.md): build/appcast.json.
# UPDATE_BASE_URL=https://example.com/mmtty4mac → url = <BASE>/mmtty4mac-<verze>.dmg (bez ní se pole url vynechá).
# Volitelně RELEASE_NOTES_CS / RELEASE_NOTES_EN. Chyba tady vydání nepokazí (DMG je už hotové).
DMG="build/mmtty4mac-$V.dmg"
if [[ -f "$DMG" ]]; then
    SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')
    MINOS=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist" 2>/dev/null || echo "")
    V="$V" B="$B" SHA="$SHA" MINOS="$MINOS" python3 - <<'PY' || echo "Appcast se nepodařilo vytvořit (DMG je v pořádku)" >&2
import json, os
e = os.environ
latest = {"version": e["V"]}
if e["B"].isdigit(): latest["build"] = int(e["B"])      # nečíselné číslo sestavení vynechat (appcast čte build jako číslo)
base = e.get("UPDATE_BASE_URL", "").rstrip("/")
if base:
    latest["url"] = f"{base}/mmtty4mac-{e['V']}.dmg"
notes = {k: e[v] for k, v in (("cs", "RELEASE_NOTES_CS"), ("en", "RELEASE_NOTES_EN")) if e.get(v)}
if notes:
    latest["notes"] = notes
if e.get("MINOS"):
    latest["minimumSystemVersion"] = e["MINOS"]
latest["sha256"] = e["SHA"]
with open("build/appcast.json", "w", encoding="utf-8") as f:
    json.dump({"latest": latest}, f, ensure_ascii=False, indent=2)
    f.write("\n")
PY
    [[ -f build/appcast.json ]] && echo "Appcast: build/appcast.json"
    [[ -z "${UPDATE_BASE_URL:-}" ]] && echo "UPDATE_BASE_URL není nastavená – v appcastu chybí url (doplňte ručně)" >&2
fi
exit 0
