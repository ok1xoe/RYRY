# Plán 2: Engine, AudioIO, klíčování a ovládání rigu – implementační plán

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Postavit „mozek“ aplikace. `Engine` řídí RX/TX stavový automat nad `Modem`, zvuk přes CoreAudio, PTT (CAT, RTS/DTR, VOX), skutečné FSK (UART TxD a softwarově časované) a ovládání rigu přes hamlib `rigctld` a flrig.

**Architecture:** Každý hardwarový prvek je za Swift protokolem s reálnou a falešnou implementací: `AudioBackend`, `SerialPort`, `Rig`, `Clock`. `Engine` je testovatelný bez hardwaru, falešný backend pumpuje zvuk synchronně. DSP běží v jednom sériovém kontextu (`DispatchQueue` Engine). Zvukové render callbacky jen kopírují vzorky přes lock-free SPSC ring buffer (C11 atomics v malém C targetu). XML-RPC kodek je samostatný target, protože ho znovu použije plán 4 (server kompatibilní s fldigi).

**Tech Stack:** Swift 6, AVFoundation/AVAudioEngine, CoreAudio (výběr zařízení), Network.framework (TCP), URLSession (flrig), POSIX termios + IOKit `IOSSIOSPEED`, C11 `<stdatomic.h>`.

**Spec:** `docs/superpowers/specs/2026-09-28-mmtty4mac-design.md` (sekce 5, 6, 12)

**Předchozí plán:** `docs/superpowers/plans/2026-09-29-plan1-rtty-core.md` (hotový: `MMTTYCore`, `ModemKit`, `RTTYModem`, `rtty-tool`).

## Global Constraints

- macOS 14+, swift-tools-version 6.0, Swift 6 language mode, C++17 / C11. Build a testy vždy s `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Licence LGPL v3. Nové soubory mají hlavičku `// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3`.
- Pracovní frekvence modemu RTTY 11025 Hz. Zvukové zařízení typicky 48000 Hz, převod přes `AVAudioConverter`.
- Výchozí porty: rigctld `127.0.0.1:4532`, flrig `http://127.0.0.1:12345/RPC2`.
- **PTT tail:** po skončení `generateTx` zůstává PTT zapnuté ještě `pttTail` (výchozí 0,2 s), aby protistanice dekódovala poslední znak (ruling z plánu 1, Task 5).
- **Bezpečnost:** při chybě, ukončení Engine (`stop()`/`deinit`) a vypršení PTT časovače se vždy vypne PTT a FSK linka se vrátí na mark.
- Ve zvukovém render callbacku žádné alokace, zámky ani Swift `async`.
- FSK přes UART: 5 datových bitů, `CSTOPB` (macOS termios neumí 1,5 stop bitu, 2 stop bity RTTY přijímače tolerují), rychlost přes `IOSSIOSPEED`. Kódy se před zápisem bitově obracejí (vnitřní pořadí MMTTY je obrácené oproti ITA2, viz `CRTTY` `_TTY` tabulka a `Comm.cpp` `OutData`).

## Review Focus

1. **Rig nebo sériový port zmizí uprostřed vysílání** (odpojený USB kabel, rigctld spadne) → Engine přejde do RX, PTT se pokusí vypnout všemi dostupnými cestami, pošle `EngineEvent.error` a nezasekne se ve stavu TX. Test v Task 8.
2. **`tx()` bez dostupného zdroje PTT** (CAT PTT a rig offline, sériový port nejde otevřít) → vysílání se odmítne s chybou, nic se nevysílá. Test v Task 8.
3. **Opakované nebo souběžné příkazy** (`tx()` během TX, `rx()` během DRAIN, `rxNow()` během PTT_ON, `stop()` během TX) → idempotentní, žádný dvojí PTT ani zaseknutý stav. Test v Task 8.
4. **Neplatná odpověď rigctld nebo flrig** (`RPRT -1`, nečíselná frekvence, XML fault, timeout) → typovaná chyba, klient zůstane použitelný. Testy v Task 2 a 3.
5. **UART neumí 45,45 Bd** (CH340, PL2303) → `IOSSIOSPEED` selže nebo port hlásí jinou rychlost → srozumitelná chyba „použijte fsk-soft“. Test v Task 5 přes falešný port.

---

## Struktura souborů

