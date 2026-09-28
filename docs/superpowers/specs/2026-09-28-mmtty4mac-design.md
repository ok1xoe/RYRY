# mmtty4mac – návrh (design spec)

- **Datum:** 2026-09-28
- **Autor:** OK1XOE (s Claude Code)
- **Stav:** návrh ke schválení
- **Licence:** celý projekt LGPL v3

## 1. Cíl

Nativní macOS aplikace ve Swiftu pro RTTY, vycházející z MMTTY (JE3HHT). Aplikace:

1. funguje samostatně (GUI pro příjem a vysílání RTTY),
2. jde zakomponovat do jiných programů přes API (fldigi XML-RPC a vlastní JSON-RPC),
3. je architektonicky připravená na další modemová jádra (MMVARI: PSK/MFSK…, MMSSTV: SSTV). V této verzi se ale implementuje **jen RTTY**.

### Zdroje

- **Základ:** původní `n5ac/mmtty` (v1.70H), lokálně `./mmtty/`, zdrojáky v kódování Shift-JIS.
- **Inspirace:** fork `ji1uui/mmtty-ji1uui` (`./mmtty-ji1uui/`). Přebírají se jen konkrétní opravy (viz 4.2). Jeho AI refaktoring (`IDemodStrategy`, `IRadioProtocol`…) je z velké části nezapojený nebo chybný a nepřebírá se.
- Referenční repozitáře nejsou součástí tohoto repozitáře (`.gitignore`).

### Mimo rozsah (vědomě vyřazeno)

- MMTTY remote protokol (Windows zprávy a sdílená paměť) ani pomocný `mmtty.exe` pro Wine.
- Emulace TNC (TNC-241, KAM, raw Baudot) a DLL pluginy (`.mmt`, `.mml`, `.mmr`, `EXTFSK.dll`). Funkce EXTFSK je nahrazena vestavěným softwarovým FSK, viz 6.3.
- Vlastní CAT (z `cradio.cpp`). Rig se ovládá jen přes hamlib a flrig.
- Japonské log formáty a funkce (Hamlog, MMLOG `.MDT`, MMCG), DXCC tabulka z `country.cpp`.
- Implementace modemů MMVARI a MMSSTV (jen připravené rozhraní).
- Import `Mmtty.ini` (případně později).
- Spouštění `rigctld` aplikací (případně později).

## 2. Platforma a technologie

- macOS 14 (Sonoma) a novější, Apple Silicon i Intel.
- Swift 5.9+ s C++ interop, SwiftUI, Swift Package Manager a Xcode projekt pro `.app`.
- Audio: AVAudioEngine a AVAudioConverter. DSP pomocné výpočty přes Accelerate (vDSP).
- Sériové porty: POSIX termios a IOKit (`IOSSIOSPEED`).
- Síť: Network.framework (TCP a WebSocket servery a klienti).
- Pracovní název: `mmtty4mac`. Přejmenování (např. při přidání dalších modemů) je možné později.

## 3. Architektura

```
┌──────────────────── App (SwiftUI) ─────────────────────────────┐
│ společné: vodopád · makra · minilog · nastavení                 │
│ podle modemu: RTTY panel | (PSK panel) | (SSTV obraz)           │
└────────────────────────────┬────────────────────────────────────┘
                             │ příkazy ↓   události ↑
┌────────────────────────────┴────────────────────────────────────┐
│ Engine (Swift) – RX/TX automat, stejný pro všechny módy         │
│  AudioIO · Keying · RigControl · MacroEngine · QSOLog · Settings│
│  ModemRegistry ──► protokol `Modem`                             │
└──────┬───────────────────┬─────────────────────┬────────────────┘
┌──────┴──────┐   ┌────────┴────────┐   ┌────────┴────────┐
│ RTTYModem   │   │ (VariModem)     │   │ (SSTVModem)     │
│ MMTTYCore   │   │ MMVARICore C++  │   │ MMSSTVCore C++  │
│ C++ · teď   │   │ později         │   │ později         │
└─────────────┘   └─────────────────┘   └─────────────────┘

APIServer (poslouchá Engine, volá jeho příkazy):
  ├─ FldigiXMLRPC   (HTTP :7362, zapínatelné)
  └─ JSONRPC        (WebSocket :7363, zapínatelné)
```

