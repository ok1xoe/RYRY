# RYRY v Mac App Store – postup odeslání

Všechno, co je k odeslání potřeba, je v této složce. Postupuj shora dolů. Kroky označené 🧑 vyžadují tvůj
účet nebo rozhodnutí, ostatní jsou připravené.

| Soubor | Co obsahuje |
|---|---|
| `metadata-en.md` | název, podtitul, propagační text, popis, klíčová slova, co je nového, URL, kategorie, cena, věk (angličtina = primární jazyk) |
| `metadata-cs.md` | totéž česky (lokalizace) |
| `check-lengths.sh` | kontrola délek polí proti limitům App Store Connect |
| `review-notes.md` | poznámky pro recenzenta: jak aplikaci vyzkoušet bez rádia a proč potřebuje jednotlivá oprávnění |
| `privacy.md` | odpovědi pro App Privacy („Data Not Collected“), export compliance a věkové hodnocení |
| `LICENSE-EULA.txt` | vlastní licenční smlouva (LGPL v3 a odkaz na zdrojový kód) |
| `icon-1024.png` | ikona 1024 px (web, marketing; App Store bere ikonu z aplikace) |
| `screenshots/{en,cs}/` | snímky 2880 × 1800 (vytvoří `scripts/appstore-screenshots.sh`) |
| `sandbox-check.md` | co bylo ověřeno v sandboxu a jak |

## 1. Účet a aplikace v App Store Connect 🧑

1. **Xcode → Settings → Accounts:** přihlášené Apple ID týmu `GN8G426WK4`. První pokus o export skončil chybou
   `No Accounts` / `missing Xcode-Token` (Mac byl zamčený a přihlášení v klíčence nebylo dostupné). Po odemčení
   a případném novém přihlášení to projde.
2. **Smlouvy:** App Store Connect → Business. Pro aplikaci zdarma stačí platná smlouva „Free Apps Agreement“,
   která je součástí členství. Bankovní a daňové údaje nejsou potřeba.
3. **Nová aplikace:** App Store Connect → Apps → „+“ → New App:
   - Platform: **macOS**
   - Name: **RYRY – RTTY for Contests**. Kdyby bylo obsazené, zkus „RYRY RTTY“ a uprav i web a metadata.
   - Primary Language: **English (U.S.)**
   - Bundle ID: **cz.ok1xoe.ryry**. Pokud v nabídce chybí, Certificates, Identifiers & Profiles →
     Identifiers → „+“ → App IDs, explicitní `cz.ok1xoe.ryry`, bez dalších schopností.
   - SKU: **RYRY-MAC**
   - User Access: Full Access
4. **Web:** nasaď `site/` na `https://ok1xoe.dev/ryry/` (viz `site/README.md`). URL podpory a zásad ochrany
   osobních údajů musí fungovat, než aplikaci odešleš ke schválení.

## 2. Sestavení a nahrání

    TEAM_ID=GN8G426WK4 ./scripts/release-appstore.sh --export-only   # zkouška: jen .pkg v build/appstore
    TEAM_ID=GN8G426WK4 ./scripts/release-appstore.sh                 # nahraje do App Store Connect

Po nahrání trvá zpracování buildu v App Store Connect 10–60 minut (přijde e-mail). Build se pak objeví ve verzi
1.0.0 v sekci **Build**.

## 3. Vyplnění verze 1.0.0 🧑

1. **App Information:** kategorie Utilities, věkové hodnocení (vše „None“ → 4+, `privacy.md`), Content Rights
   („No“), **License Agreement → Custom** a vložit `LICENSE-EULA.txt`.
2. **Pricing and Availability:** Free, všechna území.
3. **App Privacy:** Get Started → „No, we do not collect data from this app“ (zdůvodnění v `privacy.md`),
   Privacy Policy URL `https://ok1xoe.dev/ryry/privacy/`.
4. **Verze 1.0.0 (English):**
   - vlož texty z `metadata-en.md`,
   - nahraj snímky `screenshots/en/*.png` (Mac: 2880 × 1800),
   - URL podpory a marketingu,
   - copyright,
   - review notes z `review-notes.md` (kontakt: jméno, e-mail, telefon doplň),
   - Sign-in required: ne.
5. **Čeština:** v pravém horním rohu verze přidej jazyk Czech a vlož `metadata-cs.md` a `screenshots/cs/*.png`.
6. **Build:** vyber nahraný build a odpověz na export compliance („None of the algorithms…“). Díky
   `ITSAppUsesNonExemptEncryption = NO` se už nezeptá.
7. **Add for Review → Submit.** Schválení obvykle trvá 1–3 dny.

## 4. Po schválení

- Na webu (`site/index.html`, `site/cs/index.html`) nahraď zástupný odkaz `#appstore` skutečnou adresou
  aplikace (`https://apps.apple.com/app/id<číslo>`). Číslo je v App Store Connect → App Information → Apple ID.
- Volitelně přidej RYRY mezi projekty na `ok1xoe.dev` (`xoe-web/js/projects.js`).

## Rizika a otevřené body

- **LGPL v3 a App Store.** Kód MMTTY je pod LGPL v3. Mezi (L)GPL a podmínkami App Store je známé napětí (dříve
  kvůli tomu např. VLC z iOS App Store zmizelo). Tady ho zmírňuje:
  - vlastní licenční smlouva (`LICENSE-EULA.txt`), takže se nepoužije standardní licence Apple,
  - veřejný zdrojový kód,
  - to, že macOS dovoluje spouštět vlastní sestavení.

  Pokud chceš jistotu, zeptej se ostatních autorů kódu MMTTY (JE3HHT a přispěvatelé n5ac/mmtty), jestli s
  distribucí přes App Store souhlasí. **Není to právní rozbor.**
- **Oprávnění `device.serial`.** Funguje (ověřeno v `sandbox-check.md`), ale Apple ho popisuje jen ve starší
  dokumentaci. Kdyby ho recenze zpochybnila, odkaž na ovládání rádia přes USB (CAT, PTT, FSK) v review notes.
- **První spuštění.** Nová instalace se hned zeptá na složku pro log. Je to popsané v review notes, aby to
  recenzent nebral jako chybu.
- **Přechod z DMG verze na vývojovém Macu.** Migrace proběhne jen při vzniku kontejneru `cz.ok1xoe.ryry`;
  starý vývojový kontejner `cz.ok1xoe.mmtty4mac` (bundle ID vývojových sestavení před vydáním) se nepřenáší. Viz `sandbox-check.md`.