```
Sources/
  XMLRPC/            XMLRPCValue.swift, XMLRPCCodec.swift
  RigControl/        Rig.swift, NoRig.swift, LineConnection.swift, HamlibClient.swift,
                     FlrigClient.swift, XMLRPCTransport.swift
  CRingBuffer/       include/CRingBuffer.h, CRingBuffer.c      (SPSC float ring, C11 atomics)
  AudioIO/           RingBuffer.swift, SampleRateConverter.swift, AudioDevices.swift,
                     AudioBackend.swift, CoreAudioBackend.swift
  Keying/            SerialPort.swift, POSIXSerialPort.swift, PTTController.swift,
                     FSKKeyer.swift, UARTFSKKeyer.swift, SoftFSKKeyer.swift, Clock.swift
  Engine/            Engine.swift, EngineConfig.swift, EngineEvent.swift, TxStateMachine.swift
  MMTTYCore/         (+ rttycore_read_fsk_codes)
  RTTYModem/         (+ takeFskCodes)
  ModemKit/          (+ Modem.takeFskCodes s výchozí implementací)
  rtty-tool/         (+ příkazy devices, live)
Tests/
  XMLRPCTests/, RigControlTests/ (FakeRigctld, StubTransport), AudioIOTests/,
  KeyingTests/ (FakeSerialPort, ManualClock), EngineTests/ (FakeAudioBackend), MMTTYCoreTests/
```

---

### Task 1: XMLRPC kodek

**Files:** `Sources/XMLRPC/XMLRPCValue.swift`, `Sources/XMLRPC/XMLRPCCodec.swift`, `Tests/XMLRPCTests/XMLRPCCodecTests.swift`, `Package.swift`

**Interfaces (Produces):**
```swift
public indirect enum XMLRPCValue: Sendable, Equatable {
    case int(Int), bool(Bool), string(String), double(Double), base64(Data)
    case array([XMLRPCValue]), dict([String: XMLRPCValue]), nil_
}
public struct XMLRPCFault: Error, Equatable, Sendable { public let code: Int; public let message: String }
public enum XMLRPCCodecError: Error, Equatable { case malformed(String) }
public enum XMLRPCCodec {
    public static func encodeCall(method: String, params: [XMLRPCValue]) -> Data
    public static func decodeCall(_ data: Data) throws -> (method: String, params: [XMLRPCValue])
    public static func encodeResponse(_ value: XMLRPCValue) -> Data
    public static func encodeFault(_ fault: XMLRPCFault) -> Data
    /// Vrací hodnotu, nebo hodí XMLRPCFault / XMLRPCCodecError.
    public static func decodeResponse(_ data: Data) throws -> XMLRPCValue
}
```
Pravidla: `<value>text</value>` bez typu = string (podle specifikace XML-RPC). `i4`/`int`, `boolean` 0/1, `double`, `base64`, `struct`/`member`, `array`/`data`, `nil`. Escapování `& < >`.

**Testy (RED → GREEN):** round-trip všech typů v call i response; string bez tagu typu; fault → `XMLRPCFault(code:message:)`; poškozené XML → `XMLRPCCodecError.malformed`; ukázka skutečné odpovědi fldigi/flrig (`<methodResponse><params><param><value>14070000</value></param></params></methodResponse>` → `.string("14070000")`).

- [ ] Step 1: napsat testy, target do Package.swift, spustit, musí selhat na chybějících typech
- [ ] Step 2: implementovat enkodér (skládání řetězce) a dekodér (`XMLParser` s delegátem, zásobník hodnot)
- [ ] Step 3: `swift test --filter XMLRPCTests` → PASS
- [ ] Step 4: commit `feat(xmlrpc): XML-RPC value codec (calls, responses, faults)`

---

### Task 2: RigControl – protokol, NoRig, HamlibClient

**Files:** `Sources/RigControl/{Rig,NoRig,LineConnection,HamlibClient}.swift`, `Tests/RigControlTests/{FakeRigctld,HamlibClientTests}.swift`