### Zásady

- **Engine je jediný řadič.** GUI, fldigi XML-RPC i JSON-RPC jsou rovnocenní klienti: volají stejné příkazy a dostávají stejné události. Žádná logika v GUI.
- **Každý modul je samostatný SPM target** s jasným rozhraním a vlastními testy.
- **C++ jádro je izolované.** Swift volá jen tenké rozhraní (`RTTYCore`), nikdy interní třídy MMTTY.

### SPM targety

| Target | Jazyk | Odpovědnost | Závisí na |
|---|---|---|---|
| `MMTTYCore` | C++ | RTTY DSP, Baudot, AFC, bez OS závislostí | – |
| `ModemKit` | Swift | protokol `Modem`, popis parametrů, typy událostí | – |
| `RTTYModem` | Swift | implementace `Modem` nad `MMTTYCore` | MMTTYCore, ModemKit |
| `AudioIO` | Swift | vstup a výstup zvuku, převod vzorkovací frekvence, WAV | – |
| `Keying` | Swift | PTT (RTS/DTR), FSK UART, FSK soft-timed | – |
| `RigControl` | Swift | protokol `Rig`, `HamlibClient`, `FlrigClient` | – |
| `MacroEngine` | Swift | expanze maker, CW ID | ModemKit |
| `QSOLog` | Swift | ADIF a JSONL, append, oprava, mazání, dotazy | – |
| `Settings` | Swift | JSON konfigurace, profily | ModemKit |
| `Engine` | Swift | RX/TX automat, vlákna, propojení modulů, sběrnice událostí | vše výše |
| `APIServer` | Swift | fldigi XML-RPC, JSON-RPC/WebSocket | Engine |
| `App` | SwiftUI | GUI | Engine |

## 4. Modemové rozhraní a jádro RTTY

### 4.1 Protokol `Modem` (ModemKit)

```swift
public protocol Modem: AnyObject {
    static var id: String { get }                 // "rtty"
    var modes: [ModeDescriptor] { get }           // RTTY-45, RTTY-50, RTTY-75…
    var currentMode: ModeDescriptor { get }
    var sampleRate: Double { get }                // pracovní frekvence modemu (RTTY: 11025)
    var capabilities: ModemCapabilities { get }   // .fskKeying, .afc, .multiChannel, .imageOutput…
    var parameters: [ParameterDescriptor] { get } // generický popis pro GUI a API
    var events: AsyncStream<ModemEvent> { get }

    func select(mode: ModeDescriptor) throws
    func set(parameter: String, value: ParameterValue) throws
    func get(parameter: String) -> ParameterValue?

    func processRx(_ samples: UnsafeBufferPointer<Float>)      // DSP vlákno
    func queueTx(text: String)
    func generateTx(into buffer: UnsafeMutableBufferPointer<Float>) -> TxStatus
    func clearTx()
    func spectrum() -> SpectrumFrame?
}

public enum ModemEvent {
    case rxText(Character, echo: Bool)
    case rxImageLine(ImageLine)          // pro budoucí SSTV, RTTY nepoužívá
    case signal(level: Float, squelchOpen: Bool)
    case tuning(TuningInfo)              // RTTY: mark, space (AFC)
    case shift(fig: Bool)
    case overflow
}
```

`ModeDescriptor` nese ADIF `MODE` a případně `SUBMODE` (RTTY: `MODE=RTTY`).

### 4.2 `MMTTYCore` (C++, LGPL v3)

**Přebírá se z původního `mmtty`:**

