# RYRY: vydání mmtty4mac na Mac App Store (návrh)

Datum: 2026-09-30 · Stav: schváleno uživatelem („vše schvaluju“)

## Cíl

Vydat aplikaci na Mac App Store pod novým produktovým jménem **RYRY** s vylepšenou ikonou a připravit
všechno, co je k odeslání potřeba: sestavení v sandboxu, podpis a nahrání, texty a obrázky pro
App Store Connect a web produktu na `https://ryry.ok1xoe.dev`.

## Rozhodnutí uživatele

| Otázka | Rozhodnutí |
|---|---|
| Distribuce | **Jen App Store.** DMG kanál s notarizací a vlastní kontrola aktualizací končí. |
| Spravovaný hamlib (aplikace spouští rigctld) | **Odstranit.** Zůstává rigctld po TCP, flrig a vlastní CAT. |
| LoTW | **Předat do TQSL:** export nenahraných spojení do ADIF, otevření v aplikaci TQSL, potvrzení uživatelem. |
| Přechod z DMG verze | **Automaticky:** stejný identifikátor `cz.ok1xoe.mmtty4mac`, `container-migration.plist`, jednorázové povolení složky logů. |
| Cena | **Zdarma.** |
| Jméno | **RYRY** (testovací vzor RTTY). |
| Ikona | **Varianta A:** vodopád se dvěma stopami mark/space a čárové spektrum (vylepšení současné). |
| Web | Vlastní web `https://ryry.ok1xoe.dev` v designu „instrument“ z repa `xoe-web`. |
| Jazyky výpisu | Čeština a angličtina (jako aplikace). |

## 1. Identita a značka

- **Co vidí uživatel:** „RYRY“ (`CFBundleName`, `CFBundleDisplayName`), text žádosti o mikrofon,
  názvy oken, okno O aplikaci, příručka a web. Copyright: `© 2026 OK1XOE · LGPL v3 · based on MMTTY by JE3HHT`.
- **Co zůstává:**
  - identifikátor `cz.ok1xoe.mmtty4mac`, kvůli přechodu nastavení a Keychainu,
  - repozitář, moduly a binárka `MMTTY4MacApp`,
  - složka `Application Support/mmtty4mac`,
  - výchozí jméno logu `mmtty4mac`. Na to jméno jsou vázané existující soubory (`qtc.jsonl`),
    přejmenování by stávající logy odpojilo.
- **App Store:**
  - název `RYRY – RTTY for Contests`,
  - podtitul `Sound-card RTTY based on MMTTY`,
  - kategorie Utilities.
- **Ikona:** `scripts/make-icon.swift` ve variantě A. Upraví se:
  - mřížka ikon macOS (bez vlastního stínu, plocha 824/1024),
  - čitelnost v 16–32 px (méně buněk vodopádu, silnější stopy a spektrum).

  Výstupem je `Resources/AppIcon.icns` a `docs/appstore/icon-1024.png`. Pokud `actool` z Xcode 26
  umí zkompilovat formát `.icon`, přidá se i ten, aby macOS 26 ikonu nevkládal do šedého rámečku.
  Když to nepůjde, zůstane `.icns` a omezení se popíše.

## 2. Sandbox a úpravy funkcí

**Oprávnění** (`Resources/mmtty4mac.entitlements`):

| Klíč | Proč |
|---|---|
| `app-sandbox` | povinné pro App Store |
| `device.audio-input` | příjem ze zvukové karty |
| `device.serial` | CAT, PTT a FSK přes `/dev/cu.*`. Klíč je jen ve starší dokumentaci Applu, ověří se hned na začátku. |
| `network.client` | DX cluster, RBN, callbook, eQSL, Club Log, rigctld a flrig po TCP |
| `network.server` | API (fldigi XML-RPC, JSON-RPC WebSocket) |
| `files.user-selected.read-write` | otevírání a ukládání logů, WAV, importů a exportů |
| `files.bookmarks.app-scope` | trvalý přístup ke zvolené složce logů a k nedávným logům |
| `files.downloads.read-write` | ADIF pro TQSL |