**Interfaces (Produces):**
```swift
public enum RigError: Error, Equatable, Sendable {
    case offline, timeout, protocolError(String), rejected(Int)   // rigctld RPRT <n>
}
public struct RigStatus: Sendable, Equatable {
    public var online: Bool; public var frequency: Double?; public var mode: String?; public var ptt: Bool?
}
public protocol Rig: AnyObject, Sendable {
    var name: String { get }
    func connect() async throws
    func disconnect() async
    func frequency() async throws -> Double
    func setFrequency(_ hz: Double) async throws
    func mode() async throws -> String
    func setMode(_ mode: String) async throws
    func setPTT(_ on: Bool) async throws
}
public final class NoRig: Rig   // frequency() hodí RigError.offline; setPTT hodí .offline
/// Jedno TCP spojení s řádkovým protokolem, request/response s timeoutem (Network.framework).
public actor LineConnection {
    public init(host: String, port: UInt16, timeout: Duration = .seconds(2))
    public func open() async throws
    public func close()
    public func request(_ line: String, responseLines: Int) async throws -> [String]
}
public final class HamlibClient: Rig   // rigctld: f, F <hz>, m, M <mode> 0, T 0|1
```
Protokol rigctld (default, ne rozšířený):
- `f\n` vrátí 1 řádek s frekvencí v Hz.
- `m\n` vrátí 2 řádky: mód a šířku pásma.
- `F`, `M` a `T` vrátí `RPRT 0` (úspěch) nebo `RPRT -n`, to je chyba `.rejected(n)`.
- Výpadek spojení → `.offline`. Při dalším volání se klient pokusí jednou znovu připojit.

**FakeRigctld (test support):** `NWListener` na náhodném portu, drží stav (freq, mode, ptt), umí režim „vrať RPRT -1“, „neodpovídej“ (test timeoutu) a „zavři spojení“.

**Testy:** čtení a nastavení frekvence, módu a PTT proti fake. `RPRT -1` → `.rejected(-1)`. Nečíselná frekvence → `.protocolError`. Timeout → `.timeout`. Fake zavře spojení → `.offline`, po znovuspuštění fake se další volání samo připojí. `NoRig` → `.offline`.

- [ ] Step 1: testy + FakeRigctld → RED
- [ ] Step 2: `LineConnection` (NWConnection, čtení po řádcích s bufferem, `withTimeout`), `HamlibClient`, `NoRig`
- [ ] Step 3: `swift test --filter RigControlTests` → PASS
- [ ] Step 4: commit `feat(rig): Rig protocol, rigctld client with reconnect`

---

### Task 3: FlrigClient

**Files:** `Sources/RigControl/{XMLRPCTransport,FlrigClient}.swift`, `Tests/RigControlTests/FlrigClientTests.swift`

**Interfaces:**
```swift
public protocol XMLRPCTransport: Sendable { func call(_ method: String, _ params: [XMLRPCValue]) async throws -> XMLRPCValue }
public struct HTTPXMLRPCTransport: XMLRPCTransport { public init(url: URL, timeout: TimeInterval = 2) }
public final class FlrigClient: Rig {
    public init(transport: XMLRPCTransport)
    public convenience init(host: String = "127.0.0.1", port: Int = 12345)
}
```
Mapování:
- `frequency()` → `rig.get_vfo` (vrací string s Hz)
- `setFrequency` → `rig.set_frequency(double)`
- `mode()` → `rig.get_mode`
- `setMode` → `rig.set_mode(string)`
- `setPTT` → `rig.set_ptt(int 0/1)`
- `connect()` → `rig.get_xcvr` (ověření spojení)

Chyba URLSession (spojení odmítnuto) → `RigError.offline`. Timeout → `.timeout`. `XMLRPCFault` → `.protocolError(message)`.

**Testy:** `StubTransport` (zaznamená volání, vrací připravené hodnoty) ověří názvy metod a typy parametrů. Fault, offline a neplatná frekvence (`"abc"`) → typované chyby.

- [ ] Step 1: testy → RED
- [ ] Step 2: implementace
- [ ] Step 3: PASS
- [ ] Step 4: commit `feat(rig): flrig XML-RPC client`

---

### Task 4: FSK kódy z jádra

Modulátor MMTTY určuje časování, diddle i přepínání LTRS/FIGS. FSK klíčovač proto odebírá přesně ty kódy, které modulátor právě začal vysílat, včetně diddle. Zvukový výstup se při FSK zahodí nebo ztlumí.

**Files:** `Sources/MMTTYCore/mmtty/Rtty.{h,cpp}` (minimální hook), `Sources/MMTTYCore/{include/RTTYCore.h,RTTYCore.cpp}`, `Sources/ModemKit/Modem.swift`, `Sources/RTTYModem/RTTYModem.swift`, `Tests/MMTTYCoreTests/CoreFskTests.swift`, `Tests/RTTYModemTests/RTTYModemTests.swift`