- `Rtty.cpp/h`: `CFSKDEM` (demodulátor), `CFSKMOD` (modulátor), `CRTTY` (Baudot/ITA2), `CPHASE`, `CAA6YQ`, `CPLL`, `CVCO`, `CATC`, `CSmooz`, `CAMPCONT` a související.
- `fir.cpp/h`: návrh FIR (Kaiser, Hilbert), IIR (Butterworth, Čebyšev), `CIIRTANK`, `CLMS` (LMS/notch), `CDECM2`, `CDECM4`, `CINTP4`, `COVERLIMIT`. **Bez** `DrawGraph*`.
- `CLX` (komplexní čísla).
- `TSound::DoAFC` ze `Sound.cpp` jako samostatná funkce `AFC::update(spectrum, state)`.
- FFT pro AFC a vodopád: vDSP. `Fft.cpp` se nepřebírá, převezme se jen logika průměrování a zesílení.

**Úpravy:**

1. Převod kódování ze Shift-JIS do UTF-8. Japonské komentáře zůstávají, hlavička s licencí a copyrightem se doplní o „Copyright 2026 OK1XOE (úpravy)“.
2. Odstranění globálních proměnných. `sys.*`, `SampFreq`, `SampBase`, `DemSamp`, `DemOver`, `FFT_SIZE`, `FSKCount*`, `g_SinTable` a další nahradí struktura `CoreConfig` předaná v konstruktoru, případně členské proměnné. Změna vzorkovací frekvence = nová instance jádra.
3. Odstranění `__fastcall`, `#pragma option`, `BOOL`/`BYTE` (→ `bool`/`uint8_t`), `VirtualLock`, `::Sleep`, všech VCL typů (`AnsiString` → `std::string`).
4. Opravy převzaté z ji1uui: `memmove` místo `memcpy` v `DoFIR` (překrývající se buffery), definice `CFSKDEM::SetSmoozCount`, `CLMS::Clear`.
5. Známé zvláštnosti originálu (`CVCO` +0,5 kroku, fáze „FFT“ demodulátoru bez anti-alias filtru) se **nemění**, aby dekódování zůstalo shodné s MMTTY. Jsou zdokumentované v kódu.

**Veřejné rozhraní `RTTYCore`** (jediné, co vidí Swift):

```cpp
struct CoreConfig { double sampleRate; /* demod, filtry, AFC, TX… */ };

class RTTYCore {
public:
    explicit RTTYCore(const CoreConfig&);
    void processRx(const float* samples, size_t n);   // vstup ±1.0, interně škálováno na ±32768
    size_t readChars(RxChar* out, size_t max);        // dekódované znaky (ASCII + příznak echo)
    SignalInfo signal() const;                        // úroveň, squelch, overflow, mark/space
    void setParam(ParamId, double);                   // baud, mark, shift, demod typ, filtry…
    double getParam(ParamId) const;
    void queueTx(const char* text);                   // ASCII → Baudot (CRTTY)
    void queueTxRaw(const uint8_t* codes, size_t n);  // Baudot/řídicí kódy (CW ID, diddle)
    size_t generateTx(float* out, size_t n);          // vzorky AFSK
    size_t txPending() const;
    void clearTx();
    bool nextFskCode(FskCode& out);                   // Baudot kódy + časování pro Keying (FSK režimy)
    void updateAFC(const float* spectrum, size_t bins);
};
```

### 4.3 Vzorkovací frekvence

- Modem RTTY pracuje na **11 025 Hz** (volitelně 12 000 Hz) jako MMTTY, se stejnými délkami filtrů.
- `AudioIO` převádí mezi frekvencí zařízení (typicky 48 kHz) a `Modem.sampleRate` přes AVAudioConverter.
- Korekce hodin zvukové karty (ppm, RX i TX zvlášť) je parametrem nastavení. Kalibrační nástroj (`ClockAdj`) přijde později.

## 5. Engine, vlákna a tok dat

