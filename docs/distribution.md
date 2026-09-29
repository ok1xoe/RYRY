# Distribuce mmtty4mac

## Sestavení

    ./scripts/make-app.sh      # build/mmtty4mac.app
    ./scripts/make-dmg.sh      # build/mmtty4mac-<verze>.dmg

`make-app.sh` podepisuje automaticky. Přednost má **Developer ID Application**, jinak **Apple Development** z klíčenky.
Se stabilním podpisem si macOS pamatuje povolení mikrofonu i po novém sestavení.

- `SIGN_ID=-` podepíše ad-hoc; macOS se pak na mikrofon zeptá po každém sestavení.
- `SIGN_ID=<SHA-1 nebo název>` použije zadanou identitu.

Verze se bere z `Resources/Info.plist` (`CFBundleShortVersionString`). Číslo sestavení je počet commitů.

## Distribuce mimo App Store (notarizace)

Aplikace podepsaná certifikátem Apple Development běží jen na tvém Macu. Aby ji Gatekeeper pustil i na jiných Macích,
potřebuje podpis **Developer ID Application** a notarizaci.

1. **Certifikát Developer ID Application** (jednorázově):
   Xcode → Settings → Accounts → tým *TOMÁS KAPLAN (GN8G426WK4)* → Manage Certificates… → „+“ → *Developer ID Application*.
   Založit ho smí jen Account Holder týmu.
2. **Profil pro notarytool** (jednorázově). Heslo je app-specific password z appleid.apple.com, uloží se do klíčenky:

       xcrun notarytool store-credentials mmtty4mac --apple-id <apple-id> --team-id GN8G426WK4

3. **Vydání:**

       NOTARY_PROFILE=mmtty4mac ./scripts/make-dmg.sh

   Skript sestaví a podepíše aplikaci (Developer ID, hardened runtime, časové razítko). Pak podepíše DMG,
   odešle ho k notarizaci, připojí lístek (staple) a ověří ho přes `spctl`.

## Poznámky

- **Oprávnění (entitlements):** jen `com.apple.security.device.audio-input`. Aplikace není v sandboxu, protože potřebuje sériové porty a TCP pro rigctld/flrig a API.
- **Mac App Store:** nepodporováno. Sandbox by vyžadoval výjimky pro sériové porty a síťový server API.
- **Přibalená data:** `cty.dat` (AD1C) je v `Contents/Resources`. Vlastní novější verze se dá do `~/Library/Application Support/mmtty4mac/cty.dat`.