**Interfaces:**
```c
/* Kódy (5bit, pořadí bitů MMTTY), které modulátor od posledního volání začal vysílat,
   včetně diddle a LTRS/FIGS. Řídicí kódy 0xFC–0xFF se nevracejí. */
size_t rttycore_read_fsk_codes(RTTYCore* core, uint8_t* out, size_t max);
```
```swift
// ModemKit
extension Modem { public func takeFskCodes() -> [UInt8] { [] } }   // výchozí: modem FSK neumí
// RTTYModem
public func takeFskCodes() -> [UInt8]
```
Hook v `CFSKMOD::Do`: v místě, kde se načte další kód z bufferu (`m_Data = m_Buff[m_rp]`) nebo kde se generuje diddle kód, zapsat kód do malého ring bufferu v `CFSKMOD` (nový člen `BYTE m_FskOut[256]; int m_FskW, m_FskR;` + `int ReadFskCode()`). Změna je aditivní, golden testy musí zůstat beze změny.

**Testy:**
- `queueTx("RY")` → `read_fsk_codes` vrátí (po vygenerování dostatku vzorků) posloupnost obsahující kódy R a Y v pořadí MMTTY (R=0x0A, Y=0x15, viz `_TTY`) a na začátku LTRS (0x1F).
- Diddle bez textu vrací LTRS (0x1F) opakovaně.
- Golden testy beze změny.

- [ ] Step 1: testy → RED
- [ ] Step 2: hook + C API + Swift
- [ ] Step 3: `swift test` celé → PASS, golden beze změny
- [ ] Step 4: commit `feat(core): expose modulated Baudot codes for FSK keying`

---

### Task 5: Keying – SerialPort, PTT, UART FSK

**Files:** `Sources/Keying/{SerialPort,POSIXSerialPort,PTTController,FSKKeyer,UARTFSKKeyer,Clock}.swift`, `Tests/KeyingTests/{FakeSerialPort,PTTControllerTests,UARTFSKKeyerTests}.swift`

**Interfaces:**
```swift
public enum SerialError: Error, Equatable, Sendable {
    case openFailed(String), unsupportedBaud(Double), ioError(String), closed
}
public protocol SerialPort: AnyObject, Sendable {
    var path: String { get }
    func open() throws
    func close()
    func setRTS(_ on: Bool) throws
    func setDTR(_ on: Bool) throws
    func setBreak(_ on: Bool) throws
    /// 5–8 datových bitů, stopBits 1 nebo 2, bez parity, bez řízení toku.
    func configure(baud: Double, dataBits: Int, stopBits: Int) throws
    func write(_ bytes: [UInt8]) throws
    func drain() throws                 // tcdrain
}
public final class POSIXSerialPort: SerialPort   // open O_RDWR|O_NOCTTY|O_NONBLOCK, termios raw, IOSSIOSPEED, TIOCMBIS/BIC, TIOCSBRK/CBRK
public static func availableSerialPorts() -> [String]   // /dev/cu.*

public enum PTTMethod: Sendable, Equatable { case none, cat, rts, dtr, rtsDtr }
public final class PTTController: Sendable {
    public init(method: PTTMethod, port: SerialPort?, rig: Rig?, invert: Bool = false)
    public func prepare() async throws        // otevře port, ověří dostupnost (CAT: rig.connect)
    public func set(_ on: Bool) async throws
    public func forceOff() async              // best effort všemi cestami, nikdy nehází
}

public protocol FSKKeyer: AnyObject, Sendable {
    func start() throws                       // linka na mark
    func send(codes: [UInt8])                 // pořadí bitů MMTTY
    var pending: Int { get }
    func stop()                               // linka na mark, zahodí frontu
}
public final class UARTFSKKeyer: FSKKeyer {
    public init(port: SerialPort, baud: Double = 45.45, invert: Bool = false)
    static func reverse5(_ c: UInt8) -> UInt8
}
public protocol Clock: Sendable { func now() -> UInt64 /*ns*/; func sleep(untilNanos: UInt64) }
public struct HostClock: Clock      // mach_absolute_time + mach_wait_until
```
`UARTFSKKeyer.start()` volá `configure(baud: 45.45, dataBits: 5, stopBits: 2)`. `unsupportedBaud` se propaguje jako srozumitelná chyba. `invert` = výstup přes break/invertovaný adaptér, zde jen XOR datových bitů není možné, proto `invert` u UART znamená chybu `.openFailed("invert not supported on UART, use fsk-soft")`.