```
Mikrofon 48k ─► AudioIO (render vlákno) ─► převod na 11025 ─► lock-free fronta
                                                                  │
                         DSP vlákno (Engine) ◄────────────────────┘
                         modem.processRx → znaky, úroveň, spektrum
                         AFC ~ každých 100 ms
                                  │ události (AsyncStream, EventBus)
                ┌─────────────────┼──────────────────┐
               GUI           JSON-RPC           fldigi XML-RPC
```

- **Render vlákno** (CoreAudio): jen kopíruje vzorky do lock-free ring bufferu, případně z něj. Žádné alokace ani zámky.
- **DSP vlákno** (Engine): demodulace, AFC, spektrum, generování TX vzorků do výstupního ring bufferu.
- **Engine actor**: stav, příkazy, rozesílání událostí přes `EventBus`. Klienti (GUI, API) dostávají `AsyncStream<EngineEvent>`.
- Vysílání: text → `MacroEngine` → `modem.queueTx` → `generateTx` → převod na 48k → výstup. Při FSK se zároveň předávají bity do `Keying`, modulátor běží dál kvůli echu a časování. Zvukový výstup je při FSK volitelný (výchozí vypnutý).

### 5.1 Stavový automat RX/TX

```
RX ──tx()──► PTT_ON ──txDelay──► TX (diddle/text) ──rx()──► DRAIN ──► PTT_OFF ──► RX
                                   └── rxNow() → okamžitě PTT_OFF, TX buffer zahodit
```

- Příkazy: `tx()`, `rx()` (RX po dovysílání bufferu), `rxNow()` (okamžitě), `tune()` (nosná na mark).
- Nastavení: zpoždění PTT před modulací a po ní, PTT časovač (maximální doba vysílání), NET (TX na frekvenci RX, jinak pevná TX frekvence), REV, diddle (LTR/BLK), odesílání po znacích, slovech nebo řádcích.
- Stav `DRAIN` čeká na `txPending() == 0` a doběh zvukového nebo FSK výstupu.

## 6. Vysílání, klíčování a rig

### 6.1 PTT (jeden zdroj podle nastavení)

1. **CAT** přes `RigControl` (`set_ptt`).
2. **Sériový port**: RTS, DTR nebo oba, s volitelnou inverzí.
3. **VOX / žádné**: aplikace PTT neovládá.

### 6.2 Režimy výstupu

| Režim | Popis |
|---|---|
| `afsk` (výchozí) | jen zvukový výstup |
| `fsk-uart` | TxD, 45,45 Bd (dle baudu), 5 bitů, 1,5 stop bitu, přes `IOSSIOSPEED`. Při otevření se ověří skutečně nastavená rychlost, jinak chyba „port nepodporuje X Bd, použijte fsk-soft“. Spolehlivé s FTDI. |
| `fsk-soft` | softwarově časované klíčování na TxD (break), DTR nebo RTS. Real-time vlákno (`THREAD_TIME_CONSTRAINT_POLICY`, `mach_wait_until`). Náhrada EXTFSK. |

- Polarita FSK (normal/inverted) je nastavitelná.
- FSK port může být stejný jako PTT port. PTT pak jde přes druhý ovládací vodič.

### 6.3 `RigControl`

```swift
public protocol Rig: AnyObject {
    var status: AsyncStream<RigStatus> { get }  // online/offline, freq, mode
    func frequency() async throws -> Double
    func setFrequency(_ hz: Double) async throws
    func mode() async throws -> String
    func setMode(_ mode: String) async throws
    func setPTT(_ on: Bool) async throws
}
```

- **`HamlibClient`**: TCP na `rigctld` (výchozí `127.0.0.1:4532`), příkazy `f`, `F`, `m`, `M`, `t`, `T` (případně rozšířený protokol `+`).
- **`FlrigClient`**: XML-RPC na flrig (výchozí `127.0.0.1:12345`): `rig.get_vfo`, `rig.set_vfoA`, `rig.get_mode`, `rig.set_mode`, `rig.set_ptt`.
- **`NoRig`**: bez ovládání (výchozí).
- Frekvence se čte každou sekundu. Výpadek → stav `offline`, automatické znovupřipojení s rostoucím intervalem (1–10 s), dekódování běží dál.

