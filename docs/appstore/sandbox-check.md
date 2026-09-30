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