**Úpravy:**

1. **Spravovaný hamlib pryč.** Z `RigType` zmizí `hamlibManaged`. Uložená hodnota se při načtení
   převede na `hamlib` (rigctld po TCP, výchozí 127.0.0.1:4532) a uživatel dostane jednorázové
   hlášení. Smaže se `ManagedHamlibRig`, jeho UI i testy.
2. **LoTW přes TQSL.** Zmizí spouštění procesu (`ProcessRunner`, `TQSLLocator`, `LoTWUploader` s tqsl CLI).
   Nový postup:
   - nenahraná spojení se vyexportují do `~/Downloads/<log>-lotw-<čas>.adi`,
   - soubor se otevře v TQSL přes `NSWorkspace`. Aplikace se hledá podle bundle ID, pak podle jména,
     a když se nenajde, zeptá se uživatele,
   - dialog „Podepsal jsi a odeslal spojení v TQSL?“ po potvrzení označí spojení jako nahraná do LoTW.
3. **Kontrola aktualizací pryč.** Zmizí modul `Updates` a jeho testy, `UpdateModel`, položka menu,
   přepínač v nastavení, klíč `MMUpdateFeedURL` a skripty `make-dmg.sh` a `release.sh`, tedy DMG
   a appcast. `make-app.sh` zůstane pro vývojová sestavení.
4. **Složka logů s trvalým oprávněním.**
   - `LogSettings` dostane bookmarky složky a nedávných logů (security-scoped, app-scope).
   - Výchozí složka v sandboxu je `~/Documents/RYRY`. Protože v sandboxu vede `NSHomeDirectory()`
     do kontejneru, výchozí složka se jednou nabídne v dialogu a uživatel ji potvrdí.
   - Když je uložená cesta mimo kontejner a bookmark k ní chybí (přechod z DMG verze), aplikace
     při startu otevře dialog s předvybranou složkou. Po potvrzení si uloží bookmark.
   - Přístup ke složce se otevírá po dobu otevřeného logu (`startAccessingSecurityScopedResource`).
5. **Přechod nastavení.** `Contents/Resources/container-migration.plist` přesune
   `Library/Application Support/mmtty4mac` a `Library/Preferences/cz.ok1xoe.mmtty4mac.plist`.
   Hesla v Keychainu kvůli jinému podpisu nejspíš nepřejdou a aplikace o ně požádá znovu. To se uvede
   v poznámkách k verzi.
6. **Ukázkový signál pro recenzenta a nové uživatele.** Přibalí se `demo-rtty.wav`, vygenerovaný
   přes `rtty-tool gen` (CQ, výměna, šum), a přibude položka Nápověda → Přehrát ukázkový signál.
   Aplikaci tak jde vyzkoušet bez rádia.
7. **Odkazy.** Nápověda → Web RYRY / Podpora / Ochrana osobních údajů vedou na `ryry.ok1xoe.dev`.
8. **Info.plist:**
   - přidá se `ITSAppUsesNonExemptEncryption = false`, protože aplikace používá jen HTTPS systému,
   - `CFBundleVersion` doplňuje skript sestavení (počet commitů).

## 3. Sestavení, podpis a nahrání

- `scripts/make-app.sh`: vývojové sestavení v sandboxu se stejnými oprávněními, podpis Apple Development.
- **Nový `scripts/release-appstore.sh`:**
  1. Sestaví univerzální aplikaci (`make-app.sh`).
  2. Vytvoří `.xcarchive`, stejně jako dosavadní `release.sh`.
  3. Spustí `xcodebuild -exportArchive` s `method=app-store-connect`, `destination=upload`,
     `signingStyle=automatic` a `-allowProvisioningUpdates`. Xcode pod účtem týmu (`TEAM_ID`
     z prostředí) vytvoří profil, podepíše certifikátem Apple Distribution, zabalí `.pkg` a nahraje
     ho do App Store Connect.
  4. Varianta `--export-only` vytvoří jen `.pkg` bez nahrání, pro kontrolu nebo Transporter.