## 7. API

Obě vrstvy jsou v nastavení zapínatelné zvlášť. **Ve výchozím stavu naslouchají jen na `127.0.0.1`.** Naslouchání na síti je potřeba výslovně povolit, protože API umí zapnout vysílač.

### 7.1 fldigi XML-RPC (HTTP POST, port 7362)

Podmnožina metod fldigi se stejnými názvy a signaturami (ověřeno proti `fldigi_doxygen/user_src_docs/xmlrpc-control.txt`):

| Skupina | Metody |
|---|---|
| fldigi | `fldigi.list`, `fldigi.name`, `fldigi.version`, `fldigi.name_version`, `fldigi.version_struct` |
| main | `main.get_trx_status` (`rx`/`tx`/`tune`), `main.tx`, `main.rx`, `main.tune`, `main.abort`, `main.rx_only`, `main.rx_tx`, `main.get_frequency`, `main.set_frequency`, `main.get_afc`, `main.set_afc`, `main.get_reverse`, `main.set_reverse`, `main.get_squelch`, `main.set_squelch`, `main.get_squelch_level`, `main.set_squelch_level` |
| modem | `modem.get_name`, `modem.get_names`, `modem.set_by_name`, `modem.get_carrier`, `modem.set_carrier` |
| rig | `rig.set_frequency`, `rig.get_mode`, `rig.set_mode`, `rig.get_modes`, `rig.get_name` |
| text / rx / tx | `text.add_tx`, `text.add_tx_bytes`, `text.clear_tx`, `text.get_rx_length`, `text.get_rx`, `text.clear_rx`, `rx.get_data`, `tx.get_data` |
| log | `log.clear`, `log.get_call`/`set_call`, `log.get_name`/`set_name`, `log.get_qth`/`set_qth`, `log.get_locator`/`set_locator`, `log.get_rst_in`/`set_rst_in`, `log.get_rst_out`/`set_rst_out`, `log.get_serial_number`/`set_serial_number`, `log.get_exchange`/`set_exchange`, `log.get_frequency`, `log.get_band`, `log.get_time_on`, `log.get_time_off` |

- Názvy modemů pro `modem.*`: `RTTY` (a jednotlivé módy jako `RTTY-45`).
- `modem.get_carrier` / `set_carrier` = střed mezi mark a space v Hz.
- `log.*` pracuje s aktuálním QSO oknem Engine.
- Neznámá metoda → XML-RPC fault `-32601`.

### 7.2 Vlastní JSON-RPC 2.0 přes WebSocket (`ws://127.0.0.1:7363/v1`)

**Metody:**

| Jmenný prostor | Metody |
|---|---|
| `engine` | `status`, `tx`, `rx`, `rxNow`, `tune` |
| `tx` | `send(text)`, `sendRaw(codes)`, `clear`, `pending` |
| `modem` | `list`, `select(id, mode)`, `getParams`, `setParams({…})`, `describeParams` |
| `profile` | `list`, `load(slot)`, `save(slot, name)`, `delete(slot)` |
| `rig` | `status`, `getFreq`, `setFreq(hz)`, `setMode(mode)` |
| `macro` | `list`, `run(index)`, `stop` |
| `qso` | `getCurrent`, `setField(name, value)`, `clear`, `log` |
| `log` | `query({call?, from?, to?, limit?})`, `update(id, fields)`, `delete(id)` |
| `spectrum` | `get({bins?})`, `stream({fps, bins})`, `stopStream` |
| `events` | `subscribe([názvy])`, `unsubscribe([názvy])` |

