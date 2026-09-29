# Plán 8: Seznam zpráv, barvy maker, scope demodulátoru, závodní formáty

**Zadání uživatele:** „udělej bod 1 2 3 5“. Body jsou:
1. MsgList,
2. barvy tlačítek maker,
3. ladicí scope demodulátoru,
5. závodní formáty CQ/RJ, BARTG a PED.

## T1: Seznam zpráv (MMTTY sys.m_MsgList / m_MsgName)
- `AppSettings.messages: [Macro]` (název a text, syntaxe maker). Seznam je neomezený a výchozí obsahuje 3 zprávy.
- `AppController.runMessage(index)` jde stejnou cestou jako makro (expand, TX, `\`, `#`, `%l`).
- GUI: nabídka „Zprávy“ u lišty maker (odeslat, upravit, přidat, smazat) a editor.
- JSON-RPC: `msg.list`, `msg.run {index}`.
- Testy: tolerantní načtení, `runMessage` vysílá rozvinutý text, špatný index → chyba.

## T2: Barvy tlačítek maker
- `Macro.color: String?` (hex `#RRGGBB`).
- V editoru makra je ColorPicker s volbou „bez barvy“ a tlačítko se obarví (tint).
- Testy: round-trip a neplatná hodnota → nil.

## T3: Scope demodulátoru (MMTTY TTScope)
- C API:
  - `rttycore_set_scope(core, on)`,
  - `rttycore_read_scope(core, source 0–3, mark, space, bit, sync, max)` → dávka 8192 vzorků (CScope Collect/GetFlag), po přečtení se sbírá znovu.
- Zdroje: 0 = Filtr, 1 = Det., 2 = LPF, 3 = ATC (jen se zapnutým ATC).
- Průchod přes Modem, Engine, AppModel (dotazování jen při otevřeném okně) a SwiftUI okno „Scope“:
  - 4 stopy (mark, space, bit, sync),
  - volba zdroje, zoom a posun, jednorázové zachycení (trigger).
- Testy: po zpracování signálu přijde dávka, bitová stopa obsahuje mark i space a sync obsahuje značky start a stop bitů. Bez zapnutí scope nic.

## T5: Závodní formáty (MMTTY Log m_Contest: ON, CQRJ, BARTG, PED)
- `ContestSettings.format`: `serial` (dosavadní), `cqrj`, `bartg`, `ped`.
- **Odesílání:**
  - `serial`: 599 + číslo (případně pevná výměna).
  - `cqrj`: pevná výměna (zóna/QTH), bez čísel.
  - `bartg`: číslo + čas UTC začátku QSO (`599NNN-HHMM`; `%x` = číslo, `%y` = čas; MMTTY SetHisUTC).
  - `ped`: bez čísel.
- **Klik v příjmu (TMmttyWd::PBoxRxMouseDown):**
  - `cqrj`: číslo = zóna, text = QTH, výsledek `exchangeRcvd` „ZZ QTH“ (StoreZone/StoreQTH).
  - `bartg`: `hh:mm` nebo platné HHMM = čas, do 3 číslic = číslo (StoreUTC/StoreNR), výsledek serialRcvd a exchangeRcvd = HHMM.
  - `ped`: každé slovo = značka.
- Cabrillo: výměna = číslo i text (BARTG „015 1203“, CQ/RJ „14 DL“).
- Testy: pro každý formát klik a odesílané `%N`/`%x`/`%y` a řádek Cabrillo.

## Rulings
- Seznam zpráv se odesílá stejně jako makro. MMTTY má u zpráv stejné řídicí znaky (`\`, `_`); cena omylu: žádná.
- Barvy jen jako tint tlačítka, bez barvy písma; cena omylu: kosmetika.
- CQ/RJ a BARTG ukládají přijatou výměnu do `exchangeRcvd` (+ `serialRcvd`) místo MMTTY formátu v MyRST; cena omylu: jiná reprezentace, stejné údaje.