**FakeSerialPort:** zaznamenává `[(time, event)]`, konfigurovatelně hází `unsupportedBaud`.

**Testy:**
- PTT RTS / DTR / RTS+DTR / invert → správné volání na portu.
- PTT CAT → `rig.setPTT`.
- `forceOff` nehází ani při chybě portu.
- `reverse5`: 0x01 → 0x10, 0x0A → 0x0A.
- UART keyer zapíše obrácené kódy ve stejném pořadí.
- `unsupportedBaud` → chyba obsahuje „fsk-soft“ (Review Focus 5).

- [ ] Step 1: testy → RED
- [ ] Step 2: implementace (POSIX část bez unit testu, jen kompilace + ruční test v Task 9)
- [ ] Step 3: PASS
- [ ] Step 4: commit `feat(keying): serial port, PTT controller, UART FSK keyer`

---

### Task 6: Softwarově časované FSK (náhrada EXTFSK)

**Files:** `Sources/Keying/SoftFSKKeyer.swift`, `Tests/KeyingTests/{ManualClock,SoftFSKKeyerTests}.swift`

**Interfaces:**
```swift
public enum FSKLine: Sendable { case txdBreak, dtr, rts }
public final class SoftFSKKeyer: FSKKeyer {
    public init(port: SerialPort, line: FSKLine, baud: Double = 45.45, stopBits: Double = 1.5,
                invert: Bool = false, clock: Clock = HostClock())
}
```
Vlákno (`Thread`, QoS `.userInteractive`, pro `HostClock` time-constraint policy přes `thread_policy_set`) bere kódy z fronty. Každý znak: start (space) 1 bit, 5 datových bitů (pořadí ITA2 LSB-first, tj. `reverse5` z kódu MMTTY) a stop (mark) `stopBits`. Časy se počítají absolutně od začátku znaku, takže chyba nekumuluje. Mark = linka neaktivní (`break off` / DTR/RTS low), s `invert` naopak. Prázdná fronta = mark.

**ManualClock:** `sleep(until)` okamžitě posune čas. Test tak běží deterministicky a rychle.

**Testy:**
- Pro kód `Y` (MMTTY 0x15) a DTR: posloupnost přechodů linky a časy (±1 µs na ManualClock) odpovídají 22,002 ms na bit a 33,003 ms stop.
- `invert` prohodí úrovně.
- `stop()` nastaví mark.
- `pending` klesá.

- [ ] Step 1: testy → RED
- [ ] Step 2: implementace
- [ ] Step 3: PASS
- [ ] Step 4: commit `feat(keying): software-timed FSK keyer (EXTFSK replacement)`

---

### Task 7: AudioIO – ring buffer, převod frekvence, backend

**Files:** `Sources/CRingBuffer/{include/CRingBuffer.h,CRingBuffer.c}`, `Sources/AudioIO/{RingBuffer,SampleRateConverter,AudioDevices,AudioBackend,CoreAudioBackend}.swift`, `Tests/AudioIOTests/*.swift`

**Interfaces:**
```c
typedef struct CRingBuffer CRingBuffer;
CRingBuffer* cring_create(size_t capacity);   void cring_destroy(CRingBuffer*);
size_t cring_write(CRingBuffer*, const float*, size_t);  /* producent */
size_t cring_read(CRingBuffer*, float*, size_t);          /* konzument */
size_t cring_available(const CRingBuffer*);
```
```swift
public final class RingBuffer: @unchecked Sendable { init(capacity: Int); write/read/available }
public final class SampleRateConverter {
    public init(from: Double, to: Double) throws
    public func process(_ input: [Float]) -> [Float]    // stavový, blokově
}
public struct AudioDevice: Sendable, Hashable { public let id: UInt32; public let uid: String; public let name: String; public let inputChannels: Int; public let outputChannels: Int }
public enum AudioDevices { public static func all() -> [AudioDevice]; public static func defaultInput() -> AudioDevice?; public static func defaultOutput() -> AudioDevice? }
public enum AudioChannel: Sendable { case left, right, mono }
public struct AudioConfig: Sendable { public var inputUID: String?; public var outputUID: String?; public var inputChannel: AudioChannel = .left; public var outputChannel: AudioChannel = .mono }
/// Backend dodává RX vzorky na frekvenci modemu a bere TX vzorky na frekvenci modemu.
public protocol AudioBackend: AnyObject, Sendable {
    func start(modemRate: Double, config: AudioConfig) throws
    func stop()
    func readRx(into: inout [Float]) -> Int          // nepřevzaté RX vzorky (modemRate)
    func writeTx(_ samples: [Float]) -> Int          // vrací přijaté (backpressure)
    var txQueued: Int { get }                        // vzorky čekající na výstup
    var isRunning: Bool { get }
}
public final class CoreAudioBackend: AudioBackend   // AVAudioEngine input tap + AVAudioSourceNode
```