RTTY parametry (`modem.setParams`): `baud`, `mark`, `shift`, `reverse`, `afc`, `afcMode`, `net`, `atc`, `squelch`, `squelchLevel`, `demodType` (`iir`/`fir`/`pll`/`fft`), `bpf`, `lms`, `notch`, `integrator`, `bitLength`, `stopBits`, `parity`, `uos`, `diddle`.

**Notifikace** (jen odebírané):

| Událost | Obsah |
|---|---|
| `rx.char` | znak, `echo` (bool) |
| `tx.progress` | odeslané znaky, zbývá |
| `engine.state` | `rx` / `tx` / `drain` / `tune` |
| `signal.level` | úroveň, squelch otevřen (~10 Hz) |
| `afc.changed` | mark, space |
| `fig.changed` | LTRS/FIGS |
| `rig.freq`, `rig.status` | frekvence, mód, online |
| `qso.logged`, `qso.updated`, `qso.deleted` | QSO záznam |
| `spectrum` | pole magnitud (jen při `spectrum.stream`) |
| `error` | kód, zpráva (výpadek zvuku, rigu, portu) |

Chybové kódy: standardní JSON-RPC a vlastní rozsah `-32000…-32099` (např. `-32001` TX odmítnuto – PTT nedostupné). Kompletní schéma s příklady bude v `docs/api.md`.

## 8. GUI (SwiftUI)

- **Horní panel:** frekvence z rigu, modem a mód, stav RX/TX, přepínače AFC, NET, REV, ATC, SQ, HAM (170 Hz), baud, výběr profilu.
- **Vodopád nebo spektrum:** kurzory mark/space, kliknutí = naladění, kolečko = squelch. Metal nebo Canvas. Rozsah a zesílení nastavitelné.
- **XY scope:** volitelný panel.
- **RX text:** kliknutí na slovo ho vloží do pole Call / Name / QTH (podle obsahu nebo modifikátoru).
- **TX text:** režim po znacích, slovech nebo řádcích.
- **Makra:** F1–F12 a editor.
- **QSO okno:** Call, Name, QTH, Locator, RST s/r, Exch, Serial, Notes. Indikace předchozích spojení s protistanicí.
- **Minilog:** samostatné okno s tabulkou, řazením, hledáním, úpravou a mazáním.
- **Nastavení:** audio, klíčování, rig, API, RTTY parametry, makra, log.

## 9. Makra

Proměnné převzaté z MMTTY (`ConvString`):

| Makro | Význam |
|---|---|
| `%m` | moje značka |
| `%c` | značka protistanice |
| `%n` | jméno (výchozí „OM“) |
| `%q` | QTH |
| `%r` / `%s` | RST přijaté / odeslané |
| `%R` `%N` `%M` | části závodního výměnného kódu (jako MMTTY) |
| `%g` | pozdrav podle času (GM/GA/GE) |
| `%D` `%T` `%t` | UTC datum a čas (formáty přesně podle `ConvString` v MMTTY) |
| `%L` / `%F` | vynutit LTRS / FIGS |
| `%E` | konec |
| `%{text}` | CW ID (Morse klíčované nosnou přes Baudot řídicí kódy) |
| `\` na konci | po odvysílání přepnout na RX |
| `#` na konci | zůstat na TX (diddle) |

Navíc:
- `%l` zapíše aktuální QSO do logu,
- opakování makra v intervalu (CQ smyčka), zastaví se příjmem znaku nebo klávesou.

## 10. Log

