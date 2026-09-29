# Distribuce mmtty4mac

## Sestavení

    ./scripts/make-app.sh      # build/mmtty4mac.app
    ./scripts/make-dmg.sh      # build/mmtty4mac-<verze>.dmg

`make-app.sh` podepisuje automaticky. Přednost má **Developer ID Application**, jinak **Apple Development** z klíčenky.
Se stabilním podpisem si macOS pamatuje povolení mikrofonu i po novém sestavení.

- `SIGN_ID=-` podepíše ad-hoc; macOS se pak na mikrofon zeptá po každém sestavení.
- `SIGN_ID=<SHA-1 nebo název>` použije zadanou identitu.

Verze se bere z `Resources/Info.plist` (`CFBundleShortVersionString`). Číslo sestavení je počet commitů.

## Vydání jedním příkazem (účet v Xcode)

    ./scripts/release.sh

Skript použije účet přihlášený v Xcode, kde je tým GN8G426WK4 s cloudovým certifikátem Developer ID. Hesla ani lokální klíč nepotřebuje. Postup:
1. Sestaví a podepíše aplikaci.
2. Vytvoří `.xcarchive` a `xcodebuild -exportArchive` (method developer-id, destination upload) ji podepíše certifikátem Developer ID a odešle k notarizaci.
3. Počká na výsledek a `xcodebuild -exportNotarizedApp` vytvoří `build/notarized/mmtty4mac.app` s připojeným lístkem.
4. Ověří ji (`stapler`, `spctl`) a zabalí do `build/mmtty4mac-<verze>.dmg`.

DMG zůstane nepodepsané, protože cloudový klíč nejde použít pro `codesign`. Aplikace uvnitř je notarizovaná a Gatekeeper ji přijme.
Poprvé vyzkoušeno 2026-09-29: verze 0.9.0 (87), výsledek „accepted, source=Notarized Developer ID“.

## Distribuce mimo App Store s lokálním klíčem (notarytool)

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

## Kontrola aktualizací

Aplikace umí zjistit, že existuje novější verze, stáhnout DMG a otevřít ho. Instalaci nedělá sama: uživatel přetáhne aplikaci do Aplikací. Bez Sparkle a bez dalších knihoven (proč viz `docs/rulings.md`).

**Zdroj verzí** je adresa v klíči `MMUpdateFeedURL` v `Resources/Info.plist`. Prázdný řetězec (výchozí stav) = funkce vypnutá: automatická kontrola mlčí, ruční příkaz ukáže „Adresa aktualizací není nastavená“. Žádný síťový požadavek se pak neodešle. Formát se pozná podle tvaru adresy.

**1. Appcast** (libovolná adresa, `https`; `http` jen pro localhost):

    {"latest": {
        "version": "0.13.0",
        "build": 150,
        "url": "https://example.com/mmtty4mac-0.13.0.dmg",
        "notes": {"cs": "Co je nového…", "en": "What is new…"},
        "minimumSystemVersion": "14.0",
        "sha256": "<64 hexadecimálních znaků>"
    }}

Povinné jsou `version` (semver) a `url`. Nepovinné: `build` (rozhoduje jen při stejné verzi), `notes` (jazyk rozhraní, jinak `en`, jinak cokoli), `minimumSystemVersion` (na starším macOS se nabídne jen informace), `sha256` (stažený soubor se ověří, při neshodě se smaže).

**2. GitHub Releases API**: `https://api.github.com/repos/<vlastník>/<repozitář>/releases/latest`. Použije se `tag_name` (`v0.13.0` nebo `0.13.0`), `body` jako poznámky (pro všechny jazyky stejné), první asset `*.dmg` a jeho `digest` (`sha256:…`), pokud ho GitHub uvádí. Build číslo tu není, porovnává se jen verze.

**Porovnání:** semver (`0.10.0` > `0.9.0`, vydání > `-rc.1`); při stejné verzi vyhrává vyšší build (jen když je známý u obou).

**Chování:**
- Při startu (po spuštění enginu) se kontroluje nejvýš jednou za 24 hodin. Nastavení → Zobrazení → „Automaticky kontrolovat aktualizace“ (výchozí zapnuto, `updates.autoCheck`). Čas poslední úspěšné kontroly je v UserDefaults `updates.lastCheck`; při chybě sítě se nezapisuje.
- Menu aplikace → „Zkontrolovat aktualizace…“ ignoruje denní limit i přeskočenou verzi a vždy otevře okno s výsledkem.
- Nová verze otevře okno s poznámkami a tlačítky „Stáhnout“ (DMG do `~/Downloads`, existující soubor se nepřepíše, ověření sha256, otevření DMG přes NSWorkspace), „Později“ a „Přeskočit tuto verzi“ (UserDefaults `updates.skippedVersion`; automatická kontrola tu verzi už neohlásí, novější ano).
- Síť: časový limit 15 s na dotaz, žádné blokování hlavního vlákna.

**Vydání:** `scripts/release.sh` na konci vytvoří `build/appcast.json` (verze, build, sha256 DMG, `minimumSystemVersion`). S `UPDATE_BASE_URL=https://example.com/mmtty4mac` doplní `url` = `<BASE>/mmtty4mac-<verze>.dmg`, bez ní pole `url` vynechá (a upozorní). Volitelně `RELEASE_NOTES_CS` a `RELEASE_NOTES_EN`. Soubor `appcast.json` a DMG pak nahrajte na server a `MMUpdateFeedURL` nastavte na adresu appcastu.

**Zabezpečení:** appcast ani DMG nejsou podepsané vlastním klíčem. Integritu stažení kryje `sha256` z appcastu (to chrání před poškozením, ne před útočníkem, který ovládá server) a hlavně Gatekeeper: aplikace v DMG je podepsaná Developer ID a notarizovaná, takže podvržená aplikace se nespustí. Zdroj proto musí být `https`.

## Poznámky

- **Oprávnění (entitlements):** jen `com.apple.security.device.audio-input`. Aplikace není v sandboxu, protože potřebuje sériové porty a TCP pro rigctld/flrig a API.
- **Mac App Store:** nepodporováno. Sandbox by vyžadoval výjimky pro sériové porty a síťový server API.
- **Přibalená data:** `cty.dat` (AD1C) je v `Contents/Resources`. Vlastní novější verze se dá do `~/Library/Application Support/mmtty4mac/cty.dat`.
