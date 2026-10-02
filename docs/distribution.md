# Distribuce RYRY (Mac App Store)

Aplikace se od verze 1.0.0 distribuuje **jen přes Mac App Store** pod jménem **RYRY**. DMG s notarizací a vlastní
kontrola aktualizací skončily (App Store aktualizuje sám a vlastní aktualizace nedovoluje). Rozhodnutí a jejich
důvody jsou v `docs/rulings.md` a `docs/superpowers/specs/2026-09-30-app-store-ryry-design.md`.

## Vývojové sestavení

    ./scripts/make-app.sh                  # build/RYRY.app, univerzální (arm64 + x86_64)
    MMTTY_ARCHS=arm64 ./scripts/make-app.sh   # rychleji, jen Apple Silicon

Aplikace vždy běží v **App Sandbox** s oprávněními z `Resources/RYRY.entitlements`. Podpis je
**Apple Development** z klíčenky (macOS si pak pamatuje povolení mikrofonu), `SIGN_ID=-` podepíše ad-hoc.
Verze se bere z `Resources/Info.plist` (`CFBundleShortVersionString`), číslo sestavení je počet commitů.

Skript do balíčku přidá:
- ikonu: `Resources/AppIcon.icon` přeloženou přes `actool` do `Assets.car` se záložní `AppIcon.icns`,
- `cty.dat`, jazyky a příručku (`docs/html` → `Help`),
- ukázkový signál `demo-rtty.wav`,
- `container-migration.plist`.

## Vydání do App Store

    TEAM_ID=GN8G426WK4 ./scripts/release-appstore.sh                # sestavit, podepsat a nahrát
    TEAM_ID=GN8G426WK4 ./scripts/release-appstore.sh --export-only  # jen build/appstore/*.pkg

Skript sestaví univerzální aplikaci, zabalí ji do `.xcarchive` a zavolá `xcodebuild -exportArchive` s
`method=app-store-connect`. Xcode pod účtem týmu vytvoří profil, podepíše certifikátem **Apple Distribution**,
vytvoří instalační balíček a nahraje ho (`destination=upload`). Hesla ani klíče skript nepotřebuje, stačí účet
v Xcode.

### Jednorázová příprava

1. **Xcode → Settings → Accounts:** přihlásit Apple ID týmu `GN8G426WK4`. Když `xcodebuild` hlásí
   `No Accounts` nebo `missing Xcode-Token`, přihlášení vypršelo nebo je zamčená klíčenka: odemknout Mac,
   v Accounts se přihlásit znovu.
2. **App Store Connect → Aplikace → „+“ → Nová aplikace:**
   - platforma macOS,
   - název `RYRY – RTTY for Contests`,
   - primární jazyk angličtina,
   - bundle ID `cz.ok1xoe.ryry` (pokud v nabídce chybí, zaregistrovat ho v Certificates, Identifiers &
     Profiles → Identifiers, nebo ho vytvoří první `release-appstore.sh`),
   - SKU třeba `RYRY-MAC`.
3. **Chyba `No profiles for 'cz.ok1xoe.ryry' were found`** znamená, že Xcode nemohl profil vytvořit, protože
   neměl účet (viz bod 1). Po přihlášení ho `-allowProvisioningUpdates` vytvoří sám.

Postup odeslání, texty, snímky a odpovědi pro App Store Connect jsou v `docs/appstore/README.md`.

## Co v App Store verzi není a proč

| Funkce | Proč | Náhrada |
|---|---|---|
| Aplikace sama spouští rigctld (hamlib) | Sandbox nedovolí spustit cizí program. | rigctld spuštěný uživatelem (TCP 127.0.0.1:4532), flrig, vestavěný CAT |
| LoTW přes program tqsl na pozadí | Sandbox nedovolí spustit tqsl. | ADIF se uloží do Stažených souborů a otevře v TrustedQSL, uživatel potvrdí odeslání |
| Kontrola aktualizací a stažení DMG | App Store vlastní aktualizace zakazuje. | aktualizace přes App Store |
| Log kdekoli bez ptaní | Sandbox pustí aplikaci jen do složek, které uživatel vybral. | složka se vybere jednou, přístup se pamatuje (security-scoped bookmark) |

## Přechod z DMG verze

`container-migration.plist` zajistí, že se při prvním spuštění App Store verze přesune
`~/Library/Application Support/mmtty4mac` (případně `…/RYRY` z `rtty-tool`) a předvolby do kontejneru sandboxu
`cz.ok1xoe.ryry`; aplikace pak složku `mmtty4mac` přejmenuje na `RYRY` a převezme předvolby z domény
`cz.ok1xoe.mmtty4mac` (`AppSupport.migrateLegacy`). Vývojový kontejner `cz.ok1xoe.mmtty4mac` (bundle ID do
verze 1.0, App Store ho nikdy nevydal) se nepřenáší. Log mimo kontejner si
aplikace vyžádá dialogem s předvybranou složkou. Hesla v Klíčence je nejspíš potřeba zadat znovu, protože se
změnil podpis. Podrobnosti a omezení (migrace proběhne jen při vzniku kontejneru) jsou v
`docs/appstore/sandbox-check.md`.

## Poznámky

- **Oprávnění sandboxu:** mikrofon, sériová zařízení, síťový klient i server (API na 127.0.0.1), soubory
  vybrané uživatelem, bookmarky a složka Stažené soubory.
- **Přibalená data:** `cty.dat` (AD1C) je v `Contents/Resources`. Novější verzi jde dát do
  `~/Library/Containers/cz.ok1xoe.ryry/Data/Library/Application Support/RYRY/cty.dat`.
