# Plán 6: Dokončení – chybějící části specifikace a odložené drobnosti

> Provádí se inline (executing-plans), TDD u logiky; pohledy se ověřují sestavením a snímkem.

**Goal:** Doplnit části specifikace, které v plánech 1–5 chyběly, a opravit odložené drobnosti z `docs/rulings.md`.

**Spec:** `docs/superpowers/specs/2026-09-28-mmtty4mac-design.md` (sekce 8, 9, 12)

## Task 1: Jádro a modem
- `rttycore_set_xy` / `rttycore_read_xy` (XY scope z `CFSKDEM::m_XYScopeMark/Space`, dávky 512 bodů) + `RTTYModem.xyScope()` / Engine / AppController
- `set("baud", .int)` aktualizuje `currentMode` (validovaná hodnota); mark daleko pod aktuální (nejdřív space, pokud je platné)
- `%L`/`%F` uvnitř `%{}` = 7 kódů jako MMTTY
- try/catch kolem alokace v `rttycore_create`; `CoreScope` ve všech funkcích C API; předalokovaný buffer pro doběh echa
- komentář v Modem.swift; `txPending` zdokumentovat (bajty textu + kódy jádra, jen pro test == 0)

## Task 2: Engine, klíčování, rig
- `PTTController.forceOff` zkusí CAT vždy, když je rig; timeout bez čekání na nezrušitelný úkol
- `nanos()` a `engineConfig()` omezí absurdní hodnoty
- `HamlibClient.setMode` odmítne neplatný mód (mezery, nové řádky)
- `HTTPXMLRPCTransport` ukončí URLSession
- `SoftFSKKeyer` bez alokací v real-time smyčce
- `clearTx` přes příznak pro konzumenta (render vlákno) místo `cring_clear` z producenta

## Task 3: Log a API
- `logQSO` bere snímek QSO pole před await
- `ClientSession` – veškerý sdílený stav pod zámkem; přetečení inboxu = chyba a zavření spojení
- `TextHistory` bez O(n) ořezu po znacích; `text.clear_rx` nuluje délku
- data ve JSONL/ISO s desetinami sekund (čte obojí); `log.query` přijímá obě varianty
- `QSORecord.call` normalizovaný při append/update

## Task 4: CLI
- `--his`; přepínače modemu z příkazové řádky mají přednost před nastavením jen, když jsou zadané

## Task 5: GUI
- XY scope panel (přepínač), nabídka profilů (načíst/uložit 16 slotů), kolečko ve vodopádu = squelch level, tlačítko HAM (shift 170), `os.Logger` diagnostika, zrušení hlášky „čekám na mikrofon“ po povolení, CRLF v TX editoru, odeslání rozepsaného textu při přechodu do TX, DatePicker v UTC
