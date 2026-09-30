#!/bin/zsh
# Sestaví RYRY a nahraje ho do App Store Connect (s --export-only jen vytvoří podepsaný .pkg bez nahrání).
#
# Potřebuje: Xcode přihlášené k účtu týmu (Settings → Accounts), TEAM_ID v prostředí
# a založenou aplikaci v App Store Connect (bundle ID cz.ok1xoe.mmtty4mac). Hesla ani lokální klíče nejsou potřeba:
# Xcode podepíše cloudovým certifikátem Apple Distribution a profil vytvoří sám (-allowProvisioningUpdates).
#
#   TEAM_ID=XXXXXXXXXX ./scripts/release-appstore.sh               # sestavit a nahrát
#   TEAM_ID=XXXXXXXXXX ./scripts/release-appstore.sh --export-only # jen build/appstore/RYRY.pkg
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
[[ -n "${TEAM_ID:-}" ]] || { echo "TEAM_ID není nastavené (developer.apple.com → Membership)." >&2; exit 1; }
DEST=upload; [[ "${1:-}" == "--export-only" ]] && DEST=export
./scripts/make-app.sh                                  # univerzální (arm64 + x86_64), sandbox, podpis Apple Development
APP=build/mmtty4mac.app
V=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
B=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")
A=build/RYRY.xcarchive
rm -rf "$A" build/appstore; mkdir -p "$A/Products/Applications"
cp -R "$APP" "$A/Products/Applications/"
cat > "$A/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>ApplicationProperties</key><dict>
    <key>ApplicationPath</key><string>Applications/mmtty4mac.app</string>
    <key>Architectures</key><array><string>arm64</string><string>x86_64</string></array>
    <key>CFBundleIdentifier</key><string>cz.ok1xoe.mmtty4mac</string>
    <key>CFBundleShortVersionString</key><string>$V</string>
    <key>CFBundleVersion</key><string>$B</string>
    <key>Team</key><string>$TEAM_ID</string>
  </dict>
  <key>ArchiveVersion</key><integer>2</integer>
  <key>CreationDate</key><date>$(date -u +%Y-%m-%dT%H:%M:%SZ)</date>
  <key>Name</key><string>RYRY</string>
  <key>SchemeName</key><string>RYRY</string>
</dict></plist>
PL
OPTS=build/export-appstore.plist
cat > "$OPTS" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>destination</key><string>$DEST</string>
</dict></plist>
PL
echo "Podpis pro App Store ($DEST)…"
xcodebuild -exportArchive -archivePath "$A" -exportOptionsPlist "$OPTS" -exportPath build/appstore -allowProvisioningUpdates
if [[ "$DEST" == export ]]; then
    PKG=$(ls build/appstore/*.pkg)
    echo "Balíček: $PKG"
    pkgutil --check-signature "$PKG" | head -4 || true
else
    echo "Nahráno $V ($B). Pokračuj v App Store Connect → TestFlight / Distribuce."
fi