**Testy:**
- Ring buffer: FIFO, plný/prázdný, wrap-around, stress test 1 producent a 1 konzument ve dvou vláknech (1e6 vzorků, bez ztráty a v pořadí).
- Převodník 48000→11025: tón 2125 Hz zůstane 2125 Hz (±2 Hz, průchody nulou) a počet vzorků odpovídá poměru (±1 %).
- Převodník 11025→48000 zpět obdobně.
- `AudioDevices.all()` nespadne (výsledek může být prázdný na CI).
- `CoreAudioBackend` jen kompilace + ruční test v Task 9.

- [ ] Step 1: testy → RED
- [ ] Step 2: implementace
- [ ] Step 3: PASS
- [ ] Step 4: commit `feat(audio): lock-free ring buffer, sample-rate converter, CoreAudio backend`

---

### Task 8: Engine – stavový automat RX/TX

**Files:** `Sources/Engine/{Engine,EngineConfig,EngineEvent,TxStateMachine}.swift`, `Tests/EngineTests/{FakeAudioBackend,EngineTests}.swift`

**Interfaces:**
```swift
public enum TxOutput: Sendable, Equatable { case afsk, fskUART(path: String), fskSoft(path: String, line: FSKLine) }
public struct EngineConfig: Sendable {
    public var audio = AudioConfig()
    public var ptt: PTTMethod = .none
    public var pttPort: String? = nil
    public var pttInvert = false
    public var txOutput: TxOutput = .afsk
    public var fskInvert = false
    public var audioDuringFSK = false
    public var txDelay: Duration = .milliseconds(0)    // PTT → modulace
    public var pttTail: Duration = .milliseconds(200)  // konec modulace → PTT off
    public var pttTimeout: Duration = .seconds(600)
    public init() {}
}
public enum EngineState: String, Sendable { case stopped, rx, pttOn, tx, drain, pttOff }
public enum EngineError: Error, Equatable, Sendable { case pttUnavailable(String), audio(String), keying(String), rig(String), notRunning }
public enum EngineEvent: Sendable {
    case state(EngineState)
    case modem(ModemEvent)
    case rig(RigStatus)
    case error(EngineError)
    case pttTimeout
}
public final class Engine: @unchecked Sendable {
    public init(modem: Modem, rig: Rig = NoRig(), audio: AudioBackend, config: EngineConfig,
                serialFactory: @escaping @Sendable (String) -> SerialPort = { POSIXSerialPort(path: $0) },
                clock: Clock = HostClock())
    public var events: AsyncStream<EngineEvent> { get }     // každé volání = nový odběratel (broadcast)
    public var state: EngineState { get }
    public func start() async throws          // audio, rig connect (neblokující při chybě), DSP smyčka
    public func stop() async                  // forceOff PTT, keyer.stop, audio stop
    public func tx() async throws
    public func tune() async throws
    public func rx()                          // RX po dovysílání (DRAIN)
    public func rxNow()
    public func send(text: String)            // do fronty modemu (v TX), jinak se uloží a odvysílá po tx()
    public func clearTx()
    public func withModem<T>(_ body: (Modem) throws -> T) rethrows -> T   // serializovaný přístup (parametry)
    /// Pro testy a FakeAudioBackend: provede jeden krok DSP synchronně.
    public func pumpForTesting()
}
```
Chování:
- DSP smyčka běží na sériové `DispatchQueue` řízené časovačem 20 ms (reálný backend) nebo `pumpForTesting()`. V každém kroku: `readRx` → `modem.processRx`. Ve stavech TX a DRAIN `modem.generateTx` → `audio.writeTx` (nebo zahodit při FSK bez audia) a `modem.takeFskCodes()` → `keyer.send`.
- `tx()`:
  1. Stav musí být `rx`, jinak nic (idempotence).
  2. `ptt.prepare` → při chybě `EngineError.pttUnavailable` a stav zůstává `rx`.
  3. `ptt.set(true)` → `pttOn`, po `txDelay` stav `tx`: `modem.beginTx`, keyer start.
