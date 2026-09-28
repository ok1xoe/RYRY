# Plán 3: Log (ADIF + JSONL), makra a nastavení – implementační plán

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Minilog s přírůstkovým zápisem do ADIF a JSON Lines včetně oprav a mazání, makra kompatibilní s MMTTY (včetně CW ID) a trvalé nastavení aplikace se 16 profily.

**Architecture:** Tři nezávislé Swift targety bez závislosti na hardwaru:
- `QSOLog`: model spojení, ADIF kodek, úložiště.
- `MacroEngine`: expanze šablony na posloupnost výstupů `text` a `raw` (Baudot řídicí kódy) plus příznaky ukončení.
- `Settings`: Codable model, tolerantní načítání, profily.

Na Engine se napojují jen tenkými metodami: `Engine.sendMacro(_:)`, `Engine.sendRaw(_:)` a `QSO` stav. Ty přidává Task 4 tohoto plánu.

**Tech Stack:** Swift 6, Foundation (JSONEncoder/Decoder, FileHandle, `replaceItemAt` pro atomické přepsání).

**Spec:** `docs/superpowers/specs/2026-09-28-mmtty4mac-design.md` (sekce 9, 10, 11)

## Global Constraints

- macOS 14+, Swift 6, build a testy s `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Licence LGPL v3 (hlavička v nových souborech).
- **Zdroj pravdy logu je `.jsonl`.** ADIF je z něj vždy odvoditelný. Párování přes `id` (UUID) v JSONL a `APP_MMTTY4MAC_ID` v ADIF.
- Připisování: po každém spojení `write` + `synchronize()` (fsync) u obou souborů. Oprava a mazání: zápis do dočasného souboru ve stejném adresáři, pak `FileManager.replaceItemAt` (atomicky).
- ADIF: verze `3.1.4`, `PROGRAMID` `mmtty4mac`. Pole a formát `<NAME:len>value`, `<EOR>`, hlavička končí `<EOH>`. Délka se počítá v **bajtech UTF-8**.
- Makra: syntaxe a význam přesně podle MMTTY `ConvString` / `StoreCWID` / `OutputStr` (`mmtty/Main.cpp:4142-4370`). Odchylka: `%g`/`%f` (pozdrav podle časového pásma protistanice) se počítá podle UTC. MMTTY k tomu používal DXCC databázi, kterou nepřebíráme.
- Nastavení: `~/Library/Application Support/mmtty4mac/settings.json` a `profiles.json`. `schemaVersion = 1`. Chybějící nebo neplatné hodnoty → výchozí hodnota a varování, načtení nikdy nespadne.

## Review Focus

1. **Poškozený řádek v `.jsonl`** (ruční úprava, useknutý zápis při výpadku proudu) → načtení přeskočí jen ten řádek, nahlásí varování a ostatní spojení zůstanou. Test v Task 1.
2. **Znaky mimo ASCII v logu** (jméno `Tomáš`, QTH `Plzeň`) → ADIF délky v bajtech UTF-8, zpětné načtení stejné. Test v Task 1.
3. **Neúplné makro** (`%` na konci, `%{` bez `}`, neznámé `%z`) → nespadne, výstup podle MMTTY (`%%` / text do konce). Test v Task 2.
4. **Settings s neznámými nebo chybějícími klíči, starší schéma, nečitelný soubor** → výchozí hodnoty, soubor se nepřepíše, dokud uživatel neuloží. Test v Task 3.
5. **Oprava nebo smazání neexistujícího ID** → typovaná chyba, soubory beze změny. Test v Task 1.

---

### Task 1: QSOLog – model, ADIF, úložiště

**Files:** `Sources/QSOLog/{QSORecord,ADIF,Bands,QSOLogStore}.swift`, `Tests/QSOLogTests/*.swift`

**Interfaces (Produces):**
```swift
public struct QSORecord: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var call: String
    public var timeOn: Date
    public var timeOff: Date?
    public var frequency: Double?          // Hz
    public var mode: String = "RTTY"
    public var submode: String?
    public var rstSent: String?, rstRcvd: String?
    public var name: String?, qth: String?, grid: String?
    public var serialSent: Int?, serialRcvd: Int?          // STX / SRX
    public var exchangeSent: String?, exchangeRcvd: String? // STX_STRING / SRX_STRING
    public var comment: String?
    public var stationCallsign: String?
    public var band: String? { Bands.band(forHz:) }        // odvozené
}
public enum Bands { public static func band(forHz: Double?) -> String? }   // 2190m … 70cm podle ADIF
public enum ADIF {
    public static func header(now: Date) -> String
    public static func record(_ r: QSORecord) -> String
    public static func parse(_ text: String) -> [[String: String]]         // pro testy a kontrolu konzistence
}
public enum QSOLogError: Error, Equatable { case notFound(UUID), io(String) }
public actor QSOLogStore {
    public init(directory: URL, baseName: String = "mmtty4mac") throws    // načte .jsonl
    public var records: [QSORecord] { get }
    public private(set) var warnings: [String]
    public func append(_ r: QSORecord) throws
    public func update(_ r: QSORecord) throws                               // podle r.id
    public func delete(id: UUID) throws
    public func query(call: String? = nil, from: Date? = nil, to: Date? = nil, limit: Int? = nil) -> [QSORecord]
    public func previous(call: String) -> [QSORecord]                       // stejná značka (bez /P apod.), nejnovější první
    public func isADIFConsistent() -> Bool
    public func rebuildADIF() throws
    public var adifURL: URL { get }; public var jsonlURL: URL { get }
}
```

**Testy (RED → GREEN):**
- Append 3 spojení: `.jsonl` má 3 řádky, `.adi` má hlavičku a 3× `<EOR>`, `ADIF.parse` vrátí správná pole (`CALL`, `QSO_DATE` `YYYYMMDD`, `TIME_ON` `HHMMSS`, `FREQ` v MHz se 6 desetinnými místy, `BAND`, `MODE`, `APP_MMTTY4MAC_ID`).
- Nová instance store nad stejným adresářem načte totéž.
- Update: změna jména → oba soubory odpovídají, počet záznamů stejný.
- Delete: záznam zmizí z obou souborů.
- Update/delete neexistujícího ID → `.notFound` a soubory bajtově beze změny.
- UTF-8: `Tomáš`, `Plzeň` → ADIF `<NAME:6>Tomáš` (6 bajtů), parse vrátí stejné.
- Poškozený řádek v `.jsonl` → načte zbytek, `warnings` není prázdné.
- `isADIFConsistent` je `false` po ručním smazání záznamu z ADIF, `rebuildADIF()` vrátí `true`.
- `previous(call: "OK1ABC")` najde i `OK1ABC/P`. Řazení je od nejnovějšího.
- `Bands.band(forHz: 14_080_000) == "20m"`, `7_045_000 → "40m"`, `nil → nil`, `1e9 → nil` (mimo tabulku).

- [ ] Step 1: testy → RED; Step 2: implementace; Step 3: PASS; Step 4: commit `feat(log): QSO log with incremental ADIF + JSONL, edit/delete`

---

### Task 2: MacroEngine

**Files:** `Sources/MacroEngine/{MacroEngine,MacroContext,CWID}.swift`, `Tests/MacroEngineTests/*.swift`

**Interfaces:**
```swift
public struct MacroContext: Sendable {
    public var myCall = "", hisCall = "", name = "", qth = ""
    public var rstSent = "599", rstRcvd = "599"          // %s = my (odeslané), %r = his (přijaté) – jako MMTTY MyRST/HisRST
    public var now: Date = Date()
    public init() {}
}
public enum MacroOutput: Sendable, Equatable { case text(String), raw([UInt8]) }
public enum MacroEnd: Sendable, Equatable { case none, rxAfter, keepTx }
public enum MacroMode: Sendable, Equatable { case send, toEditor }       // '#' / '\' na začátku = do editoru
public struct MacroResult: Sendable, Equatable {
    public var outputs: [MacroOutput]; public var end: MacroEnd; public var mode: MacroMode
    public var logQSO: Bool
    public var plainText: String { get }                                  // náhled (raw jako „[CWID]“)
}
public enum MacroEngine {
    public static func expand(_ template: String, context: MacroContext) -> MacroResult
    static func cwID(_ text: String, context: MacroContext) -> [UInt8]   // přes StoreCWID tabulku
}
```
Pravidla podle MMTTY:
- `%m`, `%c`, `%n` (prázdné → `OM`), `%q`, `%r`, `%s`.
- `%R` = první 3 znaky `rstRcvd`, jinak `599`. `%N` = `rstRcvd` od 4. znaku. `%M` = `rstSent` od 4. znaku. `%x` a `%y` = části `%N` před a za `-`.
- `%g` = `GOOD MORNING/AFTERNOON/EVENING` podle UTC hodiny (<12, <18, jinak). `%f` = `GM/GA/GE`.
- `%D` = `YYYY-MON-DD` (MON = JAN…DEC). `%T` = `HH:MM` UTC. `%t` = `HHMM` UTC.
- `%L` → raw `0x1F`. `%F` → raw `0x1B` (v MMTTY pořadí bitů).
- `%E` = konec zpracování.
- `%{text}` = CW ID. Na začátek raw `0xFD` (diddle vyp.) a `0xFE` (nosná vyp.), potom pro každý znak (včetně expandovaných `%x` uvnitř) Morse:
  - tečka `0xFF, 0xFE`, čárka `0xFF,0xFF,0xFF, 0xFE`
  - mezera mezi znaky `0xFE,0xFE`
  - neznámý znak `0xFE`×5, `@` `0xFE`×3
  - tabulka z `StoreCWID`
- Neznámé `%z` → text `%%`. `%` na konci → nic.
- `\` se z textu vypouští. Koncové `\` (případně s CR/LF za ním) = `rxAfter`, koncové `#` = `keepTx`.
- Začátek `#` → `mode = .toEditor` (zbytek do editoru bez odeslání). Začátek `\` → `.toEditor` a TX.
- Navíc: `%l` = `logQSO = true` (nic nevysílá).

**Testy:** každá proměnná; CW ID pro `OK` porovnat s ručně spočítanou sekvencí; `%{%m}` s `myCall = "OK1XOE"`; `%L`/`%F` raw; `\` a `#` na konci s CRLF; začátek `#`; neúplné vstupy (Review Focus 3); `%E` ořízne zbytek.

- [ ] Step 1–4 (commit `feat(macro): MMTTY-compatible macro expansion with CW ID`)

---

### Task 3: Settings a profily

**Files:** `Sources/Settings/{AppSettings,SettingsStore,Profiles}.swift`, `Tests/SettingsTests/*.swift`

**Interfaces:**
```swift
public struct Macro: Codable, Sendable, Equatable { public var name: String; public var text: String; public var repeatSeconds: Double? }
public struct AppSettings: Codable, Sendable, Equatable {
    public var schemaVersion = 1
    public var station = Station()            // call, locator, name, qth
    public var audio = AudioSettings()        // inputUID, outputUID, inputChannel, outputChannel, outputGain
    public var ptt = PTTSettings()            // method, port, invert, txDelayMs, pttTailMs, pttTimeoutS
    public var fsk = FSKSettings()            // output: afsk|fskUART|fskSoft, port, line, invert, audioDuringFSK
    public var rig = RigSettings()            // type: none|hamlib|flrig, host, port
    public var api = APISettings()            // fldigiEnabled(true), fldigiPort 7362, jsonRPCEnabled(true), jsonRPCPort 7363, allowRemote(false)
    public var rtty: [String: ParameterValue] = [:]   // parametry modemu (ModemKit)
    public var macros: [Macro] = AppSettings.defaultMacros   // 12 maker (CQ, answer, 73…)
    public var log = LogSettings()            // directory (výchozí ~/Documents/mmtty4mac)
    public init()
    public func engineConfig() -> EngineConfig       // převod (Duration z ms)
}
public final class SettingsStore: Sendable {
    public init(directory: URL = default)
    public func load() -> (AppSettings, warnings: [String])    // tolerantní dekódování po sekcích
    public func save(_ s: AppSettings) throws                   // atomicky
}
public struct Profile: Codable, Sendable, Equatable { public var name: String; public var rtty: [String: ParameterValue] }
public final class ProfileStore: Sendable {                     // 16 slotů
    public func load() -> [Profile?]; public func save(_ p: Profile?, slot: Int) throws
}
```
Tolerantní dekódování: vlastní `init(from:)` pro každou sekci s `decodeIfPresent`. Neplatná hodnota vrátí výchozí hodnotu a zapíše varování (přes `userInfo` klíč s kolektorem varování).

**Testy:**
- Výchozí hodnoty. Round-trip save/load.
- Chybějící sekce → výchozí.
- Neznámé klíče → ignorované.
- Neplatný typ (`"fldigiPort": "abc"`) → výchozí port a varování.
- Nečitelný soubor (`"{{"`) → výchozí a varování, soubor nepřepsán.
- `engineConfig()` převádí ms na `Duration`, PTT metodu a FSK výstup.
- Profily: 16 slotů, uložení slotu 3, prázdné sloty `nil`, index mimo 0–15 → chyba.

- [ ] Step 1–4 (commit `feat(settings): app settings with tolerant decoding, 16 profiles`)

---

### Task 4: Napojení na Engine a rtty-tool

**Files:** `Sources/Engine/Engine.swift` (+ `sendRaw`, `sendMacro`), `Sources/RTTYModem/RTTYModem.swift` (+ `queueTxRaw`), `Sources/ModemKit/Modem.swift` (+ `queueTxRaw` s výchozí implementací ignorující), `Sources/rtty-tool/main.swift` (`:m1`–`:m12` v `live`, `macro` příkaz pro náhled), `Tests/EngineTests/EngineMacroTests.swift`

**Interfaces:**
```swift
// ModemKit
func queueTxRaw(_ codes: [UInt8])              // default: ignoruje
// Engine
public func sendMacro(_ result: MacroResult) async throws   // .send: TX (pokud není), výstupy do modemu; rxAfter → rx(); keepTx → nic
public func sendRaw(_ codes: [UInt8])
```
**Testy:**
- Makro `CQ CQ DE %m %m K\` s kontextem → Engine vysílá a po dovysílání se vrátí do RX. Odvysílaný zvuk obsahuje `CQ CQ DE OK1XOE OK1XOE K`.
- Makro s `%{%m}` → TX zvuk obsahuje úseky bez nosné (nulové vzorky ≥ 30 ms) a CW tečky a čárky (nosná 3 nebo 9 bitů).
- `#` na konci → Engine zůstane v TX (diddle).

- [ ] Step 1–4 (commit `feat: macros wired to engine; rtty-tool live :mN`)