- Ruční kroky (jednou, popsané v `docs/appstore/README.md`):
  - v App Store Connect založit aplikaci (bundle ID, jméno RYRY, jazyky, SKU),
  - zkontrolovat smlouvu Free Apps,
  - vyplnit metadata ze souborů v `docs/appstore/`.

## 4. Podklady pro App Store Connect (`docs/appstore/`)

- **Texty v češtině a angličtině:** `metadata-en.md` a `metadata-cs.md`. Každý obsahuje název,
  podtitul, propagační text, popis, klíčová slova (≤ 100 znaků), co je nového, URL podpory,
  marketingu a ochrany osobních údajů a copyright.
- **`review-notes.md`:** co aplikace dělá, jak ji vyzkoušet bez rádia (ukázkový WAV), proč potřebuje
  mikrofon, sériové porty a síťový server a že služby třetích stran používají uživatelovy vlastní účty.
- **`privacy.md`:** odpovědi pro App Privacy („Data Not Collected“) se zdůvodněním.
- **Další podklady:** věkové hodnocení 4+, export compliance („jen standardní šifrování“)
  a licence (viz níže).
- **Snímky obrazovky:** 2880 × 1800 (16:10), 4–5 kusů v každém jazyce. Pořídí se skriptem z běžící
  aplikace s ukázkovým signálem: hlavní okno, band mapa, skóre, spoty a log.
- **Licence (riziko k ověření, ne právní rozbor):** kód MMTTY je pod LGPL v3. Doporučení:
  - v App Store Connect použít vlastní licenční smlouvu (text LGPL v3 a odkaz na zdrojový kód),
    místo standardní licence Applu,
  - odkaz na zdrojový kód dát do popisu a do okna O aplikaci.

## 5. Web ryry.ok1xoe.dev (`site/`)

- **Design „instrument“:**
  - převezme se `css/site.css` a písma z `xoe-web` (Space Grotesk, JetBrains Mono, self-hosted),
  - tmavé i světlé téma s přepínačem, osciloskop v úvodní části (hero),
  - stejná hlavička i patička jako na `ok1xoe.dev`, s odkazem zpět.
- **Stránky v angličtině (kořen) a češtině (`/cs/`):**
  - úvod: hero s osciloskopem, ikona, tlačítko do App Store, přehled funkcí jako „moduly“,
    snímky obrazovky, požadavky,
  - podpora: FAQ, kontakt, odkaz na příručku, nahlášení chyby přes GitHub,
  - zásady ochrany osobních údajů,
  - příručka převzatá z `docs/html` s napojením na tokeny designu.
- Statický web bez sestavení a bez externích požadavků. Návod k nasazení (host Nginx s certbotem,
  stejně jako `xoe-web`) bude v `site/README.md`.
- Nic se nenasazuje ani nepublikuje, nasazení je na uživateli.

## 6. Ověření

- Všechny testy (`swift test`) projdou. Testy odstraněných funkcí se odstraní a na nové funkce
  přibudou nové (převod `hamlibManaged`, export pro LoTW, bookmarky a jejich načtení, přechod
  starých nastavení).
- **Ověření na hotovém sestavení v sandboxu:**
  - `codesign -d --entitlements`,
  - spuštění aplikace, mikrofon, otevření sériového portu (`/dev/cu.Bluetooth-Incoming-Port`),
    API na portu, DX cluster,
  - volba složky logů a znovuotevření po restartu,
  - přehrání ukázkového WAV,
  - přechod nastavení z DMG verze na čistém uživatelském účtu nebo v kopii kontejneru.
- `release-appstore.sh --export-only` vytvoří `.pkg`. Nahrání a odeslání ke schválení dělá uživatel.

## Mimo rozsah

- Samotné nahrání do App Store Connect a odeslání ke schválení (vyžaduje účet uživatele).
- Nasazení webu na server.
- Úpravy repa `xoe-web`, například přidání RYRY do `projects.js`. Doporučí se v závěru.
