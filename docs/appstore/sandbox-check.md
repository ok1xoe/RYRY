# Ověření sandboxu (App Store)

Sestavení: `MMTTY_ARCHS=arm64 ./scripts/make-app.sh`, podpis Apple Development, oprávnění z `Resources/mmtty4mac.entitlements`.

| Kontrola | Výsledek (2026-09-30) |
|---|---|
| Oprávnění v podpisu (`codesign -d --entitlements -`) | všech 8 klíčů |
| Spuštění v sandboxu | OK, vznikl kontejner `~/Library/Containers/cz.ok1xoe.mmtty4mac` |
| API: fldigi XML-RPC 127.0.0.1:7362 | OK, `fldigi.name_version` odpovídá |
| API: JSON-RPC 127.0.0.1:7363 | OK, naslouchá (`lsof`) |
| Sériový port s `device.serial` | OK, `open()` na `/dev/cu.Bluetooth-Incoming-Port` a `/dev/cu.debug-console` projde |
| Sériový port bez `device.serial` | odmítnuto: „Operation not permitted“ (kontrolní test, potvrzuje, že klíč je nutný a funguje) |

Sériový port se ověřoval samostatnou testovací aplikací `cz.ok1xoe.sandboxprobe` se stejnými oprávněními.

Poznámka: macOS 14+ chrání kontejnery aplikací. Čtení `~/Library/Containers/cz.ok1xoe.mmtty4mac`
z Terminálu vyvolá dotaz „přístup k datům jiných aplikací“. Pro ověřování proto používej výstupy
aplikace (API, zprávy v okně), ne přímé čtení kontejneru.

## Přechod nastavení z DMG verze (`container-migration.plist`)

Ověřeno testovací aplikací `cz.ok1xoe.migprobe…` se stejným souborem, jen se zkušební složkou místo skutečné
(skutečná `~/Library/Application Support/mmtty4mac` patří běžící DMG verzi a migrace ji **přesune**):

| Kontrola | Výsledek (2026-09-30) |
|---|---|
| `${ApplicationSupport}/<složka>` → kontejner | OK, `settings.json` je v kontejneru a z původního místa zmizel |
| `${Library}/Preferences/<bundle-id>.plist` → kontejner | OK, `UserDefaults` v sandboxu vrací hodnotu uloženou před migrací |

**Důležité:** macOS migruje jen při **vzniku** kontejneru. Kontejner `~/Library/Containers/cz.ok1xoe.mmtty4mac`
na vývojovém Macu už existuje, protože vznikl při testech sandboxu a obsahuje jen testovací výchozí nastavení.
Kdo chce na tomhle Macu vyzkoušet přechod s vlastními daty, musí ten kontejner před instalací verze z App Store
smazat ve Finderu (Knihovna → Containers → „RYRY“ / cz.ok1xoe.mmtty4mac). Na Macích uživatelů, kde vývojová
verze nikdy neběžela, proběhne přechod sám.

Zbytky testů, které můžeš smazat: `~/Library/Containers/cz.ok1xoe.sandboxprobe` a `cz.ok1xoe.migprobe*`.

## Sestavení 1.0.0 (236)

| Kontrola | Výsledek (2026-09-30) |
|---|---|
| Univerzální binárka | `x86_64 arm64` |
| `codesign --verify --strict` | OK |
| Oprávnění v podpisu | 8 klíčů |
| `Info.plist` | RYRY, 1.0.0, `ITSAppUsesNonExemptEncryption` = false, `CFBundleIconName` = AppIcon |
| `swift test` | 804 testů prošlo |

## Zbývá ověřit ručně v GUI (Mac byl při přípravě zamčený)

- [ ] Nová instalace: dialog „RYRY potřebuje přístup ke složce s logem“ otevřený ve složce Dokumenty; po „Povolit přístup“ vznikne `~/Documents/RYRY` a log je v ní (ne volně v Dokumentech).
      Po povolení se API spustí (`lsof -iTCP:7362`). Po restartu už se neptá.
- [ ] Zrušený dialog: log v kontejneru a zpráva ve stavovém řádku s cestou.
- [ ] Přesunutá nebo přejmenovaná složka logu: aplikace se znovu zeptá.
- [ ] Nápověda → Přehrát ukázkový signál: v okně příjmu se objeví „RYRYRYRY CQ TEST OK1XOE…“.
- [ ] Mikrofon: systémový dialog s textem „RYRY needs the audio input…“.
- [ ] DX cluster se připojí (okno Spoty).
- [ ] LoTW bez TQSL: zpráva s názvem souboru ve Stažených souborech, dotaz na potvrzení, bez potvrzení se nic
      neoznačí.
- [ ] Ikona v Docku a ve Finderu (macOS 26: skleněný tvar, žádný šedý rámeček); ve Finderu se aplikace jmenuje RYRY.app.
- [ ] Historie značek (N1MM): po výběru souboru a restartu se načte; bez nového výběru se ukáže výzva vybrat ho znovu.
- [ ] Snímky: `./scripts/appstore-screenshots.sh` (potřebuje povolení Nahrávání obrazovky pro Terminál).
- [ ] `TEAM_ID=GN8G426WK4 ./scripts/release-appstore.sh --export-only` po přihlášení účtu v Xcode.