- **ADIF (`.adi`)**: po každém spojení se záznam připíše na konec a zavolá se `fsync`. Hlavička (`ADIF_VER` 3.1.4, `PROGRAMID` `mmtty4mac`, `PROGRAMVERSION`) se zapíše při vytvoření souboru.
- Pole: `CALL`, `QSO_DATE`, `TIME_ON`, `TIME_OFF`, `FREQ`, `BAND`, `MODE`, `SUBMODE`, `RST_SENT`, `RST_RCVD`, `NAME`, `QTH`, `GRIDSQUARE`, `STX`, `SRX`, `STX_STRING`, `SRX_STRING`, `COMMENT`, `STATION_CALLSIGN`, `APP_MMTTY4MAC_ID`.
- **JSON Lines (`.jsonl`)**: jeden JSON objekt na řádek se stejnými daty a polem `id` (UUID). Slouží jako zdroj pro minilog a pro externí nástroje.
- **Párování:** `id` je v JSONL jako `id` a v ADIF jako `APP_MMTTY4MAC_ID`.
- **Oprava a mazání:** v paměti se upraví seznam, oba soubory se zapíšou do dočasných souborů a atomicky přejmenují. Další spojení se pak znovu připisují na konec.
- **Zdroj pravdy** je `.jsonl`. Pokud se soubory rozejdou (např. ruční úprava ADIF), nabídne aplikace přegenerování `.adi` z `.jsonl`.
- Frekvence a pásmo se doplní automaticky z rigu.

## 11. Nastavení a profily

- Soubor `~/Library/Application Support/mmtty4mac/settings.json`, sekce `audio`, `keying`, `rig`, `api`, `station` (značka, lokátor), `modems.rtty`, `macros`, `log`, `ui`.
- Verze schématu v souboru (`schemaVersion`) kvůli migracím.
- **Profily:** 16 slotů s parametry modemu (jako `UserPara.ini` v MMTTY), soubor `profiles.json`.
- Neplatné nebo chybějící hodnoty → výchozí hodnota a varování v logu aplikace. Aplikace nikdy nespadne kvůli nastavení.

## 12. Chyby a bezpečnost vysílání

- Výpadek zvukového zařízení, rigu nebo portu není fatální: stav v GUI, událost `error` v API, automatické znovupřipojení.
- Vysílání se odmítne (chyba `-32001` / hláška v GUI), pokud zvolený zdroj PTT není dostupný.
- PTT časovač vypne vysílání po nastavené době.
- Při ukončení aplikace, pádu API klienta i při chybě DSP vlákna se vždy vypne PTT a FSK linka se vrátí do klidového stavu (mark).
- Diagnostický log aplikace přes `os.Logger`.

## 13. Testování

- **Golden testy jádra:** sada WAV nahrávek (vygenerované pro různé baudy a shifty a skutečné RTTY z pásma) → dekódovaný text se porovná s očekávaným. Totéž pro všechny typy demodulátoru.
- **Smyčka TX→RX:** `generateTx` → `processRx` musí vrátit stejný text. Varianty s šumem (SNR) a posunutou frekvencí (ověření AFC), měří se chybovost znaků.
- **Referenční srovnání s originálem:** první extrakce jádra (jen nutné úpravy pro překlad, bez refaktoringu) vygeneruje referenční výstupy pro golden WAV sadu a ty se commitnou. Každá další úprava jádra musí dát bitově stejný dekódovaný text.
- **Unit testy:** Baudot tabulky (LTRS/FIGS, UOS, US-TTY / J-BELL), makra, ADIF a JSONL (zápis, oprava, mazání, obnova po přerušení), stavový automat RX/TX, parsování nastavení.
- **Integrační testy:** `HamlibClient` proti falešnému `rigctld` serveru, `FlrigClient` proti falešnému flrig serveru, fldigi XML-RPC a JSON-RPC proti testovacím klientům.
- **Ruční kontrolní seznam** pro hardware: zvukovka a výběr kanálu, PTT RTS/DTR, `fsk-uart` s FTDI, `fsk-soft` (měření časování osciloskopem nebo druhým přijímačem), skutečné spojení.

## 14. Licence a atribuce

- Celý projekt: **GNU LGPL v3**. `COPYING` a `COPYING.LESSER` v kořeni repozitáře.
- `MMTTYCore`: zachovány původní hlavičky „Copyright 2000–2013 Makoto Mori, Nobuyuki Oba“ a doplněn copyright úprav.
- Odkaz na původní projekt (`n5ac/mmtty`, mm-open.org) v README a v okně „O aplikaci“.
