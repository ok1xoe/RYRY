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