- `rx()` ve `tx` → `drain`. V `drain`, když `modem.txPending == 0` a výstupní fronta audia i keyeru je prázdná → `modem.stopTx`. Po `.finished` čeká `pttTail`, pak `ptt.set(false)` → `rx`.
- `rxNow()` → `modem.abortTx`, keyer stop, audio TX fronta vyprázdnit, PTT off → `rx`.
- PTT časovač: po `pttTimeout` od `pttOn` → `rxNow()` + událost `.pttTimeout`.
- Chyba PTT, audia nebo keyeru během TX → `rxNow()` s `forceOff` + `.error`.
- Rig: Engine se na začátku pokusí `rig.connect()`. Poll `frequency()` každou 1 s v samostatném `Task`, výsledky jako `.rig(RigStatus)`. Výpadek → `online=false`, další poll = pokus o znovupřipojení. Při `ptt == .cat` a `online == false` → `tx()` hodí `pttUnavailable`.

**FakeAudioBackend:** RX vzorky z pole (např. `RTTYSignalGenerator`), TX vzorky se ukládají, `txQueued` konfigurovatelně (simulace výstupní latence).

**Testy:**
- RX: zvuk z generátoru → události `.modem(.rxText)` dají text.
- Plný TX cyklus s `FakeSerialPort` (RTS PTT): pořadí PTT on → první nenulový TX vzorek nejdříve po `txDelay` → text → `rx()` → drain → PTT off až po `pttTail`. Odvysílané audio dekódované `RTTYModem` obsahuje text.
- `rxNow()` během TX → PTT off a stav `rx`.
- `pttTimeout` (krátký) → `.pttTimeout` a PTT off.
- CAT PTT s `NoRig` → `pttUnavailable`, žádný TX vzorek (Review Focus 2).
- Port hodí chybu při `setRTS(true)` → `pttUnavailable`.
- Port hodí chybu uprostřed TX → `.error` a stav `rx` (Review Focus 1).
- Idempotence: `tx(); tx()`, `rx(); rx()`, `stop()` během TX → forceOff (Review Focus 3).
- FSK UART s `FakeSerialPort`: zapsané bajty = obrácené kódy textu. Audio výstup je nulový, když `audioDuringFSK == false`.

- [ ] Step 1: testy → RED
- [ ] Step 2: implementace
- [ ] Step 3: `swift test` celé → PASS
- [ ] Step 4: commit `feat(engine): RX/TX state machine with PTT, FSK, rig polling`

---

### Task 9: rtty-tool `devices` a `live` + ruční ověření hardwaru

**Files:** `Sources/rtty-tool/main.swift`, `README.md`, `docs/hardware-checklist.md`

- `rtty-tool devices` vypíše zvuková zařízení (UID, název, kanály) a sériové porty.
- `rtty-tool live [--in UID] [--out UID] [--ptt none|rts|dtr|cat] [--port /dev/cu.x] [--rig none|hamlib|flrig] [--fsk uart|soft-dtr|soft-rts|soft-break]` spustí Engine a vypisuje dekódovaný text na stdout. Řádek ze stdin = odvysílat (`tx`, text, `rx`), `:q` = konec.
- `docs/hardware-checklist.md` obsahuje ruční kontrolní seznam ze specifikace (sekce 13): zvukovka a kanál, PTT RTS/DTR, fsk-uart s FTDI, fsk-soft (měření časování), rigctld (`rigctld -m 1` dummy rig), flrig.

Ověření na tomto stroji bez rádia:
- `rtty-tool devices`
- `rtty-tool live` s výchozím vstupem, kdy se `rtty-tool gen` WAV přehrává přes `afplay` do smyčky (pokud je k dispozici loopback, jinak jen ověřit, že běží bez chyb)
- `rigctld -m 1 &` (hamlib dummy, pokud je nainstalovaný přes brew) a `live --rig hamlib --ptt cat` → PTT příkazy v logu rigctld

- [ ] Step 1: implementace
- [ ] Step 2: ruční ověření (výsledky do ledgeru)
- [ ] Step 3: commit `feat(cli): devices and live commands; hardware checklist`
