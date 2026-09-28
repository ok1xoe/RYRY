# Plán 1: RTTY jádro (MMTTYCore + ModemKit + RTTYModem + rtty-tool) – implementační plán

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Z původního MMTTY vytáhnout RTTY DSP jádro do samostatné C++ knihovny bez závislosti na Windows, zabalit ho do Swift modulu implementujícího protokol `Modem` a ověřit ho golden testy a CLI nástrojem, který generuje a dekóduje WAV soubory.

**Architecture:** C++ zdrojáky MMTTY (`Rtty`, `fir`, `CLX`, `Fft`) se převedou do UTF-8 a přeloží přes malou kompatibilní vrstvu (`MMTTYCompat.h`). Nad nimi vznikne C API `rttycore_*` (C++ třída `RTTYCore` schovaná za `extern "C"` funkcemi). Díky tomu Swift nepotřebuje C++ interop mode a C++ se nešíří do dalších targetů. Swift target `ModemKit` definuje obecný protokol `Modem`, `RTTYModem` ho implementuje nad C API. Nezávislý Swift generátor RTTY signálu (vlastní ITA2 tabulka) slouží jako referenční zdroj pro testy, takže se jádro netestuje samo sebou.

**Tech Stack:** Swift 6 (Swift Package Manager, Swift Testing), C++17, macOS 14+. Žádné externí závislosti.

**Spec:** `docs/superpowers/specs/2026-09-28-mmtty4mac-design.md`

**Navazující plány** (napíšou se po dokončení tohoto):
2. AudioIO + Engine (stavový automat RX/TX) + Keying (PTT, FSK UART, FSK soft) + RigControl (hamlib, flrig). Sem patří i `nextFskCode` z jádra.
3. Log (ADIF + JSONL), makra, nastavení a profily.
4. API: fldigi XML-RPC a JSON-RPC.
5. GUI (SwiftUI, vyžaduje Xcode).

## Global Constraints

- Minimální platforma: **macOS 14** (`platforms: [.macOS(.v14)]`), swift-tools-version **6.0**, jazykový režim Swift 6.
- C++ standard: **C++17**.
- Licence: celý projekt **GNU LGPL v3**. Každý převzatý C++ soubor si ponechá původní hlavičku „Copyright 2000-2013 Makoto Mori, Nobuyuki Oba“ a pod ni se přidá řádek `// Modifications Copyright 2026 OK1XOE (mmtty4mac), LGPL v3`.
- Zdroj převzatého kódu: **výhradně** `./mmtty/` (n5ac/mmtty v1.70H). Z `./mmtty-ji1uui/` se přebírají jen tyto tři opravy: `memmove` v `DoFIR`, definice `CFSKDEM::SetSmoozCount`, `CLMS::Clear`.
- Pracovní vzorkovací frekvence modemu RTTY: **11025 Hz** (povolená i 12000 Hz). Jiné hodnoty `rttycore_create` odmítne.
- Rozsah vzorků na rozhraní: `Float` v rozsahu ±1,0. Jádro interně násobí a dělí **32768** (MMTTY pracuje s 16bitovým rozsahem).
- Výchozí hodnoty RTTY: mark **2125 Hz**, space **2295 Hz**, baud **45,45**, 5 bitů, 1,5 stop bitu (MMTTY `m_StopLen = 4` znamená 1,42 bitu, ponechat), AFC zapnuto, `m_FixShift = 1`, `AFCTime 8.0`, `AFCSweep 1.0`, `AFCSQ 32`, echo **1**.
- Japonské komentáře v převzatém kódu zůstávají (jen v UTF-8).
- Známé zvláštnosti originálu (`CVCO` +0,5 kroku, „FFT“ demodulátor bez anti-alias filtru) se **nemění**.
- **Odchylky od specifikace v tomto plánu** (vědomé, zdůvodněné):
  - Rozhraní jádra je C API `rttycore_*` místo C++ třídy viditelné ze Swiftu. Důvod: bez C++ interop mode ve všech závislých targetech. Uvnitř je C++ třída `RTTYCore`, jak spec požaduje.
  - FFT pro AFC a spektrum je převzaté `CFFT` z MMTTY místo vDSP, aby prahy AFC (`AFCSQ`) seděly s originálem. Náhrada vDSP případně později, hlídaná golden testy.
  - Globální proměnné se nahradí kontextem jádra (`CoreContext`), který je aktivní po dobu každého volání C API (`thread_local` ukazatel), místo předávání do každého konstruktoru. Výsledek je stejný: žádný sdílený stav mezi instancemi, více instancí s různou vzorkovací frekvencí. Změna je ale výrazně menší a méně riziková.

## Review Focus

1. **Nepodporovaná vzorkovací frekvence** (např. 44100 nebo 8000 předaná přímo do jádra) → `rttycore_create` vrátí `NULL`, `RTTYModem` hodí chybu. Nesmí spadnout ani tiše dekódovat nesmysly. Test v Task 4.
2. **Hodnota parametru mimo rozsah** (baud 0, mark 0, FIR tap 10000, neznámé ID) → `rttycore_set_param` vrátí chybu a stav jádra se nezmění. Test v Task 4.
3. **Znaky, které Baudot neumí** (malá písmena, `é`, emoji, `@`, tabulátor) ve vysílaném textu → malá písmena se převedou na velká, ostatní se přeskočí, nic nespadne. Test v Task 5.
4. **Dlouhý text nad kapacitu TX bufferu** (MMTTY `MODBUFMAX` = 2048 kódů, `PutData` nad kapacitu **tiše zahazuje**) → `rttycore_queue_tx` vrátí počet přijatých znaků a `RTTYModem` zbytek dodává postupně, takže se odvysílá všechno. Test v Task 10.
5. **Šum bez signálu se zapnutým squelchem a přebuzený vstup** (vzorky > 1,0) → squelch nepustí žádné znaky, přebuzení se nahlásí (`overflow`) a dekódování pokračuje. Test v Task 6.

---

## Struktura souborů

```
Package.swift
COPYING                       (GPL v3 – z ./mmtty/COPYING)
COPYING.LESSER                (LGPL v3 – z ./mmtty/COPYING.LESSER)
README.md
Sources/
  MMTTYCore/                  C++ target
    include/RTTYCore.h        veřejné C API (jediný header viditelný ze Swiftu)
    RTTYCore.cpp              C++ třída RTTYCore + extern "C" funkce
    AFC.h / AFC.cpp           DoAFC vytažené z Sound.cpp
    compat/MMTTYCompat.h      náhrady typů a maker z Windows/VCL a ComLib.h
    compat/CoreContext.h      kontext jádra (bývalé globální proměnné)
    compat/CoreContext.cpp
    mmtty/Rtty.h, Rtty.cpp    převzato z ./mmtty (UTF-8, upraveno)
    mmtty/fir.h, fir.cpp
    mmtty/CLX.h, CLX.cpp
    mmtty/Fft.h, Fft.cpp
  ModemKit/                   Swift: obecné rozhraní modemu
    Modem.swift
    ModeDescriptor.swift
    Parameters.swift
    ModemEvent.swift
  RTTYModem/                  Swift: Modem nad MMTTYCore
    RTTYModem.swift
    RTTYParameters.swift
  WaveFile/                   Swift: čtení a zápis 16bit PCM mono WAV
    WaveFile.swift
  RTTYSignalKit/              Swift: nezávislý generátor RTTY + šum (testy a CLI)
    ITA2.swift
    RTTYSignalGenerator.swift
    NoiseGenerator.swift
  rtty-tool/                  CLI: gen / decode / encode
    main.swift
Tests/
  RTTYSignalKitTests/SignalKitTests.swift
  WaveFileTests/WaveFileTests.swift
  MMTTYCoreTests/CoreRxTests.swift
  MMTTYCoreTests/CoreTxTests.swift
  MMTTYCoreTests/CoreAFCTests.swift
  MMTTYCoreTests/CoreRobustnessTests.swift
  MMTTYCoreTests/GoldenTests.swift
  MMTTYCoreTests/Fixtures/golden/*.wav, *.expected.txt
  ModemKitTests/ParameterTests.swift
  RTTYModemTests/RTTYModemTests.swift
```

---

### Task 1: Kostra balíčku, licence a ověření toolchainu

**Files:**
- Create: `Package.swift`, `COPYING`, `COPYING.LESSER`, `README.md`
- Create: `Sources/WaveFile/WaveFile.swift` (zatím prázdný typ), `Tests/WaveFileTests/WaveFileTests.swift`

**Interfaces:**
- Produces: SPM balíček `mmtty4mac`, na který navazují všechny další tasky.

- [ ] **Step 1: Ověřit toolchain**

Run: `swift --version`
Expected: Swift 6.x. (Na tomto stroji je Swift 6.4 z Command Line Tools. Xcode není nainstalované, pro tento plán není potřeba.)

- [ ] **Step 2: Zkopírovat licence**

```bash
cp mmtty/COPYING COPYING
cp mmtty/COPYING.LESSER COPYING.LESSER
```

- [ ] **Step 3: Vytvořit `Package.swift`** (zatím jen WaveFile, další targety přidávají tasky postupně)

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "mmtty4mac",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WaveFile", targets: ["WaveFile"]),
    ],
    targets: [
        .target(name: "WaveFile"),
        .testTarget(name: "WaveFileTests", dependencies: ["WaveFile"]),
    ],
    cxxLanguageStandard: .cxx17
)
```

- [ ] **Step 4: Minimální zdroj a test, který ověří, že Swift Testing funguje**

`Sources/WaveFile/WaveFile.swift`:
```swift
/// 16bit PCM mono WAV – čtení a zápis (implementace v Task 2).
public enum WaveFile {}
```

`Tests/WaveFileTests/WaveFileTests.swift`:
```swift
import Testing
@testable import WaveFile

@Test func toolchainWorks() {
    #expect(1 + 1 == 2)
}
```

- [ ] **Step 5: Spustit testy**

Run: `swift test`
Expected: `Test toolchainWorks() passed`.
Pokud `import Testing` selže s „no such module 'Testing'“, zastavte se a nahlaste to. Řešením je instalace Xcode (stejně bude potřeba pro plán 5), **nepřepisujte** testy na jiný framework bez souhlasu.

- [ ] **Step 6: README**

`README.md`:
```markdown
# mmtty4mac

Nativní macOS aplikace pro RTTY vycházející z MMTTY (JE3HHT, Makoto Mori).

- Původní zdrojáky: https://github.com/n5ac/mmtty (viz http://mm-open.org)
- Licence: GNU LGPL v3 (viz COPYING a COPYING.LESSER)
- Návrh: docs/superpowers/specs/2026-09-28-mmtty4mac-design.md

## Vývoj

    swift build
    swift test
```

- [ ] **Step 7: Commit**

```bash
git add Package.swift COPYING COPYING.LESSER README.md Sources Tests
git commit -m "chore: SPM package skeleton, LGPL v3 license files"
```

---

### Task 2: WaveFile a nezávislý generátor RTTY signálu

Generátor je **záměrně nezávislý na MMTTY kódu** (vlastní ITA2 tabulka, vlastní modulátor). Testy jádra díky tomu neověřují jádro samo sebou.

**Files:**
- Modify: `Sources/WaveFile/WaveFile.swift`, `Package.swift`
- Create: `Sources/RTTYSignalKit/ITA2.swift`, `Sources/RTTYSignalKit/RTTYSignalGenerator.swift`, `Sources/RTTYSignalKit/NoiseGenerator.swift`
- Test: `Tests/WaveFileTests/WaveFileTests.swift`, `Tests/RTTYSignalKitTests/SignalKitTests.swift`

**Interfaces:**
- Produces:
  - `WaveFile.write(samples: [Float], sampleRate: Int, to url: URL) throws`
  - `WaveFile.read(from url: URL) throws -> (samples: [Float], sampleRate: Int)` (stereo → levý kanál)
  - `ITA2.encode(_ text: String) -> [UInt8]` (5bitové kódy včetně vložených FIGS 0x1B / LTRS 0x1F, začíná LTRS)
  - `struct RTTYSignalGenerator { init(sampleRate: Double = 11025, baud: Double = 45.45, markHz: Double = 2125, shiftHz: Double = 170, stopBits: Double = 1.5, amplitude: Float = 0.5, reverse: Bool = false); func generate(text: String, leadIn: Double = 1.0, tail: Double = 0.5) -> [Float] }`
  - `struct NoiseGenerator { init(seed: UInt64); mutating func gaussian() -> Float; mutating func addNoise(to: inout [Float], rms: Float) }`

- [ ] **Step 1: Napsat failing testy**

`Tests/WaveFileTests/WaveFileTests.swift` (nahradit obsah):
```swift
import Foundation
import Testing
@testable import WaveFile

@Test func roundTripPreservesSamples() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("rt-\(UUID()).wav")
    defer { try? FileManager.default.removeItem(at: url) }
    let input: [Float] = [0, 0.5, -0.5, 1.0, -1.0, 0.25]
    try WaveFile.write(samples: input, sampleRate: 11025, to: url)
    let (out, sr) = try WaveFile.read(from: url)
    #expect(sr == 11025)
    #expect(out.count == input.count)
    for (a, b) in zip(input, out) { #expect(abs(a - b) < 1.0 / 16384) }
}

@Test func clipsOutOfRangeSamples() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("clip-\(UUID()).wav")
    defer { try? FileManager.default.removeItem(at: url) }
    try WaveFile.write(samples: [2.0, -2.0], sampleRate: 8000, to: url)
    let (out, _) = try WaveFile.read(from: url)
    #expect(out[0] > 0.99 && out[1] < -0.99)
}

@Test func rejectsNonWaveData() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("bad-\(UUID()).wav")
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("hello".utf8).write(to: url)
    #expect(throws: WaveFile.Error.self) { try WaveFile.read(from: url) }
}
```

`Tests/RTTYSignalKitTests/SignalKitTests.swift`:
```swift
import Testing
@testable import RTTYSignalKit

@Test func ita2EncodesLettersAndFigures() {
    // LTRS, C=0x0E, Q=0x17, space=0x04, FIGS, 5=0x10
    #expect(ITA2.encode("CQ 5") == [0x1F, 0x0E, 0x17, 0x04, 0x1B, 0x10])
}

@Test func ita2UppercasesAndSkipsUnknown() {
    #expect(ITA2.encode("aé@b") == [0x1F, 0x03, 0x19])
}

@Test func generatorProducesExpectedLength() {
    let g = RTTYSignalGenerator()
    // 1 znak = 1 start + 5 dat + 1,5 stop = 7,5 bitu
    let samples = g.generate(text: "E", leadIn: 0, tail: 0)   // LTRS + E = 2 znaky
    let expected = Int((2 * 7.5 / 45.45 * 11025).rounded())
    #expect(abs(samples.count - expected) <= 2)
}

@Test func generatorToneFrequencyIsMarkWhenIdle() {
    let g = RTTYSignalGenerator()
    let s = g.generate(text: "", leadIn: 1.0, tail: 0)
    // počet průchodů nulou za 1 s ≈ 2 × 2125
    var crossings = 0
    for i in 1..<s.count where (s[i - 1] < 0) != (s[i] < 0) { crossings += 1 }
    #expect(abs(crossings - 4250) < 10)
}

@Test func noiseIsDeterministicAndHasRequestedRMS() {
    var a = NoiseGenerator(seed: 42), b = NoiseGenerator(seed: 42)
    var x = [Float](repeating: 0, count: 20000), y = x
    a.addNoise(to: &x, rms: 0.1); b.addNoise(to: &y, rms: 0.1)
    #expect(x == y)
    let rms = (x.map { $0 * $0 }.reduce(0, +) / Float(x.count)).squareRoot()
    #expect(abs(rms - 0.1) < 0.005)
}
```

- [ ] **Step 2: Přidat targety do `Package.swift`**

Do `targets` přidat:
```swift
        .target(name: "RTTYSignalKit"),
        .testTarget(name: "RTTYSignalKitTests", dependencies: ["RTTYSignalKit"]),
```

- [ ] **Step 3: Spustit testy – musí selhat**

Run: `swift test`
Expected: FAIL při kompilaci (`WaveFile.write`, `ITA2`, `RTTYSignalGenerator`, `NoiseGenerator` neexistují).

- [ ] **Step 4: Implementovat `WaveFile`**

`Sources/WaveFile/WaveFile.swift`:
```swift
import Foundation

/// Minimalistické čtení a zápis PCM WAV (16 bit). Zápis vždy mono, čtení bere 1. kanál.
public enum WaveFile {
    public enum Error: Swift.Error, Equatable {
        case notWave, unsupportedFormat(String), truncated
    }

    public static func write(samples: [Float], sampleRate: Int, to url: URL) throws {
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let dataBytes = UInt32(samples.count * 2)
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + dataBytes)
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16)
        u16(1); u16(1); u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(dataBytes)
        for s in samples {
            let c = max(-1.0, min(1.0, s))
            let v = Int16(clamping: Int((c * 32767).rounded()))
            withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) }
        }
        try d.write(to: url)
    }

    public static func read(from url: URL) throws -> (samples: [Float], sampleRate: Int) {
        let d = try Data(contentsOf: url)
        guard d.count >= 12,
              String(decoding: d[0..<4], as: UTF8.self) == "RIFF",
              String(decoding: d[8..<12], as: UTF8.self) == "WAVE" else { throw Error.notWave }
        func u16(_ o: Int) -> Int { Int(d[o]) | Int(d[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
        var pos = 12
        var channels = 0, rate = 0, bits = 0, format = 0
        while pos + 8 <= d.count {
            let id = String(decoding: d[pos..<pos + 4], as: UTF8.self)
            let size = u32(pos + 4)
            let body = pos + 8
            if id == "fmt " {
                guard body + 16 <= d.count else { throw Error.truncated }
                format = u16(body); channels = u16(body + 2); rate = u32(body + 4); bits = u16(body + 14)
            } else if id == "data" {
                guard format == 1, bits == 16, channels >= 1 else {
                    throw Error.unsupportedFormat("format=\(format) bits=\(bits) ch=\(channels)")
                }
                let end = min(body + size, d.count)
                let frame = 2 * channels
                var out = [Float](); out.reserveCapacity((end - body) / frame)
                var p = body
                while p + 2 <= end {
                    let v = Int16(bitPattern: UInt16(u16(p)))
                    out.append(Float(v) / 32768)
                    p += frame
                }
                return (out, rate)
            }
            pos = body + size + (size & 1)
        }
        throw Error.truncated
    }
}
```

- [ ] **Step 5: Implementovat `ITA2`**

`Sources/RTTYSignalKit/ITA2.swift`:
```swift
/// Nezávislá ITA2 / US-TTY tabulka pro testy (NEsdílí kód s MMTTY CRTTY).
public enum ITA2 {
    public static let ltrs: UInt8 = 0x1F
    public static let figs: UInt8 = 0x1B

    static let letters: [Character: UInt8] = [
        "E": 0x01, "\n": 0x02, "A": 0x03, " ": 0x04, "S": 0x05, "I": 0x06, "U": 0x07,
        "\r": 0x08, "D": 0x09, "R": 0x0A, "J": 0x0B, "N": 0x0C, "F": 0x0D, "C": 0x0E,
        "K": 0x0F, "T": 0x10, "Z": 0x11, "L": 0x12, "W": 0x13, "H": 0x14, "Y": 0x15,
        "P": 0x16, "Q": 0x17, "O": 0x18, "B": 0x19, "G": 0x1A, "M": 0x1C, "X": 0x1D,
        "V": 0x1E,
    ]
    /// Jen znaky společné pro US-TTY i ITA2 (bez $ ! " # & ; ' BELL).
    static let figures: [Character: UInt8] = [
        "3": 0x01, "-": 0x03, "8": 0x06, "7": 0x07, "4": 0x0A, ",": 0x0C, ":": 0x0E,
        "(": 0x0F, "5": 0x10, ")": 0x12, "2": 0x13, "6": 0x15, "0": 0x16, "1": 0x17,
        "9": 0x18, "?": 0x19, ".": 0x1C, "/": 0x1D,
    ]

    /// Text → 5bitové kódy. Začíná LTRS, FIGS/LTRS vkládá podle potřeby.
    /// Mezera, CR a LF jsou v obou registrech (bez přepnutí). Neznámé znaky vynechá.
    public static func encode(_ text: String) -> [UInt8] {
        var out: [UInt8] = [ltrs]
        var inFigs = false
        for ch in text.uppercased() {
            if ch == " " || ch == "\r" || ch == "\n" {
                out.append(letters[ch]!)
            } else if let c = letters[ch] {
                if inFigs { out.append(ltrs); inFigs = false }
                out.append(c)
            } else if let c = figures[ch] {
                if !inFigs { out.append(figs); inFigs = true }
                out.append(c)
            }
        }
        return out
    }
}
```

- [ ] **Step 6: Implementovat generátor a šum**

`Sources/RTTYSignalKit/RTTYSignalGenerator.swift`:
```swift
import Foundation

/// Nezávislý AFSK RTTY generátor se spojitou fází. Mark = nižší tón (jako MMTTY),
/// space = mark + shift. reverse prohodí tóny.
public struct RTTYSignalGenerator: Sendable {
    public var sampleRate: Double, baud: Double, markHz: Double, shiftHz: Double
    public var stopBits: Double, amplitude: Float, reverse: Bool

    public init(sampleRate: Double = 11025, baud: Double = 45.45, markHz: Double = 2125,
                shiftHz: Double = 170, stopBits: Double = 1.5, amplitude: Float = 0.5,
                reverse: Bool = false) {
        self.sampleRate = sampleRate; self.baud = baud; self.markHz = markHz
        self.shiftHz = shiftHz; self.stopBits = stopBits; self.amplitude = amplitude
        self.reverse = reverse
    }

    public func generate(text: String, leadIn: Double = 1.0, tail: Double = 0.5) -> [Float] {
        generate(codes: ITA2.encode(text), leadIn: leadIn, tail: tail)
    }

    public func generate(codes: [UInt8], leadIn: Double = 1.0, tail: Double = 0.5) -> [Float] {
        // Seznam úseků (isMark, délka v bitech)
        var segs: [(Bool, Double)] = []
        if leadIn > 0 { segs.append((true, leadIn * baud)) }
        for c in codes {
            segs.append((false, 1))                                   // start
            for b in 0..<5 { segs.append(((c >> b) & 1 == 1, 1)) }   // LSB první
            segs.append((true, stopBits))                             // stop
        }
        if tail > 0 { segs.append((true, tail * baud)) }

        var out: [Float] = []
        var phase = 0.0
        var tBits = 0.0          // přesný čas v bitech, bez kumulace zaokrouhlení
        var n = 0
        let samplesPerBit = sampleRate / baud
        for (isMark, lenBits) in segs {
            tBits += lenBits
            let end = Int((tBits * samplesPerBit).rounded())
            let mark = isMark != reverse
            let f = mark ? markHz : markHz + shiftHz
            let dphi = 2 * Double.pi * f / sampleRate
            while n < end {
                out.append(amplitude * Float(sin(phase)))
                phase += dphi
                if phase > 2 * Double.pi { phase -= 2 * Double.pi }
                n += 1
            }
        }
        return out
    }
}
```

`Sources/RTTYSignalKit/NoiseGenerator.swift`:
```swift
import Foundation

/// Deterministický gaussovský šum (SplitMix64 + Box–Muller).
public struct NoiseGenerator: Sendable {
    private var state: UInt64
    private var spare: Float?

    public init(seed: UInt64) { state = seed }

    private mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    private mutating func uniform() -> Double {
        (Double(next() >> 11) + 0.5) / Double(1 << 53)
    }

    public mutating func gaussian() -> Float {
        if let s = spare { spare = nil; return s }
        let u1 = uniform(), u2 = uniform()
        let r = (-2 * log(u1)).squareRoot()
        spare = Float(r * sin(2 * .pi * u2))
        return Float(r * cos(2 * .pi * u2))
    }

    public mutating func addNoise(to samples: inout [Float], rms: Float) {
        for i in samples.indices { samples[i] += rms * gaussian() }
    }
}
```

- [ ] **Step 7: Spustit testy**

Run: `swift test`
Expected: všech 8 testů PASS.

- [ ] **Step 8: Commit**

```bash
git add Package.swift Sources/WaveFile Sources/RTTYSignalKit Tests/WaveFileTests Tests/RTTYSignalKitTests
git commit -m "feat: WAV I/O and independent RTTY test signal generator"
```

---

### Task 3: Převzetí C++ zdrojáků MMTTY a jejich přeložení na macOS

Cílem je **přeložitelné jádro s minimem změn**. Chování se nemění, kromě tří oprav z ji1uui. Globální proměnné zatím zůstávají (odstraní je Task 8).

**Files:**
- Create: `Sources/MMTTYCore/mmtty/{Rtty,fir,CLX,Fft}.{h,cpp}` (z `./mmtty`)
- Create: `Sources/MMTTYCore/compat/MMTTYCompat.h`, `Sources/MMTTYCore/compat/CoreGlobals.cpp`
- Create: `Sources/MMTTYCore/include/RTTYCore.h` (prozatím jen verze), `Sources/MMTTYCore/RTTYCore.cpp`
- Modify: `Package.swift`

**Interfaces:**
- Produces: C++ target `MMTTYCore` přeložitelný přes `swift build`. Třídy `CFSKDEM`, `CFSKMOD`, `CRTTY`, `CFFT`, `CLMS` a volné funkce `MakeFilter`, `DoFIR` použitelné z `RTTYCore.cpp`. Globální proměnné definované v `CoreGlobals.cpp`: `SampFreq`, `SampBase`, `DemSamp`, `DemOver`, `FFT_SIZE`, `SampType`, `SampSize`, `FSKCount`, `FSKCount1`, `FSKCount2`, `FSKDeff`, `sys` (typu `CoreSys`) a funkce `InitSampType()`.

- [ ] **Step 1: Převést zdrojáky do UTF-8**

```bash
mkdir -p Sources/MMTTYCore/mmtty Sources/MMTTYCore/compat Sources/MMTTYCore/include
for f in Rtty.h Rtty.cpp fir.h fir.cpp CLX.h CLX.cpp Fft.h Fft.cpp; do
  iconv -f SHIFT_JIS -t UTF-8 "mmtty/$f" > "Sources/MMTTYCore/mmtty/$f" \
    || iconv -c -f SHIFT_JIS -t UTF-8 "mmtty/$f" > "Sources/MMTTYCore/mmtty/$f"
done
# CRLF → LF
sed -i '' $'s/\r$//' Sources/MMTTYCore/mmtty/*
# ‾ (U+203E, vzniká z backslashe v Shift-JIS) zpět na ~ u destruktorů
sed -i '' 's/‾/~/g' Sources/MMTTYCore/mmtty/*
```
Pozor: iconv převádí `\` (0x5C) na `¥`. Zkontrolujte `grep -n '¥' Sources/MMTTYCore/mmtty/*`. V kódu (ne v komentářích) nahraďte `¥` zpět za `\` (typicky `'\0'`, `"\r\n"`). Příkaz: `sed -i '' 's/¥/\\/g' Sources/MMTTYCore/mmtty/*` a pak ručně zkontrolujte diff.

- [ ] **Step 2: Commit čistého převodu** (samostatný commit, aby šly další úpravy snadno zkontrolovat)

```bash
git add Sources/MMTTYCore/mmtty
git commit -m "chore: import MMTTY DSP sources (Rtty, fir, CLX, Fft) as UTF-8, unmodified"
```

- [ ] **Step 3: Vytvořit `compat/MMTTYCompat.h`**

```cpp
// MMTTYCompat.h – náhrady typů a maker z Windows/VCL/ComLib.h pro jádro MMTTY.
// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
#pragma once
#include <cstdint>
#include <cstring>
#include <cstdlib>
#include <cmath>
#include <cstdio>

#define __fastcall
typedef int BOOL;
typedef uint8_t BYTE;
typedef uint16_t WORD;
typedef uint32_t DWORD;
typedef const char* LPCSTR;
typedef char* LPSTR;
#ifndef TRUE
#define TRUE 1
#define FALSE 0
#endif
#define ABS(c) (((c) < 0) ? (-(c)) : (c))

// z ComLib.h
enum { txSound, txTXD, txTXDOnly };

// Podmnožina SYSSET z ComLib.h, kterou jádro skutečně čte.
struct CoreSys {
    double m_SampFreq = 11025.0;
    double m_TxOffset = 0.0;
    int    m_TxPort   = txSound;
    int    m_LWait    = 0;
    int    m_CodeSet  = 0;   // 0 = S-BELL (US), 1 = J-BELL
    int    m_txuos    = 1;
    int    m_dblsft   = 0;
    int    m_FFTGain  = 1;
    int    m_FFTResp  = 2;
};

extern CoreSys sys;
extern double SampFreq, SampBase, DemSamp;
extern int DemOver, FFT_SIZE, SampType, SampSize;
extern int FSKCount, FSKCount1, FSKCount2, FSKDeff;
void InitSampType(void);
```

- [ ] **Step 4: Vytvořit `compat/CoreGlobals.cpp`** (definice a `InitSampType` doslova z `mmtty/ComLib.cpp:125-160`)

```cpp
// Globální proměnné jádra převzaté z ComLib.cpp (Task 8 je přesune do kontextu).
// Copyright 2000-2013 Makoto Mori, Nobuyuki Oba; Modifications Copyright 2026 OK1XOE, LGPL v3
#include "MMTTYCompat.h"

CoreSys sys;
double SampFreq = 11025.0;
double SampBase = 11025.0;
double DemSamp  = 11025.0 * 0.5;
int DemOver = 1, FFT_SIZE = 2048, SampType = 0, SampSize = 1024;
int FSKCount = 0, FSKCount1 = 0, FSKCount2 = 0, FSKDeff = 0;

void InitSampType(void)
{
    if( SampFreq >= 11600.0 ){
        SampType = 3; SampBase = 12000.0; DemSamp = SampFreq * 0.5; DemOver = 1;
        FFT_SIZE = 2048; SampSize = (12000*1024)/11025;
    }
    else if( SampFreq >= 10000.0 ){
        SampType = 0; SampBase = 11025.0; DemSamp = SampFreq * 0.5; DemOver = 1;
        FFT_SIZE = 2048; SampSize = 1024;
    }
    else if( SampFreq >= 7000.0 ){
        SampType = 1; SampBase = 8000.0; DemSamp = SampFreq; DemOver = 0;
        FFT_SIZE = 1024; SampSize = (8000*1024)/11025;
    }
    else if( SampFreq >= 5000.0 ){
        SampType = 2; SampBase = 6000.0; DemSamp = SampFreq; DemOver = 0;
        FFT_SIZE = 1024; SampSize = (6000*1024)/11025;
    }
}
```

- [ ] **Step 5: Upravit převzaté zdrojáky, jen tyto změny:**

1. Ve všech 4 `.cpp` nahradit `#include <vcl.h>` a `#pragma hdrstop` (pokud je) řádkem `#include "../compat/MMTTYCompat.h"`.
2. `fir.h`: odstranit `#include <inifiles.hpp>` a `#include "ComLib.h"`, místo nich `#include "../compat/MMTTYCompat.h"`. Odstranit deklarace `DrawGraph`, `DrawGraph2` a obě `DrawGraphIIR` (používají `Graphics::TBitmap`).
3. `fir.cpp`: odstranit těla funkcí `DrawGraph` (od ř. ~776), `DrawGraph2`, `DrawGraphIIR` (obě přetížení). Najdete je `grep -n 'DrawGraph' Sources/MMTTYCore/mmtty/fir.cpp`.
4. `Rtty.cpp`: v `CVCO::VirtualLock` a v místě s `if( m_vlock ) ::VirtualLock(...)` smazat volání `::VirtualLock(...)` (tělo funkce ponechat prázdné). `::Sleep` jsou jen v blocích `#if 0`, ty nechat.
5. `Fft.h`/`Fft.cpp`: nahradit případné `#include "ComLib.h"` za `#include "../compat/MMTTYCompat.h"`.
6. Hlavičky do všech 8 souborů: pod původní copyright přidat `// Modifications Copyright 2026 OK1XOE (mmtty4mac), LGPL v3`.
7. **Tři opravy z ji1uui:**
   - `DoFIR` v `fir.cpp`: `memcpy(zp, zp+1, ...)` (posun zpožďovací linky, překrývající se buffery) → `memmove`. Porovnejte `diff <(iconv -f SHIFT_JIS -t UTF-8 mmtty/fir.cpp) mmtty-ji1uui/fir.cpp | grep -n memmove`.
   - `CFSKDEM::SetSmoozCount(int n)` je v `Rtty.h` deklarovaná, ale nikde nedefinovaná. Do `Rtty.cpp` za `CFSKDEM::SetSmoozFreq` přidat:
     ```cpp
     void CFSKDEM::SetSmoozCount(int n)
     {
         if( n < 1 ) n = 1;
         m_Smooz = n;
         m_SmoozFreq = DemSamp / double(n);
         avgMark.SetCount(m_Smooz);
         avgSpace.SetCount(m_Smooz);
     }
     ```
     (Ověřte proti `SetSmoozFreq`. Musí být její inverzí: `SetSmoozFreq` počítá `m_Smooz` z frekvence.)
   - `CLMS::Clear()`: převzít definici z `mmtty-ji1uui/fir.cpp` (`grep -n 'CLMS::Clear' -A 15 mmtty-ji1uui/fir.cpp`) a deklaraci do `fir.h`, pokud v originálu chybí.
8. Do `CFSKMOD` v `Rtty.h` přidat jediný nový accessor (nemění chování):
   ```cpp
   inline int GetBufCount(void){return m_cnt;};
   ```

- [ ] **Step 6: Minimální `include/RTTYCore.h` a `RTTYCore.cpp`** (plné API přijde v Task 4)

`Sources/MMTTYCore/include/RTTYCore.h`:
```c
// RTTYCore.h – C API jádra RTTY z MMTTY.
// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
#ifndef RTTYCORE_H
#define RTTYCORE_H
#ifdef __cplusplus
extern "C" {
#endif

const char* rttycore_version(void);

#ifdef __cplusplus
}
#endif
#endif
```

`Sources/MMTTYCore/RTTYCore.cpp`:
```cpp
// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
#include "include/RTTYCore.h"
#include "mmtty/Rtty.h"
#include "mmtty/Fft.h"

extern "C" const char* rttycore_version(void) { return "MMTTYCore 0.1 (MMTTY 1.70H)"; }
```

- [ ] **Step 7: Přidat target do `Package.swift`**

```swift
        .target(
            name: "MMTTYCore",
            path: "Sources/MMTTYCore",
            cxxSettings: [
                .headerSearchPath("mmtty"),
                .headerSearchPath("compat"),
                .unsafeFlags(["-Wno-deprecated-declarations", "-Wno-writable-strings",
                              "-Wno-parentheses", "-Wno-dangling-else", "-Wno-unused-variable"]),
            ]
        ),
```

- [ ] **Step 8: Přeložit a opravovat chyby, dokud nebude čisto**

Run: `swift build --target MMTTYCore 2>&1 | grep -E 'error' | head -30`

Očekávané typy chyb a **jediné povolené** opravy:
- Neznámý typ nebo makro z Windows (`LPCSTR`, `ZeroMemory`…) → doplnit do `MMTTYCompat.h`.
- `Fir.h` vs `fir.h` (include v `Rtty.h` je `"Fir.h"`) → opravit na `"fir.h"` (APFS může být case-sensitive).
- Chybějící `#include "ComLib.h"` symboly (`sys.m_...` pole, které v `CoreSys` není) → přidat pole do `CoreSys` s výchozí hodnotou z `mmtty/Main.cpp` (inicializace kolem ř. 430–470).
- Chyby C++17 (např. `register`, implicitní konverze `const char*`) → minimální syntaktická úprava.
- Nedefinované symboly při linkování v této fázi nevadí (`swift build --target` jen kompiluje). Řeší se v Task 4.

**Nesmí se** měnit aritmetika, konstanty ani pořadí operací v DSP.

Expected (na konci): `Build of target: 'MMTTYCore' complete!`

- [ ] **Step 9: Commit**

```bash
git add Package.swift Sources/MMTTYCore
git commit -m "feat(core): compile MMTTY DSP on macOS via compat layer; port ji1uui fixes (memmove, SetSmoozCount, CLMS::Clear)"
```

---

### Task 4: C API – příjem (RX), parametry a validace

**Files:**
- Modify: `Sources/MMTTYCore/include/RTTYCore.h`, `Sources/MMTTYCore/RTTYCore.cpp`, `Package.swift`
- Test: `Tests/MMTTYCoreTests/CoreRxTests.swift`

**Interfaces:**
- Consumes: `CFSKDEM`, `CRTTY`, `CLMS`, `MakeFilter`, `DoFIR`, `InitSampType`, globály z Task 3; `RTTYSignalGenerator`, `NoiseGenerator` z Task 2.
- Produces (C API, přesné signatury, viz hlavička níže): `rttycore_create`, `rttycore_destroy`, `rttycore_process_rx`, `rttycore_read_chars`, `rttycore_signal`, `rttycore_set_param`, `rttycore_get_param`, typy `RTTYCore`, `RTTYCoreConfig`, `RTTYCoreParam`, `RTTYCoreChar`, `RTTYCoreSignal`, návratové kódy `RC_OK=0`, `RC_ERR_UNKNOWN=-1`, `RC_ERR_RANGE=-2`.

- [ ] **Step 1: Napsat failing testy**

`Tests/MMTTYCoreTests/CoreRxTests.swift`:
```swift
import Testing
import MMTTYCore
import RTTYSignalKit

/// Pomocník: pustí vzorky jádrem po blocích 512 a vrátí dekódovaný text.
func decode(_ core: OpaquePointer, _ samples: [Float], block: Int = 512) -> String {
    var text = ""
    var buf = [RTTYCoreChar](repeating: RTTYCoreChar(), count: 256)
    var i = 0
    while i < samples.count {
        let n = min(block, samples.count - i)
        samples.withUnsafeBufferPointer { p in rttycore_process_rx(core, p.baseAddress! + i, n) }
        i += n
        let got = rttycore_read_chars(core, &buf, buf.count)
        for k in 0..<got { text.append(Character(UnicodeScalar(UInt8(bitPattern: buf[k].ch)))) }
    }
    return text
}

func makeCore(sampleRate: Double = 11025) -> OpaquePointer? {
    var cfg = rttycore_default_config()
    cfg.sampleRate = sampleRate
    return rttycore_create(&cfg)
}

let sample = "RYRYRY CQ CQ DE OK1XOE OK1XOE PSE K\r\n599 001 TU 73\r\n"

@Test(arguments: [0, 1, 2, 3])   // IIR, FIR, PLL, FFT
func decodesCleanSignalWithEveryDemodulator(demod: Int) throws {
    let core = try #require(makeCore())
    defer { rttycore_destroy(core) }
    #expect(rttycore_set_param(core, RC_DEMOD_TYPE, Double(demod)) == RC_OK)
    let s = RTTYSignalGenerator().generate(text: sample)
    #expect(decode(core, s) == sample)
}

@Test(arguments: [(45.45, 170.0), (50.0, 170.0), (75.0, 170.0), (45.45, 850.0)])
func decodesOtherBaudAndShift(baud: Double, shift: Double) throws {
    let core = try #require(makeCore())
    defer { rttycore_destroy(core) }
    #expect(rttycore_set_param(core, RC_BAUD, baud) == RC_OK)
    #expect(rttycore_set_param(core, RC_SPACE, 2125 + shift) == RC_OK)
    let s = RTTYSignalGenerator(baud: baud, shiftHz: shift).generate(text: sample)
    #expect(decode(core, s) == sample)
}

@Test func decodesAt12000Hz() throws {
    let core = try #require(makeCore(sampleRate: 12000))
    defer { rttycore_destroy(core) }
    let s = RTTYSignalGenerator(sampleRate: 12000).generate(text: sample)
    #expect(decode(core, s) == sample)
}

@Test func decodesWithModerateNoise() throws {
    let core = try #require(makeCore())
    defer { rttycore_destroy(core) }
    var s = RTTYSignalGenerator(amplitude: 0.3).generate(text: sample)
    var noise = NoiseGenerator(seed: 1)
    noise.addNoise(to: &s, rms: 0.1)          // SNR ≈ 6,5 dB v celém pásmu 0–5,5 kHz
    #expect(decode(core, s) == sample)
}

@Test func reverseSettingDecodesReversedSignal() throws {
    let core = try #require(makeCore())
    defer { rttycore_destroy(core) }
    #expect(rttycore_set_param(core, RC_REVERSE, 1) == RC_OK)
    let s = RTTYSignalGenerator(reverse: true).generate(text: sample)
    #expect(decode(core, s) == sample)
}

// Review Focus 1
@Test(arguments: [44100.0, 48000.0, 8000.0, 0.0, -1.0, .nan])
func rejectsUnsupportedSampleRate(rate: Double) {
    #expect(makeCore(sampleRate: rate) == nil)
}

// Review Focus 2
@Test func rejectsOutOfRangeParametersWithoutChangingState() throws {
    let core = try #require(makeCore())
    defer { rttycore_destroy(core) }
    let before = rttycore_get_param(core, RC_BAUD)
    #expect(rttycore_set_param(core, RC_BAUD, 0) == RC_ERR_RANGE)
    #expect(rttycore_set_param(core, RC_BAUD, .nan) == RC_ERR_RANGE)
    #expect(rttycore_set_param(core, RC_MARK, 0) == RC_ERR_RANGE)
    #expect(rttycore_set_param(core, RC_FIR_TAP, 10000) == RC_ERR_RANGE)
    #expect(rttycore_set_param(core, RC_DEMOD_TYPE, 7) == RC_ERR_RANGE)
    #expect(rttycore_set_param(core, RTTYCoreParam(rawValue: 9999), 1) == RC_ERR_UNKNOWN)
    #expect(rttycore_get_param(core, RC_BAUD) == before)
}

@Test func defaultsMatchMMTTY() throws {
    let core = try #require(makeCore())
    defer { rttycore_destroy(core) }
    #expect(rttycore_get_param(core, RC_MARK) == 2125)
    #expect(rttycore_get_param(core, RC_SPACE) == 2295)
    #expect(abs(rttycore_get_param(core, RC_BAUD) - 45.45) < 1e-9)
    #expect(rttycore_get_param(core, RC_BIT_LENGTH) == 5)
    #expect(rttycore_get_param(core, RC_AFC) == 1)
}
```

Do `Package.swift` přidat:
```swift
        .testTarget(name: "MMTTYCoreTests", dependencies: ["MMTTYCore", "RTTYSignalKit", "WaveFile"],
                    resources: [.copy("Fixtures")]),
```
a vytvořit prázdný adresář `Tests/MMTTYCoreTests/Fixtures/golden/` se souborem `.gitkeep`.

- [ ] **Step 2: Spustit testy – musí selhat**

Run: `swift test --filter CoreRxTests`
Expected: FAIL při kompilaci (`rttycore_create` a další nejsou definované).

- [ ] **Step 3: Napsat plnou hlavičku C API**

`Sources/MMTTYCore/include/RTTYCore.h` (nahradit):
```c
// RTTYCore.h – C API jádra RTTY z MMTTY.
// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
#ifndef RTTYCORE_H
#define RTTYCORE_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef struct RTTYCore RTTYCore;

enum { RC_OK = 0, RC_ERR_UNKNOWN = -1, RC_ERR_RANGE = -2 };

typedef struct {
    double sampleRate;   /* 11025 nebo 12000 (± 2 % kvůli korekci ppm), jinak create vrátí NULL */
    double txOffset;     /* korekce vzorkovací frekvence TX v Hz */
    int    codeSet;      /* 0 = US (S-BELL), 1 = J-BELL */
    int    doubleShift;  /* 1 = LTRS/FIGS posílat 2× */
    int    txUOS;        /* 1 = unshift on space při vysílání */
} RTTYCoreConfig;

typedef enum {
    RC_BAUD = 0,            /* 20 .. 300 */
    RC_MARK,                /* 100 .. 3000 Hz */
    RC_SPACE,               /* 100 .. 3000 Hz, |space-mark| 20 .. 1000 */
    RC_REVERSE,             /* 0/1 */
    RC_SQUELCH,             /* 0/1 */
    RC_SQUELCH_LEVEL,       /* 0 .. 32768 (MMTTY m_SQLevel, výchozí 600) */
    RC_DEMOD_TYPE,          /* 0 IIR, 1 FIR, 2 PLL, 3 FFT */
    RC_IIR_BW,              /* 20 .. 500 Hz */
    RC_FIR_TAP,             /* 8 .. 512 */
    RC_SMOOTH_TYPE,         /* 0 moving avg, 1 IIR LPF */
    RC_SMOOTH_FREQ,         /* 10 .. 1000 Hz */
    RC_LPF_ORDER,           /* 1 .. 8 */
    RC_ATC,                 /* 0/1 */
    RC_MAJORITY,            /* 0/1 */
    RC_IGNORE_FRAMING,      /* 0/1 */
    RC_BIT_LENGTH,          /* 5 .. 8 */
    RC_STOP_BITS,           /* 0 .. 4 (MMTTY m_StopLen: 0=1, 1=1.5, 2=2, 3=1, 4=1.42) */
    RC_PARITY,              /* 0 .. 4 (none, even, odd, mark, space) */
    RC_LIMITER_AGC,         /* 0/1 */
    RC_LIMITER_OVERSAMPLE,  /* 0/1 */
    RC_UOS,                 /* 0/1 RX unshift on space */
    RC_DIDDLE,              /* 0 off, 1 BLK, 2 LTR */
    RC_ECHO,                /* 0/1/2 jako sys.m_echo */
    RC_AFC,                 /* 0/1 */
    RC_AFC_MODE,            /* 0 Free, 1 Fixed, 2 HAM, 3 FSK (sys.m_FixShift) */
    RC_AFC_SQ,              /* 0 .. 1024 */
    RC_AFC_TIME,            /* 1 .. 64 */
    RC_AFC_SWEEP,           /* 0.1 .. 3.0 */
    RC_RX_BPF,              /* 0/1 vstupní BPF */
    RC_RX_BPF_WIDTH,        /* 20 .. 500 Hz (TSound m_bpffw, výchozí 100) */
    RC_RX_LMS,              /* 0/1 LMS/notch */
    RC_TX_OUTPUT_GAIN,      /* 0 .. 32768 (CFSKMOD m_OutputGain) */
    RC_PARAM_COUNT
} RTTYCoreParam;

typedef struct { char ch; uint8_t echo; } RTTYCoreChar;

typedef struct {
    double level;        /* CFSKDEM m_avgdeff */
    int    squelchOpen;  /* 1 když squelch vypnutý nebo level > squelch level */
    int    overflow;     /* 1 = přebuzení od posledního volání rttycore_signal */
    double mark;         /* aktuální mark (po AFC) */
    double space;
    int    fig;          /* 1 = RX ve FIGS */
} RTTYCoreSignal;

RTTYCoreConfig rttycore_default_config(void);
const char* rttycore_version(void);

RTTYCore* rttycore_create(const RTTYCoreConfig* cfg);
void      rttycore_destroy(RTTYCore* core);

void      rttycore_process_rx(RTTYCore* core, const float* samples, size_t n);
size_t    rttycore_read_chars(RTTYCore* core, RTTYCoreChar* out, size_t max);
RTTYCoreSignal rttycore_signal(RTTYCore* core);

int       rttycore_set_param(RTTYCore* core, RTTYCoreParam p, double value);
double    rttycore_get_param(const RTTYCore* core, RTTYCoreParam p);

#ifdef __cplusplus
}
#endif
#endif
```

- [ ] **Step 4: Implementovat RX část `RTTYCore.cpp`**

Postupujte podle `mmtty/Sound.cpp` (`TSound::Execute` RX větev, ř. ~297–318, a `CalcBPF` ř. ~109–113) a `mmtty/Main.cpp` (`RecvJob` ř. ~2607–2650).

```cpp
// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
#include "include/RTTYCore.h"
#include "MMTTYCompat.h"
#include "mmtty/Rtty.h"
#include "mmtty/Fft.h"
#include <cmath>
#include <memory>
#include <vector>

struct RTTYCore {
    RTTYCoreConfig cfg;
    std::unique_ptr<CFSKDEM> dem;
    std::unique_ptr<CFSKMOD> mod;
    CRTTY rtty;
    CLMS  lms;
    double HBPF[TAPMAX + 1];
    double ZBPF[TAPMAX + 1];
    int    bpf = 0, lmsOn = 0, bpftap = 56;
    double bpffw = 100.0;
    int    echo = 1;
    int    afc = 1, afcMode = 1;
    double afcSQ = 32, afcTime = 8.0, afcSweep = 1.0;
    int    txActive = 0;
    int    overflowLatched = 0;
    std::vector<double> block;

    void calcBPF() {
        MakeFilter(HBPF, bpftap, ffBPF, SampFreq,
                   dem->GetMarkFreq() - bpffw, dem->GetSpaceFreq() + bpffw, 60, 1.0);
        lms.SetWindow(dem->GetMarkFreq(), dem->GetSpaceFreq());
    }
};

static bool validRate(double r) {
    if (!std::isfinite(r)) return false;
    return (r >= 11025 * 0.98 && r <= 11025 * 1.02) || (r >= 12000 * 0.98 && r <= 12000 * 1.02);
}

extern "C" RTTYCoreConfig rttycore_default_config(void) {
    RTTYCoreConfig c;
    c.sampleRate = 11025; c.txOffset = 0; c.codeSet = 0; c.doubleShift = 0; c.txUOS = 1;
    return c;
}

extern "C" const char* rttycore_version(void) { return "MMTTYCore 0.1 (MMTTY 1.70H)"; }

extern "C" RTTYCore* rttycore_create(const RTTYCoreConfig* cfg) {
    if (!cfg || !validRate(cfg->sampleRate)) return nullptr;
    // Globály MUSÍ být nastavené PŘED konstrukcí CFSKDEM/CFSKMOD (konstruktory je čtou).
    SampFreq = cfg->sampleRate;
    InitSampType();
    sys.m_SampFreq = SampFreq;
    sys.m_TxOffset = cfg->txOffset;
    sys.m_CodeSet  = cfg->codeSet;
    sys.m_dblsft   = cfg->doubleShift;
    sys.m_txuos    = cfg->txUOS;
    sys.m_TxPort   = txSound;

    auto* c = new RTTYCore();
    c->cfg = *cfg;
    c->dem = std::make_unique<CFSKDEM>();
    c->mod = std::make_unique<CFSKMOD>();
    c->mod->SetDem(c->dem.get());
    c->mod->SetSampFreq(SampFreq + sys.m_TxOffset);
    c->rtty.SetCodeSet();
    memset(c->ZBPF, 0, sizeof(c->ZBPF));
    c->calcBPF();
    return c;
}

extern "C" void rttycore_destroy(RTTYCore* c) { delete c; }

extern "C" void rttycore_process_rx(RTTYCore* c, const float* s, size_t n) {
    if (!c || !s) return;
    c->block.resize(n);
    for (size_t i = 0; i < n; i++) c->block[i] = double(s[i]) * 32768.0;
    double* lp = c->block.data();
    if (c->bpf || c->lmsOn) {
        for (size_t i = 0; i < n; i++) {
            if (c->bpf)   lp[i] = DoFIR(c->HBPF, c->ZBPF, lp[i], c->bpftap);
            if (c->lmsOn) lp[i] = c->lms.Do(lp[i]);
        }
    }
    // (FFT sběr doplní Task 6)
    if (!c->txActive || c->echo) {
        for (size_t i = 0; i < n; i++) c->dem->Do(lp[i]);
    }
    if (c->dem->m_OverFlow) { c->overflowLatched = 1; c->dem->m_OverFlow = 0; }
}

extern "C" size_t rttycore_read_chars(RTTYCore* c, RTTYCoreChar* out, size_t max) {
    if (!c || !out) return 0;
    size_t k = 0;
    while (k < max) {
        int d = c->dem->GetData();
        if (d < 0) break;
        char ch = 0;
        switch (c->dem->m_BitLen) {
            case 7: d &= 0x7f; /* fallthrough */
            case 8: ch = char(d); break;
            default: ch = c->rtty.ConvAscii(d); break;
        }
        if (ch) { out[k].ch = ch; out[k].echo = uint8_t(c->txActive ? 1 : 0); k++; }
    }
    return k;
}

extern "C" RTTYCoreSignal rttycore_signal(RTTYCore* c) {
    RTTYCoreSignal r{};
    if (!c) return r;
    r.level = c->dem->m_avgdeff;
    r.squelchOpen = (!c->dem->GetSQ() || c->dem->m_avgdeff >= c->dem->GetSQLevel()) ? 1 : 0;
    r.overflow = c->overflowLatched; c->overflowLatched = 0;
    r.mark = c->dem->GetMarkFreq();
    r.space = c->dem->GetSpaceFreq();
    r.fig = c->rtty.m_fig;
    return r;
}
```

`rttycore_set_param` / `rttycore_get_param`: `switch` přes všechny `RTTYCoreParam`. Pro každý parametr **nejdřív validace rozsahu** podle komentáře v hlavičce (`!std::isfinite(v)` → `RC_ERR_RANGE`, neznámé ID → `RC_ERR_UNKNOWN`), teprve potom nastavení. Mapování na MMTTY (ověřte proti obsluze v `mmtty/Main.cpp`: `grep -n 'SetBaudRate\|SetMarkFreq\|SetSpaceFreq\|SetIIR\|SetFilterTap\|SetSmoozFreq\|SetLPFFreq' mmtty/Main.cpp`):

| Param | set | get |
|---|---|---|
| `RC_BAUD` | `dem->SetBaudRate(v); mod->SetBaudRate(v);` | `dem->GetBaudRate()` |
| `RC_MARK` | kontrola shiftu proti `GetSpaceFreq()`; `dem->SetMarkFreq(v); mod->SetMarkFreq(v); calcBPF();` | `dem->GetMarkFreq()` |
| `RC_SPACE` | kontrola shiftu proti `GetMarkFreq()`; `dem->SetSpaceFreq(v); mod->SetSpaceFreq(v); calcBPF();` | `dem->GetSpaceFreq()` |
| `RC_REVERSE` | `dem->SetRev(int(v)); mod->SetRev(int(v));` | `dem->GetRev()` |
| `RC_SQUELCH` | `dem->SetSQ(int(v))` | `dem->GetSQ()` |
| `RC_SQUELCH_LEVEL` | `dem->SetSQLevel(v)` | `dem->GetSQLevel()` |
| `RC_DEMOD_TYPE` | `dem->m_type = int(v)` | `dem->m_type` |
| `RC_IIR_BW` | `dem->SetIIR(v)` | `dem->m_iirfw` |
| `RC_FIR_TAP` | `dem->SetFilterTap(int(v))` | `dem->GetFilterTap()` |
| `RC_SMOOTH_TYPE` | `dem->m_lpf = int(v)` | `dem->m_lpf` |
| `RC_SMOOTH_FREQ` | `dem->SetSmoozFreq(v); dem->SetLPFFreq(v);` | `dem->GetSmoozFreq()` |
| `RC_LPF_ORDER` | `dem->m_lpfOrder = int(v); dem->SetLPFFreq(dem->m_lpffreq);` | `dem->m_lpfOrder` |
| `RC_ATC` | `dem->m_atc = int(v)` | `dem->m_atc` |
| `RC_MAJORITY` | `dem->m_majority = int(v)` | `dem->m_majority` |
| `RC_IGNORE_FRAMING` | `dem->m_ignoreFream = int(v)` | `dem->m_ignoreFream` |
| `RC_BIT_LENGTH` | `dem->m_BitLen = mod->m_BitLen = int(v)` | `dem->m_BitLen` |
| `RC_STOP_BITS` | `dem->m_StopLen = mod->m_StopLen = int(v)` | `dem->m_StopLen` |
| `RC_PARITY` | `dem->m_Parity = mod->m_Parity = int(v)` | `dem->m_Parity` |
| `RC_LIMITER_AGC` | `dem->m_LimitAGC = int(v)` | `dem->m_LimitAGC` |
| `RC_LIMITER_OVERSAMPLE` | `dem->m_LimitOverSampling = int(v)` | `dem->m_LimitOverSampling` |
| `RC_UOS` | `rtty.m_uos = int(v)` | `rtty.m_uos` |
| `RC_DIDDLE` | `mod->m_diddle = int(v)` | `mod->m_diddle` |
| `RC_ECHO` | `echo = int(v)` | `echo` |
| `RC_AFC` … `RC_AFC_SWEEP` | uložit do `afc`, `afcMode`, `afcSQ`, `afcTime`, `afcSweep` | tatáž pole |
| `RC_RX_BPF` | `bpf = int(v)` | `bpf` |
| `RC_RX_BPF_WIDTH` | `bpffw = v; calcBPF();` | `bpffw` |
| `RC_RX_LMS` | `lmsOn = int(v)` | `lmsOn` |
| `RC_TX_OUTPUT_GAIN` | `mod->SetOutputGain(v)` | `mod->GetOutputGain()` |

Poznámka k `RC_SMOOTH_FREQ`: MMTTY používá jednu hodnotu jako kmitočet klouzavého průměru i jako mez LPF. Ověřte v `Main.cpp`, jestli se `SetLPFFreq` volá se stejnou hodnotou. Pokud ne, rozdělte na dva parametry a upravte hlavičku.

- [ ] **Step 5: Spustit testy**

Run: `swift test --filter CoreRxTests`
Expected: PASS všech testů.
Pokud některý demodulátor (typicky `3` FFT nebo `2` PLL) nedekóduje čistý signál bezchybně, **neupravujte DSP**. Zkontrolujte, jestli `rttycore_create` nastavuje totéž co `TSound` a `TMmttyWd` při startu (`Main.cpp` ř. ~430–520 a `ReadRegister`). Pokud jde o vlastnost originálu (např. první znak po náběhu), upravte test tak, aby toleroval ztrátu prvních 1–2 znaků (`#expect(decoded.hasSuffix(String(sample.dropFirst(6))))`) a do testu napište komentář proč.

- [ ] **Step 6: Commit**

```bash
git add Sources/MMTTYCore Tests/MMTTYCoreTests Package.swift
git commit -m "feat(core): C API for RX decoding, parameters with range validation"
```

---

### Task 5: C API – vysílání (TX)

**Files:**
- Modify: `Sources/MMTTYCore/include/RTTYCore.h`, `Sources/MMTTYCore/RTTYCore.cpp`
- Test: `Tests/MMTTYCoreTests/CoreTxTests.swift`

**Interfaces:**
- Consumes: C API z Task 4, `CFSKMOD`, `CRTTY::ConvRTTY`, `CFSKMOD::GetBufCount` (Task 3).
- Produces:
  - `void rttycore_tx_begin(RTTYCore*, int tune)` – `tune=1` vysílá jen nosnou mark
  - `size_t rttycore_queue_tx(RTTYCore*, const char* text)` – vrací počet **vstupních znaků** zpracovaných (přijatých i vynechaných), zastaví se, když v bufferu není místo aspoň na 3 kódy
  - `size_t rttycore_tx_space(const RTTYCore*)` – volné místo v bufferu (kódy)
  - `size_t rttycore_tx_pending(const RTTYCore*)` – kódy čekající na odvysílání
  - `size_t rttycore_generate_tx(RTTYCore*, float* out, size_t n)` – vrací počet vzorků; `< n`, když vysílání skončilo (zbytek vyplní nulami)
  - `void rttycore_tx_stop(RTTYCore*)` – dovysílá rozpracovaný znak, zahodí zbytek bufferu, pak ticho
  - `void rttycore_tx_abort(RTTYCore*)` – okamžitě konec
  - `int rttycore_is_tx(const RTTYCore*)`

- [ ] **Step 1: Napsat failing testy**

`Tests/MMTTYCoreTests/CoreTxTests.swift`:
```swift
import Testing
import MMTTYCore
import RTTYSignalKit

/// Vygeneruje TX signál z jádra A a dekóduje ho nezávislou instancí B.
func transmit(_ text: String, configure: (OpaquePointer) -> Void = { _ in }) throws -> [Float] {
    let tx = try #require(makeCore())
    defer { rttycore_destroy(tx) }
    configure(tx)
    rttycore_tx_begin(tx, 0)
    var remaining = Array(text.utf8CString.dropLast())   // bez koncové 0
    var out: [Float] = []
    var buf = [Float](repeating: 0, count: 1024)
    var stopRequested = false
    for _ in 0..<100_000 {
        if !remaining.isEmpty {
            let used = remaining.withUnsafeBufferPointer { p -> Int in
                var tmp = Array(p) + [0]
                return rttycore_queue_tx(tx, &tmp)
            }
            remaining.removeFirst(used)
        } else if !stopRequested && rttycore_tx_pending(tx) == 0 {
            rttycore_tx_stop(tx); stopRequested = true
        }
        let n = rttycore_generate_tx(tx, &buf, buf.count)
        out += buf[0..<n]
        if n < buf.count { break }
    }
    return out
}

@Test func loopbackDecodesTransmittedText() throws {
    let text = "CQ CQ DE OK1XOE OK1XOE K\r\n"
    let s = try transmit(text)
    let rx = try #require(makeCore())
    defer { rttycore_destroy(rx) }
    #expect(decode(rx, [Float](repeating: 0, count: 5000) + s + [Float](repeating: 0, count: 5000)).contains("CQ CQ DE OK1XOE OK1XOE K"))
}

@Test func figuresAndLettersSwitchCorrectly() throws {
    let text = "RST 599 NR 001 QTH PRAGUE 73"
    let s = try transmit(text)
    let rx = try #require(makeCore())
    defer { rttycore_destroy(rx) }
    #expect(decode(rx, s).contains(text))
}

@Test func transmittedToneIsWithinMarkSpaceBand() throws {
    let s = try transmit("RYRYRYRY")
    var crossings = 0
    for i in 1..<s.count where (s[i - 1] < 0) != (s[i] < 0) { crossings += 1 }
    let f = Double(crossings) / 2 / (Double(s.count) / 11025)
    #expect(f > 2100 && f < 2320)
    #expect(s.allSatisfy { abs($0) <= 1.0 })
}

@Test func stopEndsTransmissionAndIsTxClears() throws {
    let tx = try #require(makeCore())
    defer { rttycore_destroy(tx) }
    rttycore_tx_begin(tx, 0)
    #expect(rttycore_is_tx(tx) == 1)
    var buf = [Float](repeating: 0, count: 1024)
    _ = rttycore_generate_tx(tx, &buf, buf.count)
    rttycore_tx_stop(tx)
    var total = 0
    for _ in 0..<100 {
        let n = rttycore_generate_tx(tx, &buf, buf.count)
        total += n
        if n < buf.count { break }
    }
    #expect(rttycore_is_tx(tx) == 0)
    #expect(total < 11025)            // ukončeno do 1 s
}

@Test func abortStopsImmediately() throws {
    let tx = try #require(makeCore())
    defer { rttycore_destroy(tx) }
    rttycore_tx_begin(tx, 0)
    _ = rttycore_queue_tx(tx, "CQ CQ CQ CQ CQ CQ CQ")
    rttycore_tx_abort(tx)
    var buf = [Float](repeating: 1, count: 256)
    #expect(rttycore_generate_tx(tx, &buf, buf.count) == 0)
    #expect(buf.allSatisfy { $0 == 0 })
    #expect(rttycore_tx_pending(tx) == 0)
}

// Review Focus 3
@Test func unsupportedCharactersAreSkippedAndLowercaseUppercased() throws {
    let s = try transmit("cq é@\t😀 de ok1xoe")
    let rx = try #require(makeCore())
    defer { rttycore_destroy(rx) }
    #expect(decode(rx, s).contains("CQ  DE OK1XOE"))
}

@Test func queueReportsBackpressure() throws {
    let tx = try #require(makeCore())
    defer { rttycore_destroy(tx) }
    rttycore_tx_begin(tx, 0)
    let long = String(repeating: "RYRYRYRYRY", count: 500)     // 5000 znaků > 2048 kódů
    let used = rttycore_queue_tx(tx, long)
    #expect(used > 0 && used < 5000)
    #expect(rttycore_tx_space(tx) < 3)
}
```

- [ ] **Step 2: Spustit – musí selhat**

Run: `swift test --filter CoreTxTests`
Expected: FAIL při kompilaci (`rttycore_tx_begin` neexistuje).

- [ ] **Step 3: Doplnit deklarace do `RTTYCore.h`** (před `#ifdef __cplusplus }`)

```c
void   rttycore_tx_begin(RTTYCore* core, int tune);
size_t rttycore_queue_tx(RTTYCore* core, const char* text);
size_t rttycore_tx_space(const RTTYCore* core);
size_t rttycore_tx_pending(const RTTYCore* core);
size_t rttycore_generate_tx(RTTYCore* core, float* out, size_t n);
void   rttycore_tx_stop(RTTYCore* core);
void   rttycore_tx_abort(RTTYCore* core);
int    rttycore_is_tx(const RTTYCore* core);
```

- [ ] **Step 4: Implementovat v `RTTYCore.cpp`** podle `TMmttyWd::XMIT` (`Main.cpp:3553-3606`), `ToRX` (`Main.cpp:3435-3460`) a TX větve `TSound::Execute` (`Sound.cpp:320-330`, `:366-372`)

Do `struct RTTYCore` přidat: `int txStopping = 0;` a konstantu `static constexpr int kBufSize = 1024;` (MMTTY `m_BuffSize` při 11025 Hz).

```cpp
extern "C" void rttycore_tx_begin(RTTYCore* c, int tune) {
    if (!c) return;
    c->mod->ClearTXBuf();
    c->rtty.ClearTX();
    c->mod->SetBaudRate(c->dem->GetBaudRate());
    c->mod->m_Amp.Reset();
    c->mod->m_AmpVal = 1;
    c->mod->OutTone(tune ? 1 : 0, RTTYCore::kBufSize);
    if (c->echo != 2) c->dem->ClearRXBuf();
    c->mod->InitPhase();
    c->mod->SetCount(RTTYCore::kBufSize * 3);
    c->mod->SetDiddleTimer(int(SampFreq / 4));     // 0,25 s jako XMIT
    c->txActive = 1;
    c->txStopping = 0;
}

extern "C" size_t rttycore_tx_space(const RTTYCore* c) {
    return c ? size_t(MODBUFMAX - c->mod->GetBufCount()) : 0;
}

extern "C" size_t rttycore_tx_pending(const RTTYCore* c) {
    return c ? size_t(c->mod->GetBufCount()) : 0;
}

extern "C" size_t rttycore_queue_tx(RTTYCore* c, const char* text) {
    if (!c || !text || !c->txActive || c->txStopping) return 0;
    size_t used = 0;
    BYTE codes[8];
    for (const char* p = text; *p; p++) {
        if (rttycore_tx_space(c) < 3) break;
        unsigned char u = (unsigned char)*p;
        used++;
        if (u >= 'a' && u <= 'z') u = u - 'a' + 'A';
        if (!(u == '\r' || u == '\n' || (u >= 0x20 && u < 0x7F))) continue;   // mimo ASCII vynechat
        char one[2] = { char(u), 0 };
        int n = c->rtty.ConvRTTY(codes, one);
        for (int i = 0; i < n; i++) c->mod->PutData(codes[i]);
    }
    return used;
}
```

Poznámka: `used` počítá **bajty** UTF-8. Vícebajtové znaky (é, emoji) se vynechají po bajtech, protože jejich bajty jsou ≥ 0x80. Swift strana (Task 10) posílá text po bajtech UTF-8, takže je to konzistentní.

`ConvRTTY(BYTE*, LPCSTR)` může pro znak, který Baudot nezná (např. `@`, TAB), vrátit 0 kódů nebo kód „neznámý“. Ověřte v `Rtty.cpp:1560-1600` a nechte chování originálu. Test `unsupportedCharactersAreSkipped...` říká, co je správně na výstupu.

```cpp
extern "C" size_t rttycore_generate_tx(RTTYCore* c, float* out, size_t n) {
    if (!c || !out) return 0;
    size_t i = 0;
    if (c->txActive) {
        for (; i < n; i++) {
            double d = c->mod->Do(c->echo);
            if (c->txStopping && !c->mod->GetMode()) { c->txActive = 0; c->txStopping = 0; break; }
            double f = d / 32768.0;
            out[i] = float(f > 1.0 ? 1.0 : (f < -1.0 ? -1.0 : f));
        }
    }
    for (size_t k = i; k < n; k++) out[k] = 0.0f;
    return i;
}

extern "C" void rttycore_tx_stop(RTTYCore* c) {
    if (!c || !c->txActive) return;
    c->mod->SetDiddleTimer(-1);
    c->mod->DeleteTXBuf();
    c->txStopping = 1;
}

extern "C" void rttycore_tx_abort(RTTYCore* c) {
    if (!c) return;
    c->mod->DeleteTXBuf();
    c->txActive = 0; c->txStopping = 0;
}

extern "C" int rttycore_is_tx(const RTTYCore* c) { return c && c->txActive ? 1 : 0; }
```

Poznámka k echu: když `echo != 0`, `CFSKMOD::Do` zapisuje odvysílané kódy do bufferu demodulátoru (`pDem->WriteData`). `rttycore_read_chars` je během `txActive` označí `echo = 1`.

- [ ] **Step 5: Spustit testy**

Run: `swift test --filter CoreTxTests`
Expected: PASS.
Pokud `stopEndsTransmission...` nevyprší do 1 s, zkontrolujte, že `GetMode()` po `DeleteTXBuf` klesne na 0 po dokončení znaku (`Rtty.cpp:364-530`).

- [ ] **Step 6: Commit**

```bash
git add Sources/MMTTYCore Tests/MMTTYCoreTests
git commit -m "feat(core): TX path (begin/queue/generate/stop/abort) with backpressure"
```

---

### Task 6: Spektrum (CFFT), AFC, vstupní BPF/LMS a robustnost

**Files:**
- Create: `Sources/MMTTYCore/AFC.h`, `Sources/MMTTYCore/AFC.cpp`
- Modify: `Sources/MMTTYCore/include/RTTYCore.h`, `Sources/MMTTYCore/RTTYCore.cpp`
- Test: `Tests/MMTTYCoreTests/CoreAFCTests.swift`, `Tests/MMTTYCoreTests/CoreRobustnessTests.swift`

**Interfaces:**
- Consumes: `CFFT` (`CollectFFT`, `CalcFFT`, `m_fft`, `m_CollectFFT`, `TrigFFT`), `CFSKDEM::AFCMarkFreq/AFCSpaceFreq`.
- Produces:
  - `int rttycore_tick(RTTYCore*)` – volat po každých ~100 ms zpracovaných vzorků; spočítá FFT a provede AFC; vrací 1, když AFC změnilo mark/space
  - `size_t rttycore_spectrum(RTTYCore*, float* out, size_t max, double* binHz)` – poslední spektrum (magnitudy z `CFFT::m_fft`), vrací počet binů
  - `AFC.h`: `struct AFCParams { int mode; double sq; double time; double sweep; }`, `struct AFCState { /* přesunuté členy TSound, které DoAFC používá */ }`, `bool DoAFC(const int* fft, int fftSize, double sampFreq, int fftWindow, CFSKDEM& dem, const AFCParams& p, AFCState& st)`

- [ ] **Step 1: Napsat failing testy**

`Tests/MMTTYCoreTests/CoreAFCTests.swift`:
```swift
import Testing
import MMTTYCore
import RTTYSignalKit

func runWithTicks(_ core: OpaquePointer, _ samples: [Float]) -> String {
    var text = ""
    var buf = [RTTYCoreChar](repeating: RTTYCoreChar(), count: 256)
    let block = 1103   // ≈ 100 ms při 11025 Hz
    var i = 0
    while i < samples.count {
        let n = min(block, samples.count - i)
        samples.withUnsafeBufferPointer { p in rttycore_process_rx(core, p.baseAddress! + i, n) }
        _ = rttycore_tick(core)
        i += n
        let got = rttycore_read_chars(core, &buf, buf.count)
        for k in 0..<got { text.append(Character(UnicodeScalar(UInt8(bitPattern: buf[k].ch)))) }
    }
    return text
}

@Test func spectrumPeaksAtMarkTone() throws {
    let core = try #require(makeCore())
    defer { rttycore_destroy(core) }
    let s = RTTYSignalGenerator().generate(text: "", leadIn: 2.0, tail: 0)   // čistý mark 2125 Hz
    _ = runWithTicks(core, s)
    var spec = [Float](repeating: 0, count: 2048)
    var binHz = 0.0
    let n = rttycore_spectrum(core, &spec, spec.count, &binHz)
    #expect(n > 0 && binHz > 0)
    let peak = spec[0..<n].enumerated().max { $0.element < $1.element }!.offset
    #expect(abs(Double(peak) * binHz - 2125) < 3 * binHz)
}

@Test func afcTracksOffsetSignalAndDecodes() throws {
    let core = try #require(makeCore())
    defer { rttycore_destroy(core) }
    #expect(rttycore_get_param(core, RC_AFC) == 1)
    // signál o 60 Hz níž, než je nastaveno (2065/2235 místo 2125/2295)
    let text = String(repeating: "RYRYRYRY CQ TEST DE OK1XOE ", count: 6)
    let s = RTTYSignalGenerator(markHz: 2065).generate(text: text, leadIn: 1.0)
    let out = runWithTicks(core, s)
    let sig = rttycore_signal(core)
    #expect(abs(sig.mark - 2065) < 6)
    #expect(abs(sig.space - 2235) < 6)
    #expect(out.contains("CQ TEST DE OK1XOE"))
}

@Test func afcOffKeepsFrequencies() throws {
    let core = try #require(makeCore())
    defer { rttycore_destroy(core) }
    #expect(rttycore_set_param(core, RC_AFC, 0) == RC_OK)
    let s = RTTYSignalGenerator(markHz: 2065).generate(text: "RYRYRYRY", leadIn: 1.0)
    _ = runWithTicks(core, s)
    #expect(rttycore_signal(core).mark == 2125)
}

@Test func bpfAndLmsDoNotBreakCleanDecoding() throws {
    let core = try #require(makeCore())
    defer { rttycore_destroy(core) }
    #expect(rttycore_set_param(core, RC_RX_BPF, 1) == RC_OK)
    #expect(rttycore_set_param(core, RC_RX_LMS, 1) == RC_OK)
    let s = RTTYSignalGenerator().generate(text: sample)
    #expect(runWithTicks(core, s).contains("CQ CQ DE OK1XOE"))
}
```

`Tests/MMTTYCoreTests/CoreRobustnessTests.swift`:
```swift
import Testing
import MMTTYCore
import RTTYSignalKit

// Review Focus 5
@Test func squelchSuppressesNoiseOnlyInput() throws {
    let core = try #require(makeCore())
    defer { rttycore_destroy(core) }
    #expect(rttycore_set_param(core, RC_SQUELCH, 1) == RC_OK)
    var s = [Float](repeating: 0, count: 11025 * 5)
    var noise = NoiseGenerator(seed: 7)
    noise.addNoise(to: &s, rms: 0.05)
    #expect(runWithTicks(core, s).isEmpty)
    #expect(rttycore_signal(core).squelchOpen == 0)
}

@Test func overdrivenInputIsFlaggedAndStillDecodes() throws {
    let core = try #require(makeCore())
    defer { rttycore_destroy(core) }
    let s = RTTYSignalGenerator(amplitude: 3.0).generate(text: sample)   // 3× přes plný rozsah
    let out = runWithTicks(core, s)
    #expect(rttycore_signal(core).overflow == 1)
    #expect(out.contains("CQ CQ DE OK1XOE"))
}

@Test func silenceAndEmptyBuffersAreHarmless() throws {
    let core = try #require(makeCore())
    defer { rttycore_destroy(core) }
    rttycore_process_rx(core, nil, 0)
    let zeros = [Float](repeating: 0, count: 11025)
    #expect(runWithTicks(core, zeros).isEmpty)
}

@Test func nanSamplesDoNotPoisonDecoder() throws {
    let core = try #require(makeCore())
    defer { rttycore_destroy(core) }
    var s = RTTYSignalGenerator().generate(text: sample)
    s.insert(contentsOf: [Float.nan, .infinity, -.infinity], at: 100)
    #expect(runWithTicks(core, s).contains("CQ CQ DE OK1XOE"))
}
```

- [ ] **Step 2: Spustit – musí selhat**

Run: `swift test --filter "CoreAFCTests|CoreRobustnessTests"`
Expected: FAIL při kompilaci (`rttycore_tick`, `rttycore_spectrum` neexistují).

- [ ] **Step 3: Vytáhnout `DoAFC` do `AFC.cpp`**

Zdroj: `mmtty/Sound.cpp` `TSound::DoAFC` (ř. 479–~780) a volání `CalcFFT` (ř. ~815–840).
- `sys.m_AFC` / `m_FixShift` / `m_AFCSQ` / `m_AFCTime` / `m_AFCSweep` → `AFCParams`.
- `fftIN.m_fft` → parametr `fft`.
- `FFT_SIZE`, `SampFreq` → parametry.
- Členy `TSound`, které funkce čte nebo mění (`m_FFTWINDOW`, `m_FFTFW`, `m_bpfafc`, čítače mezi voláními), → `AFCState`.
- Volání `CalcBPF(...)` → callback `std::function<void(double, double, double)> onBPF` v `AFCState`, ve kterém `RTTYCore` přepočítá vstupní BPF.
- `Suspend()`/`Resume()` vynechat (běží ve stejném vlákně jako DSP).
- `if( m_Tx ) return 0;` → parametr `bool tx`.
- Aritmetiku a podmínky **přenést doslova**. Návratová hodnota: 1, když se zavolalo `AFCMarkFreq`/`AFCSpaceFreq` se změnou.

- [ ] **Step 4: Napojit FFT, AFC a sanitaci vstupu v `RTTYCore.cpp`**

Do `struct RTTYCore` přidat: `std::unique_ptr<CFFT> fft;` (vytvořit v `rttycore_create` **po** `InitSampType()`), `AFCState afcState;`, `int fftWindow;` (inicializovat jako `TSound` pro výchozí zobrazení, viz `Sound.cpp`, kde se nastavuje `m_FFTWINDOW`).

V `rttycore_process_rx`:
- Při převodu z float nahradit nekonečné a NaN vzorky nulou: `double v = std::isfinite(s[i]) ? double(s[i]) * 32768.0 : 0.0;` (Review Focus 5).
- Po BPF/LMS a před demodulací: `c->fft->CollectFFT(lp, int(n));` (jako `Sound.cpp:313`).

`rttycore_tick`:
```cpp
extern "C" int rttycore_tick(RTTYCore* c) {
    if (!c) return 0;
    if (c->fft->m_CollectFFT) {             // stejná podmínka jako Sound.cpp:820
        c->fft->CalcFFT(c->fftWindow, /* gain podle sys.m_FFTGain jako Sound.cpp:821-836 */ 30.0, sys.m_FFTResp);
        c->fft->TrigFFT();
    }
    if (!c->afc) return 0;
    AFCParams p{ c->afcMode, c->afcSQ, c->afcTime, c->afcSweep };
    return DoAFC(c->fft->m_fft, FFT_SIZE, SampFreq, c->fftWindow, *c->dem, p, c->afcState,
                 c->txActive && c->echo != 2) ? 1 : 0;
}
```
Hodnotu `gain` převezměte přesně podle `switch(sys.m_FFTGain)` v `Sound.cpp:821-836`. Konstanta 30.0 výše je jen pro větev `m_FFTGain == 0`.

`rttycore_spectrum`: zkopírovat `min(max, FFT_SIZE/2)` hodnot z `fft->m_fft` do `out` jako `float`, `*binHz = SampFreq / FFT_SIZE`.

Deklarace do hlavičky:
```c
int    rttycore_tick(RTTYCore* core);
size_t rttycore_spectrum(RTTYCore* core, float* out, size_t max, double* binHz);
```

Do `AFCState` na konci AFC s úspěchem (callback `onBPF`) napojit `c->calcBPF()` s frekvencemi z callbacku (odpovídá `TSound::CalcBPF(fl, fh, fw)`).

- [ ] **Step 5: Spustit testy**

Run: `swift test --filter "MMTTYCoreTests"`
Expected: PASS včetně Task 4 a 5.
Pokud `afcTracksOffsetSignalAndDecodes` selže kvůli režimu `m_FixShift = 1` (Fixed shift), ověřte v `DoAFC`, že Fixed posouvá mark i space současně. Offset 60 Hz musí být v rozsahu `AFCSweep`. Nezvětšujte toleranci nad 6 Hz bez konzultace.

- [ ] **Step 6: Commit**

```bash
git add Sources/MMTTYCore Tests/MMTTYCoreTests
git commit -m "feat(core): spectrum (CFFT), AFC extracted from TSound, input sanitizing"
```

---

### Task 7: Golden testy (referenční výstupy)

Zafixuje přesné chování jádra **před** refaktoringem v Task 8. Golden soubory se generují jednou a commitují.

**Files:**
- Create: `Tests/MMTTYCoreTests/GoldenTests.swift`
- Create: `Tests/MMTTYCoreTests/Fixtures/golden/*.wav`, `*.expected.txt` (generuje test)

**Interfaces:**
- Consumes: C API z Task 4–6, `WaveFile`, `RTTYSignalGenerator`, `NoiseGenerator`.
- Produces: `goldenCases` (seznam), soubory fixtures. Task 8 je musí reprodukovat bitově.

- [ ] **Step 1: Napsat test s režimem nahrávání**

`Tests/MMTTYCoreTests/GoldenTests.swift`:
```swift
import Foundation
import Testing
import MMTTYCore
import RTTYSignalKit
import WaveFile

struct GoldenCase: Sendable, CustomStringConvertible {
    let name: String, baud: Double, shift: Double, markOffset: Double
    let noiseRMS: Float, demod: Int
    var description: String { name }
}

let goldenText = String(repeating: "RYRYRY CQ CQ DE OK1XOE OK1XOE PSE K\r\nUR RST 599 599 NR 012 BK\r\n", count: 2)

let goldenCases: [GoldenCase] = [
    .init(name: "clean-45-iir",     baud: 45.45, shift: 170, markOffset: 0,   noiseRMS: 0,    demod: 0),
    .init(name: "noise6db-45-iir",  baud: 45.45, shift: 170, markOffset: 0,   noiseRMS: 0.1,  demod: 0),
    .init(name: "noise0db-45-iir",  baud: 45.45, shift: 170, markOffset: 0,   noiseRMS: 0.2,  demod: 0),
    .init(name: "noise0db-45-fft",  baud: 45.45, shift: 170, markOffset: 0,   noiseRMS: 0.2,  demod: 3),
    .init(name: "noise0db-45-pll",  baud: 45.45, shift: 170, markOffset: 0,   noiseRMS: 0.2,  demod: 2),
    .init(name: "noise3db-75-fir",  baud: 75,    shift: 170, markOffset: 0,   noiseRMS: 0.15, demod: 1),
    .init(name: "offset40-45-afc",  baud: 45.45, shift: 170, markOffset: -40, noiseRMS: 0.1,  demod: 0),
]

let fixturesDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/golden")

func goldenDecode(_ c: GoldenCase, samples: [Float]) throws -> String {
    let core = try #require(makeCore())
    defer { rttycore_destroy(core) }
    #expect(rttycore_set_param(core, RC_DEMOD_TYPE, Double(c.demod)) == RC_OK)
    #expect(rttycore_set_param(core, RC_BAUD, c.baud) == RC_OK)
    #expect(rttycore_set_param(core, RC_SPACE, 2125 + c.shift) == RC_OK)
    return runWithTicks(core, samples)
}

@Test(arguments: goldenCases)
func golden(_ c: GoldenCase) throws {
    let wav = fixturesDir.appendingPathComponent("\(c.name).wav")
    let expected = fixturesDir.appendingPathComponent("\(c.name).expected.txt")
    if ProcessInfo.processInfo.environment["RECORD_GOLDEN"] == "1" {
        var s = RTTYSignalGenerator(baud: c.baud, markHz: 2125 + c.markOffset,
                                    shiftHz: c.shift, amplitude: 0.3).generate(text: goldenText)
        var noise = NoiseGenerator(seed: 2026)
        if c.noiseRMS > 0 { noise.addNoise(to: &s, rms: c.noiseRMS) }
        try WaveFile.write(samples: s, sampleRate: 11025, to: wav)
        let (readBack, _) = try WaveFile.read(from: wav)          // dekódovat až 16bit verzi
        try goldenDecode(c, samples: readBack).write(to: expected, atomically: true, encoding: .utf8)
        return
    }
    let (samples, rate) = try WaveFile.read(from: wav)
    #expect(rate == 11025)
    let want = try String(contentsOf: expected, encoding: .utf8)
    #expect(try goldenDecode(c, samples: samples) == want)
}

@Test func cleanGoldenIsPerfect() throws {
    let want = try String(contentsOf: fixturesDir.appendingPathComponent("clean-45-iir.expected.txt"),
                          encoding: .utf8)
    #expect(want == goldenText)
}
```

- [ ] **Step 2: Vygenerovat fixtures**

Run: `RECORD_GOLDEN=1 swift test --filter GoldenTests`
Expected: vznikne 7 `.wav` a 7 `.expected.txt` v `Tests/MMTTYCoreTests/Fixtures/golden/` (každý WAV zhruba 400 kB).

- [ ] **Step 3: Zkontrolovat výstupy očima**

Run: `for f in Tests/MMTTYCoreTests/Fixtures/golden/*.expected.txt; do echo "== $f"; cat "$f"; echo; done`
Expected: `clean-45-iir` přesně odpovídá textu. Zašuměné varianty mají nanejvýš ojedinělé chyby, `noise0db-*` může mít víc chyb. Pokud je některý výstup **prázdný nebo úplně nesmyslný**, jde o chybu v Task 4–6. Neukládat a vrátit se k nim.

- [ ] **Step 4: Spustit v režimu ověření**

Run: `swift test --filter GoldenTests`
Expected: PASS (8 testů).

- [ ] **Step 5: Commit**

```bash
git add Tests/MMTTYCoreTests/GoldenTests.swift Tests/MMTTYCoreTests/Fixtures/golden
git commit -m "test(core): golden decoding fixtures (baseline before de-globalizing)"
```

---

### Task 8: Odstranění globálních proměnných – `CoreContext`

**Files:**
- Create: `Sources/MMTTYCore/compat/CoreContext.h`, `Sources/MMTTYCore/compat/CoreContext.cpp`
- Delete: `Sources/MMTTYCore/compat/CoreGlobals.cpp`
- Modify: `Sources/MMTTYCore/compat/MMTTYCompat.h`, `Sources/MMTTYCore/RTTYCore.cpp`
- Test: `Tests/MMTTYCoreTests/CoreRxTests.swift` (nový test níže), golden testy beze změny

**Interfaces:**
- Consumes: vše z Task 3–7.
- Produces: `struct CoreContext` (pole = bývalé globály), `extern thread_local CoreContext* g_ctx;`, RAII `struct CoreScope { explicit CoreScope(CoreContext*); ~CoreScope(); }`. Každá funkce C API začíná `CoreScope scope(&c->ctx);`. C API se **nemění**.

- [ ] **Step 1: Napsat failing test pro dvě instance s různou frekvencí**

Do `Tests/MMTTYCoreTests/CoreRxTests.swift` přidat:
```swift
@Test func twoInstancesWithDifferentRatesAreIndependent() throws {
    let a = try #require(makeCore(sampleRate: 11025))
    let b = try #require(makeCore(sampleRate: 12000))
    defer { rttycore_destroy(a); rttycore_destroy(b) }
    let sa = RTTYSignalGenerator(sampleRate: 11025).generate(text: sample)
    let sb = RTTYSignalGenerator(sampleRate: 12000).generate(text: sample)
    var ta = "", tb = ""
    var buf = [RTTYCoreChar](repeating: RTTYCoreChar(), count: 256)
    var ia = 0, ib = 0
    while ia < sa.count || ib < sb.count {           // prokládané zpracování
        if ia < sa.count {
            let n = min(512, sa.count - ia)
            sa.withUnsafeBufferPointer { rttycore_process_rx(a, $0.baseAddress! + ia, n) }; ia += n
            let g = rttycore_read_chars(a, &buf, 256)
            for k in 0..<g { ta.append(Character(UnicodeScalar(UInt8(bitPattern: buf[k].ch)))) }
        }
        if ib < sb.count {
            let n = min(512, sb.count - ib)
            sb.withUnsafeBufferPointer { rttycore_process_rx(b, $0.baseAddress! + ib, n) }; ib += n
            let g = rttycore_read_chars(b, &buf, 256)
            for k in 0..<g { tb.append(Character(UnicodeScalar(UInt8(bitPattern: buf[k].ch)))) }
        }
    }
    #expect(ta == sample)
    #expect(tb == sample)
}
```

- [ ] **Step 2: Spustit – musí selhat**

Run: `swift test --filter twoInstancesWithDifferentRatesAreIndependent`
Expected: FAIL (instance `a` dekóduje špatně, protože druhé `create` přepsalo globální `SampFreq`/`DemSamp`).

- [ ] **Step 3: Vytvořit `CoreContext`**

`Sources/MMTTYCore/compat/CoreContext.h`:
```cpp
// Kontext jádra – nahrazuje globální proměnné MMTTY. Aktivní po dobu volání C API.
// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
#pragma once
#include "MMTTYCompat.h"

struct CoreContext {
    CoreSys sys;
    double SampFreq = 11025.0, SampBase = 11025.0, DemSamp = 11025.0 * 0.5;
    int DemOver = 1, FFT_SIZE = 2048, SampType = 0, SampSize = 1024;
    int FSKCount = 0, FSKCount1 = 0, FSKCount2 = 0, FSKDeff = 0;
};

extern thread_local CoreContext* g_ctx;

struct CoreScope {
    CoreContext* prev;
    explicit CoreScope(CoreContext* c) : prev(g_ctx) { g_ctx = c; }
    ~CoreScope() { g_ctx = prev; }
    CoreScope(const CoreScope&) = delete;
    CoreScope& operator=(const CoreScope&) = delete;
};
```

`Sources/MMTTYCore/compat/CoreContext.cpp`:
```cpp
// Copyright 2000-2013 Makoto Mori, Nobuyuki Oba; Modifications Copyright 2026 OK1XOE, LGPL v3
#include "CoreContext.h"

static CoreContext g_defaultCtx;                       // pro statickou inicializaci mimo C API
thread_local CoreContext* g_ctx = &g_defaultCtx;

void InitSampType(void)   // doslova z ComLib.cpp, pracuje přes makra nad g_ctx
{
    if( SampFreq >= 11600.0 ){
        SampType = 3; SampBase = 12000.0; DemSamp = SampFreq * 0.5; DemOver = 1;
        FFT_SIZE = 2048; SampSize = (12000*1024)/11025;
    }
    else if( SampFreq >= 10000.0 ){
        SampType = 0; SampBase = 11025.0; DemSamp = SampFreq * 0.5; DemOver = 1;
        FFT_SIZE = 2048; SampSize = 1024;
    }
    else if( SampFreq >= 7000.0 ){
        SampType = 1; SampBase = 8000.0; DemSamp = SampFreq; DemOver = 0;
        FFT_SIZE = 1024; SampSize = (8000*1024)/11025;
    }
    else if( SampFreq >= 5000.0 ){
        SampType = 2; SampBase = 6000.0; DemSamp = SampFreq; DemOver = 0;
        FFT_SIZE = 1024; SampSize = (6000*1024)/11025;
    }
}
```

- [ ] **Step 4: Přesměrovat jména globálů na kontext v `MMTTYCompat.h`**

Nahradit `extern` deklarace z Task 3 tímto (na konec `MMTTYCompat.h`):
```cpp
struct CoreContext;
extern thread_local CoreContext* g_ctx;
#include "CoreContext.h"
#define sys        (g_ctx->sys)
#define SampFreq   (g_ctx->SampFreq)
#define SampBase   (g_ctx->SampBase)
#define DemSamp    (g_ctx->DemSamp)
#define DemOver    (g_ctx->DemOver)
#define FFT_SIZE   (g_ctx->FFT_SIZE)
#define SampType   (g_ctx->SampType)
#define SampSize   (g_ctx->SampSize)
#define FSKCount   (g_ctx->FSKCount)
#define FSKCount1  (g_ctx->FSKCount1)
#define FSKCount2  (g_ctx->FSKCount2)
#define FSKDeff    (g_ctx->FSKDeff)
void InitSampType(void);
```
`CoreContext.h` musí makra vidět až **po** definici struktury: v `CoreContext.h` includovat jen typy (`CoreSys`, enum). Rozdělte `MMTTYCompat.h` na `MMTTYTypes.h` (typy, `CoreSys`) a `MMTTYCompat.h` (types + context + makra). `CoreContext.h` includuje `MMTTYTypes.h`.

Smazat `CoreGlobals.cpp`. Odstranit případné `extern double SampFreq;` v `Rtty.h:35` a podobné deklarace (`grep -n 'extern' Sources/MMTTYCore/mmtty/*.h`), protože po rozvinutí makra by byly neplatné.

Pokud makro koliduje s identifikátorem, který není globál (např. parametr funkce jménem `SampFreq`), přejmenujte ten lokální identifikátor. Kolize najdete `grep -nE '\b(double|int)\s+(SampFreq|DemSamp|FFT_SIZE)\b' Sources/MMTTYCore/mmtty/*`.

- [ ] **Step 5: Použít kontext v `RTTYCore.cpp`**

- Do `struct RTTYCore` přidat jako **první člen** `CoreContext ctx;`.
- V `rttycore_create`: nejdřív `auto* c = new RTTYCore(); CoreScope scope(&c->ctx);` a teprve pak nastavovat `SampFreq`, `InitSampType()`, `sys.*` a konstruovat `dem`, `mod`, `fft` (pořadí: globály před konstruktory, jako dosud). Neplatná konfigurace se kontroluje před `new`.
- **Každá** `extern "C"` funkce, která sahá na `dem`/`mod`/`fft`/`rtty`/`lms`, začíná `CoreScope scope(&c->ctx);` (po kontrole `if (!c)`), včetně `rttycore_destroy` (destruktory mohou číst globály).
- `CSinTable g_SinTable` v `Rtty.cpp` zůstává globální: je to neměnná tabulka s pevnou velikostí 48000, naplněná v konstruktoru. Ověřte, že konstruktor `CSinTable` **nečte** `SampFreq` (`grep -n 'CSinTable::CSinTable' -A 12 Sources/MMTTYCore/mmtty/Rtty.cpp`). Pokud čte, přesuňte ji do `CoreContext` jako `CSinTable* sinTable` a vytvářejte ji v `rttycore_create`.

- [ ] **Step 6: Spustit všechny testy**

Run: `swift test`
Expected: PASS všech testů, **golden testy beze změny fixtures**, nový `twoInstancesWithDifferentRatesAreIndependent` PASS.
Pokud golden test selže, refaktoring změnil chování. Najděte místo, kde se globál čte mimo `CoreScope` (typicky konstruktor volaný mimo C API), a opravte. **Nikdy nepřegenerovávejte golden soubory v tomto tasku.**

- [ ] **Step 7: Commit**

```bash
git add -A Sources/MMTTYCore Tests/MMTTYCoreTests
git commit -m "refactor(core): replace MMTTY globals with per-instance CoreContext (golden unchanged)"
```

---

### Task 9: ModemKit – obecný protokol modemu

**Files:**
- Create: `Sources/ModemKit/Modem.swift`, `ModeDescriptor.swift`, `Parameters.swift`, `ModemEvent.swift`
- Modify: `Package.swift`
- Test: `Tests/ModemKitTests/ParameterTests.swift`

**Interfaces:**
- Produces (přesně takto, používají je plány 2–5):

```swift
public struct ModeDescriptor: Sendable, Hashable, Codable {
    public let id: String            // "RTTY-45"
    public let displayName: String   // "RTTY 45.45 Bd"
    public let adifMode: String      // "RTTY"
    public let adifSubmode: String?  // nil
}

public enum ParameterKind: Sendable, Hashable {
    case bool
    case int(ClosedRange<Int>)
    case double(ClosedRange<Double>, unit: String?)
    case choice([String])
}

public enum ParameterValue: Sendable, Hashable, Codable {
    case bool(Bool), int(Int), double(Double), string(String)
}

public struct ParameterDescriptor: Sendable, Hashable {
    public let id: String
    public let label: String
    public let kind: ParameterKind
    public let defaultValue: ParameterValue
    public func validate(_ v: ParameterValue) throws(ParameterError) -> ParameterValue
}

public enum ParameterError: Error, Equatable, Sendable {
    case unknown(String), typeMismatch(String), outOfRange(String)
}

public struct ModemCapabilities: OptionSet, Sendable {
    public static let fskKeying, afc, multiChannel, imageOutput, textOutput
}

public struct SpectrumFrame: Sendable { public let binHz: Double; public let magnitudes: [Float] }

public struct TuningInfo: Sendable, Equatable { public let mark: Double; public let space: Double }

public enum ModemEvent: Sendable, Equatable {
    case rxText(Character, echo: Bool)
    case signal(level: Double, squelchOpen: Bool)
    case tuning(TuningInfo)
    case shift(fig: Bool)
    case overflow
    case txFinished
}

public enum TxStatus: Sendable, Equatable { case active, finished }

public protocol Modem: AnyObject {
    static var id: String { get }
    var modes: [ModeDescriptor] { get }
    var currentMode: ModeDescriptor { get }
    var sampleRate: Double { get }
    var capabilities: ModemCapabilities { get }
    var parameters: [ParameterDescriptor] { get }
    var events: AsyncStream<ModemEvent> { get }

    func select(mode: ModeDescriptor) throws
    func set(parameter id: String, value: ParameterValue) throws
    func get(parameter id: String) -> ParameterValue?

    func processRx(_ samples: UnsafeBufferPointer<Float>)
    func beginTx(tune: Bool)
    func queueTx(text: String)
    func generateTx(into buffer: UnsafeMutableBufferPointer<Float>) -> TxStatus
    func stopTx()      // dovysílá rozpracované, pak TxStatus.finished
    func abortTx()
    var txPending: Int { get }   // znaky čekající ve frontě modemu + v jádře
    func spectrum() -> SpectrumFrame?
}
```
Oproti specifikaci (4.1) je `queueTx`/`generateTx` doplněné o `beginTx`/`stopTx`/`abortTx`/`txPending`, které Engine (plán 2) potřebuje pro stavový automat. `rxImageLine` (SSTV) se přidá až s SSTV modemem (YAGNI).

- [ ] **Step 1: Napsat failing testy**

`Tests/ModemKitTests/ParameterTests.swift`:
```swift
import Testing
@testable import ModemKit

let baud = ParameterDescriptor(id: "baud", label: "Baud", kind: .double(20...300, unit: "Bd"),
                               defaultValue: .double(45.45))
let demod = ParameterDescriptor(id: "demodType", label: "Demodulator",
                                kind: .choice(["iir", "fir", "pll", "fft"]), defaultValue: .string("iir"))
let afc = ParameterDescriptor(id: "afc", label: "AFC", kind: .bool, defaultValue: .bool(true))
let taps = ParameterDescriptor(id: "firTap", label: "FIR taps", kind: .int(8...512), defaultValue: .int(72))

@Test func acceptsValidValues() throws {
    #expect(try baud.validate(.double(75)) == .double(75))
    #expect(try demod.validate(.string("pll")) == .string("pll"))
    #expect(try afc.validate(.bool(false)) == .bool(false))
    #expect(try taps.validate(.int(128)) == .int(128))
}

@Test func intIsAcceptedForDoubleParameter() throws {
    #expect(try baud.validate(.int(50)) == .double(50))
}

@Test func rejectsOutOfRangeAndWrongType() {
    #expect(throws: ParameterError.outOfRange("baud")) { try baud.validate(.double(0)) }
    #expect(throws: ParameterError.outOfRange("baud")) { try baud.validate(.double(.nan)) }
    #expect(throws: ParameterError.outOfRange("demodType")) { try demod.validate(.string("xyz")) }
    #expect(throws: ParameterError.typeMismatch("afc")) { try afc.validate(.string("yes")) }
    #expect(throws: ParameterError.outOfRange("firTap")) { try taps.validate(.int(4)) }
}

@Test func valueCodableRoundTrip() throws {
    let v: [ParameterValue] = [.bool(true), .int(3), .double(45.45), .string("iir")]
    let data = try JSONEncoder().encode(v)
    #expect(try JSONDecoder().decode([ParameterValue].self, from: data) == v)
}
```
(přidat `import Foundation` na začátek kvůli `JSONEncoder`)

`Package.swift`:
```swift
        .target(name: "ModemKit"),
        .testTarget(name: "ModemKitTests", dependencies: ["ModemKit"]),
```
a do `products`: `.library(name: "ModemKit", targets: ["ModemKit"]),`

- [ ] **Step 2: Spustit – musí selhat**

Run: `swift test --filter ModemKitTests`
Expected: FAIL při kompilaci.

- [ ] **Step 3: Implementovat**

`Sources/ModemKit/Parameters.swift`:
```swift
public enum ParameterKind: Sendable, Hashable {
    case bool
    case int(ClosedRange<Int>)
    case double(ClosedRange<Double>, unit: String?)
    case choice([String])
}

public enum ParameterValue: Sendable, Hashable, Codable {
    case bool(Bool), int(Int), double(Double), string(String)
}

public enum ParameterError: Error, Equatable, Sendable {
    case unknown(String), typeMismatch(String), outOfRange(String)
}

public struct ParameterDescriptor: Sendable, Hashable {
    public let id: String
    public let label: String
    public let kind: ParameterKind
    public let defaultValue: ParameterValue

    public init(id: String, label: String, kind: ParameterKind, defaultValue: ParameterValue) {
        self.id = id; self.label = label; self.kind = kind; self.defaultValue = defaultValue
    }

    /// Ověří hodnotu a vrátí ji v kanonickém typu (např. .int → .double u double parametru).
    public func validate(_ v: ParameterValue) throws(ParameterError) -> ParameterValue {
        switch (kind, v) {
        case (.bool, .bool): return v
        case (.int(let r), .int(let i)):
            guard r.contains(i) else { throw .outOfRange(id) }
            return v
        case (.double(let r, _), .double(let d)):
            guard d.isFinite, r.contains(d) else { throw .outOfRange(id) }
            return v
        case (.double(let r, _), .int(let i)):
            guard r.contains(Double(i)) else { throw .outOfRange(id) }
            return .double(Double(i))
        case (.choice(let opts), .string(let s)):
            guard opts.contains(s) else { throw .outOfRange(id) }
            return v
        default:
            throw .typeMismatch(id)
        }
    }
}
```

`Sources/ModemKit/ModeDescriptor.swift`:
```swift
public struct ModeDescriptor: Sendable, Hashable, Codable {
    public let id: String
    public let displayName: String
    public let adifMode: String
    public let adifSubmode: String?

    public init(id: String, displayName: String, adifMode: String, adifSubmode: String? = nil) {
        self.id = id; self.displayName = displayName
        self.adifMode = adifMode; self.adifSubmode = adifSubmode
    }
}
```

`Sources/ModemKit/ModemEvent.swift`:
```swift
public struct ModemCapabilities: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let fskKeying    = ModemCapabilities(rawValue: 1 << 0)
    public static let afc          = ModemCapabilities(rawValue: 1 << 1)
    public static let multiChannel = ModemCapabilities(rawValue: 1 << 2)
    public static let imageOutput  = ModemCapabilities(rawValue: 1 << 3)
    public static let textOutput   = ModemCapabilities(rawValue: 1 << 4)
}

public struct SpectrumFrame: Sendable {
    public let binHz: Double
    public let magnitudes: [Float]
    public init(binHz: Double, magnitudes: [Float]) { self.binHz = binHz; self.magnitudes = magnitudes }
}

public struct TuningInfo: Sendable, Equatable {
    public let mark: Double
    public let space: Double
    public init(mark: Double, space: Double) { self.mark = mark; self.space = space }
}

public enum ModemEvent: Sendable, Equatable {
    case rxText(Character, echo: Bool)
    case signal(level: Double, squelchOpen: Bool)
    case tuning(TuningInfo)
    case shift(fig: Bool)
    case overflow
    case txFinished
}

public enum TxStatus: Sendable, Equatable { case active, finished }
```

`Sources/ModemKit/Modem.swift`: protokol přesně podle bloku **Interfaces** výše, s doc-komentářem u každé metody:
- `processRx`, `generateTx` a `spectrum` se volají **jen z DSP vlákna**.
- Ostatní metody se volají z Engine, který zajistí serializaci s DSP vláknem (plán 2).
- `events` je bezpečné číst odkudkoli.

- [ ] **Step 4: Spustit testy**

Run: `swift test --filter ModemKitTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/ModemKit Tests/ModemKitTests
git commit -m "feat(modemkit): Modem protocol, parameter descriptors with validation, events"
```

---

### Task 10: RTTYModem – implementace `Modem` nad MMTTYCore

**Files:**
- Create: `Sources/RTTYModem/RTTYModem.swift`, `Sources/RTTYModem/RTTYParameters.swift`
- Modify: `Package.swift`
- Test: `Tests/RTTYModemTests/RTTYModemTests.swift`

**Interfaces:**
- Consumes: C API (Task 4–6, 8), `ModemKit` (Task 9).
- Produces:
  - `public final class RTTYModem: Modem, @unchecked Sendable`
  - `public init(sampleRate: Double = 11025, config: RTTYModem.Config = .init()) throws(RTTYModem.Error)`
  - `public struct Config: Sendable { public var codeSet: CodeSet = .us; public var doubleShift = false; public var txUOS = true; public var txOffset = 0.0 }`, `public enum CodeSet: Sendable { case us, japanese }`
  - `public enum Error: Swift.Error, Equatable { case unsupportedSampleRate(Double), parameter(ParameterError) }`
  - `static let id = "rtty"`; módy `RTTY-45` (45,45), `RTTY-50`, `RTTY-75`, `RTTY-100`, `RTTY-110` (ADIF `MODE=RTTY`)
  - ID parametrů (pro API v plánu 4): `baud`, `mark`, `shift`, `reverse`, `afc`, `afcMode` (`free|fixed|ham|fsk`), `net` (zatím jen uložené, použije Engine), `atc`, `squelch`, `squelchLevel`, `demodType` (`iir|fir|pll|fft`), `iirBandwidth`, `firTaps`, `integrator` (`average|lpf`), `smoothFreq`, `lpfOrder`, `majority`, `ignoreFraming`, `bitLength`, `stopBits` (`1|1.5|2|1.42`), `parity` (`none|even|odd|mark|space`), `uos`, `diddle` (`off|blk|ltr`), `echo`, `bpf`, `bpfWidth`, `lms`, `txGain`.

- [ ] **Step 1: Napsat failing testy**

`Tests/RTTYModemTests/RTTYModemTests.swift`:
```swift
import Testing
import ModemKit
@testable import RTTYModem
import RTTYSignalKit

func collectText(_ m: RTTYModem, _ samples: [Float]) async -> String {
    let stream = m.events
    samples.withUnsafeBufferPointer { p in
        var i = 0
        while i < p.count {
            let n = min(512, p.count - i)
            m.processRx(UnsafeBufferPointer(rebasing: p[i..<i + n])); i += n
        }
    }
    m.finishEventsForTesting()
    var text = ""
    for await e in stream { if case .rxText(let c, false) = e { text.append(c) } }
    return text
}

@Test func decodesViaModemProtocol() async throws {
    let m = try RTTYModem()
    let text = "CQ CQ DE OK1XOE K\r\n"
    let s = RTTYSignalGenerator().generate(text: text)
    #expect(await collectText(m, s) == text)
}

@Test func rejectsUnsupportedRate() {
    #expect(throws: RTTYModem.Error.unsupportedSampleRate(48000)) { try RTTYModem(sampleRate: 48000) }
}

@Test func parameterRoundTripAndValidation() throws {
    let m = try RTTYModem()
    try m.set(parameter: "shift", value: .double(850))
    #expect(m.get(parameter: "shift") == .double(850))
    #expect(m.get(parameter: "mark") == .double(2125))
    try m.set(parameter: "demodType", value: .string("pll"))
    #expect(m.get(parameter: "demodType") == .string("pll"))
    #expect(throws: RTTYModem.Error.parameter(.outOfRange("baud"))) {
        try m.set(parameter: "baud", value: .double(1000))
    }
    #expect(throws: RTTYModem.Error.parameter(.unknown("nope"))) {
        try m.set(parameter: "nope", value: .bool(true))
    }
}

@Test func selectModeChangesBaud() throws {
    let m = try RTTYModem()
    let m75 = try #require(m.modes.first { $0.id == "RTTY-75" })
    try m.select(mode: m75)
    #expect(m.currentMode == m75)
    #expect(m.get(parameter: "baud") == .double(75))
}

@Test func everyParameterDefaultIsValid() throws {
    let m = try RTTYModem()
    for p in m.parameters {
        #expect(throws: Never.self) { _ = try p.validate(p.defaultValue) }
        #expect(m.get(parameter: p.id) != nil, "get(\(p.id)) vrací nil")
    }
}

// Review Focus 4: text delší než TX buffer jádra se odvysílá celý
@Test func longTextIsFullyTransmitted() async throws {
    let tx = try RTTYModem()
    let long = String(repeating: "RYRYRY CQ TEST ", count: 200)      // 3000 znaků
    tx.beginTx(tune: false)
    tx.queueTx(text: long)
    var out: [Float] = []
    var buf = [Float](repeating: 0, count: 4096)
    var stopped = false
    for _ in 0..<10_000 {
        if !stopped && tx.txPending == 0 { tx.stopTx(); stopped = true }
        let st = buf.withUnsafeMutableBufferPointer { tx.generateTx(into: $0) }
        out += buf
        if st == .finished { break }
    }
    let rx = try RTTYModem()
    let decoded = await collectText(rx, out)
    #expect(decoded.components(separatedBy: "CQ TEST").count - 1 >= 199)
}

@Test func spectrumAvailableAfterProcessing() throws {
    let m = try RTTYModem()
    let s = RTTYSignalGenerator().generate(text: "", leadIn: 1.0, tail: 0)
    s.withUnsafeBufferPointer { m.processRx($0) }
    let frame = try #require(m.spectrum())
    #expect(frame.binHz > 0 && !frame.magnitudes.isEmpty)
}
```

`Package.swift`:
```swift
        .target(name: "RTTYModem", dependencies: ["MMTTYCore", "ModemKit"]),
        .testTarget(name: "RTTYModemTests", dependencies: ["RTTYModem", "ModemKit", "RTTYSignalKit"]),
```
a do `products`: `.library(name: "RTTYModem", targets: ["RTTYModem"]),`

- [ ] **Step 2: Spustit – musí selhat**

Run: `swift test --filter RTTYModemTests`
Expected: FAIL při kompilaci.

- [ ] **Step 3: Implementovat `RTTYParameters.swift`**

Tabulka `static let descriptors: [ParameterDescriptor]` se všemi ID z **Interfaces**, rozsahy podle komentářů v `RTTYCore.h`. Převodní funkce:
- `func coreParam(for id: String) -> RTTYCoreParam?`
- `func toCore(_ id: String, _ v: ParameterValue) -> Double`: choice → index; `stopBits` `1|1.5|2|1.42` → `0|1|2|4`; `afcMode` `free|fixed|ham|fsk` → `0|1|2|3`; `diddle` `off|blk|ltr` → `0|1|2`; `integrator` `average|lpf` → `0|1`; bool → 0/1.
- `func fromCore(_ id: String, _ d: Double) -> ParameterValue` (inverzní).

Parametr `shift` není v jádře: `set(shift)` nastaví `RC_SPACE = mark + shift`, `get(shift)` = `space - mark`. `set(mark)` zachová shift, tj. nastaví mark i space. `net` se jen uloží ve Swiftu.

- [ ] **Step 4: Implementovat `RTTYModem.swift`**

```swift
import MMTTYCore
import ModemKit

public final class RTTYModem: Modem, @unchecked Sendable {
    public enum CodeSet: Sendable { case us, japanese }
    public struct Config: Sendable {
        public var codeSet: CodeSet = .us
        public var doubleShift = false
        public var txUOS = true
        public var txOffset = 0.0
        public init() {}
    }
    public enum Error: Swift.Error, Equatable {
        case unsupportedSampleRate(Double), parameter(ParameterError)
    }

    public static let id = "rtty"
    public let modes: [ModeDescriptor] = [
        .init(id: "RTTY-45", displayName: "RTTY 45.45 Bd", adifMode: "RTTY"),
        .init(id: "RTTY-50", displayName: "RTTY 50 Bd", adifMode: "RTTY"),
        .init(id: "RTTY-75", displayName: "RTTY 75 Bd", adifMode: "RTTY"),
        .init(id: "RTTY-100", displayName: "RTTY 100 Bd", adifMode: "RTTY"),
        .init(id: "RTTY-110", displayName: "RTTY 110 Bd", adifMode: "RTTY"),
    ]
    static let modeBaud: [String: Double] = ["RTTY-45": 45.45, "RTTY-50": 50, "RTTY-75": 75,
                                             "RTTY-100": 100, "RTTY-110": 110]
    public private(set) var currentMode: ModeDescriptor
    public let sampleRate: Double
    public let capabilities: ModemCapabilities = [.fskKeying, .afc, .textOutput]
    public var parameters: [ParameterDescriptor] { RTTYParameters.descriptors }
    public let events: AsyncStream<ModemEvent>

    private let core: OpaquePointer
    private let continuation: AsyncStream<ModemEvent>.Continuation
    private var samplesSinceTick = 0
    private let tickInterval: Int
    private var txQueue: [UInt8] = []          // UTF-8 bajty čekající na místo v jádře
    private var net = true
    private var lastFig = false
    private var lastTuning = TuningInfo(mark: 0, space: 0)
    private var charBuf = [RTTYCoreChar](repeating: RTTYCoreChar(), count: 256)

    public init(sampleRate: Double = 11025, config: Config = .init()) throws(Error) {
        var cfg = rttycore_default_config()
        cfg.sampleRate = sampleRate
        cfg.codeSet = config.codeSet == .us ? 0 : 1
        cfg.doubleShift = config.doubleShift ? 1 : 0
        cfg.txUOS = config.txUOS ? 1 : 0
        cfg.txOffset = config.txOffset
        guard let c = rttycore_create(&cfg) else { throw .unsupportedSampleRate(sampleRate) }
        core = c
        self.sampleRate = sampleRate
        tickInterval = Int(sampleRate / 10)
        currentMode = modes[0]
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(4096))
    }

    deinit {
        continuation.finish()
        rttycore_destroy(core)
    }

    public func select(mode: ModeDescriptor) throws {
        guard let baud = Self.modeBaud[mode.id] else { throw Error.parameter(.unknown(mode.id)) }
        try set(parameter: "baud", value: .double(baud))
        currentMode = mode
    }

    public func set(parameter id: String, value: ParameterValue) throws {
        guard let d = RTTYParameters.descriptors.first(where: { $0.id == id }) else {
            throw Error.parameter(.unknown(id))
        }
        let v: ParameterValue
        do { v = try d.validate(value) } catch { throw Error.parameter(error) }
        try RTTYParameters.apply(id: id, value: v, core: core, net: &net)
    }

    public func get(parameter id: String) -> ParameterValue? {
        RTTYParameters.read(id: id, core: core, net: net)
    }

    public func processRx(_ samples: UnsafeBufferPointer<Float>) {
        var offset = 0
        while offset < samples.count {
            let n = min(samples.count - offset, tickInterval - samplesSinceTick)
            rttycore_process_rx(core, samples.baseAddress! + offset, n)
            offset += n
            samplesSinceTick += n
            if samplesSinceTick >= tickInterval {
                samplesSinceTick = 0
                _ = rttycore_tick(core)
                publishStatus()
            }
            drainChars()
        }
    }

    private func drainChars() {
        while true {
            let got = charBuf.withUnsafeMutableBufferPointer {
                rttycore_read_chars(core, $0.baseAddress!, $0.count)
            }
            if got == 0 { break }
            for k in 0..<got {
                let ch = Character(UnicodeScalar(UInt8(bitPattern: charBuf[k].ch)))
                continuation.yield(.rxText(ch, echo: charBuf[k].echo != 0))
            }
        }
    }

    private func publishStatus() {
        let s = rttycore_signal(core)
        continuation.yield(.signal(level: s.level, squelchOpen: s.squelchOpen != 0))
        if s.overflow != 0 { continuation.yield(.overflow) }
        let t = TuningInfo(mark: s.mark, space: s.space)
        if t != lastTuning { lastTuning = t; continuation.yield(.tuning(t)) }
        let fig = s.fig != 0
        if fig != lastFig { lastFig = fig; continuation.yield(.shift(fig: fig)) }
    }

    public func beginTx(tune: Bool) { txQueue.removeAll(); rttycore_tx_begin(core, tune ? 1 : 0) }

    public func queueTx(text: String) { txQueue += Array(text.utf8); feedCore() }

    private func feedCore() {
        guard !txQueue.isEmpty else { return }
        var chunk = txQueue.prefix(256).map { CChar(bitPattern: $0) } + [0]
        let used = rttycore_queue_tx(core, &chunk)
        txQueue.removeFirst(used)
    }

    public func generateTx(into buffer: UnsafeMutableBufferPointer<Float>) -> TxStatus {
        feedCore()
        let n = rttycore_generate_tx(core, buffer.baseAddress!, buffer.count)
        drainChars()                                   // echo odvysílaného textu
        if n < buffer.count { continuation.yield(.txFinished); return .finished }
        return .active
    }

    public func stopTx() { txQueue.removeAll(); rttycore_tx_stop(core) }
    public func abortTx() { txQueue.removeAll(); rttycore_tx_abort(core) }
    public var txPending: Int { txQueue.count + rttycore_tx_pending(core) }

    public func spectrum() -> SpectrumFrame? {
        var mags = [Float](repeating: 0, count: 2048)
        var binHz = 0.0
        let n = rttycore_spectrum(core, &mags, mags.count, &binHz)
        guard n > 0 else { return nil }
        return SpectrumFrame(binHz: binHz, magnitudes: Array(mags[0..<n]))
    }

    /// Jen pro testy: ukončí stream událostí, aby šel přečíst do konce.
    func finishEventsForTesting() { continuation.finish() }
}
```

Pozn. k `stopTx`: MMTTY `ToRX` zahodí zbytek bufferu. Engine v plánu 2 volá `stopTx` až po `txPending == 0` (drain). Test `longTextIsFullyTransmitted` tak postupuje.

- [ ] **Step 5: Spustit testy**

Run: `swift test --filter RTTYModemTests`
Expected: PASS.

- [ ] **Step 6: Spustit celou sadu**

Run: `swift test`
Expected: PASS všech testů.

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources/RTTYModem Tests/RTTYModemTests
git commit -m "feat(rtty): RTTYModem implementing Modem over MMTTYCore C API"
```

---

### Task 11: CLI `rtty-tool` (gen / decode / encode)

**Files:**
- Create: `Sources/rtty-tool/main.swift`
- Modify: `Package.swift`, `README.md`

**Interfaces:**
- Consumes: `RTTYModem`, `WaveFile`, `RTTYSignalGenerator`, `NoiseGenerator`.
- Produces: spustitelný `rtty-tool`:
  - `rtty-tool gen "TEXT" out.wav [--baud 45.45] [--mark 2125] [--shift 170] [--noise 0.1] [--seed 1]` – nezávislý generátor
  - `rtty-tool encode "TEXT" out.wav [--baud 45.45] [--mark 2125] [--shift 170]` – vysílač MMTTY jádra
  - `rtty-tool decode in.wav [--baud 45.45] [--mark 2125] [--shift 170] [--demod iir|fir|pll|fft] [--no-afc]` – vypíše text na stdout
  - Chyby (neexistující soubor, špatný WAV, nepodporovaná frekvence) → hláška na stderr, exit kód 1. WAV s jinou frekvencí než 11025/12000 → chyba „resampling přijde v plánu 2 (AudioIO); převeďte např. `ffmpeg -i in.wav -ar 11025 -ac 1 out.wav`“.

- [ ] **Step 1: Přidat target**

```swift
        .executableTarget(name: "rtty-tool", dependencies: ["RTTYModem", "WaveFile", "RTTYSignalKit"]),
```
a do `products`: `.executable(name: "rtty-tool", targets: ["rtty-tool"]),`

- [ ] **Step 2: Implementovat `main.swift`**

```swift
import Foundation
import ModemKit
import RTTYModem
import RTTYSignalKit
import WaveFile

struct Options {
    var baud = 45.45, mark = 2125.0, shift = 170.0, noise: Float = 0, seed: UInt64 = 1
    var demod = "iir", afc = true
    var positional: [String] = []
}

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data("rtty-tool: \(msg)\n".utf8)); exit(1)
}

func parse(_ args: ArraySlice<String>) -> Options {
    var o = Options()
    var it = args.makeIterator()
    func num(_ name: String) -> Double {
        guard let s = it.next(), let v = Double(s) else { fail("\(name) očekává číslo") }
        return v
    }
    while let a = it.next() {
        switch a {
        case "--baud": o.baud = num(a)
        case "--mark": o.mark = num(a)
        case "--shift": o.shift = num(a)
        case "--noise": o.noise = Float(num(a))
        case "--seed": o.seed = UInt64(num(a))
        case "--demod": o.demod = it.next() ?? fail("--demod očekává iir|fir|pll|fft")
        case "--no-afc": o.afc = false
        default:
            if a.hasPrefix("--") { fail("neznámý přepínač \(a)") }
            o.positional.append(a)
        }
    }
    return o
}

func configure(_ m: RTTYModem, _ o: Options) {
    do {
        try m.set(parameter: "baud", value: .double(o.baud))
        try m.set(parameter: "mark", value: .double(o.mark))
        try m.set(parameter: "shift", value: .double(o.shift))
        try m.set(parameter: "demodType", value: .string(o.demod))
        try m.set(parameter: "afc", value: .bool(o.afc))
    } catch { fail("neplatný parametr: \(error)") }
}

let usage = """
    použití:
      rtty-tool gen "TEXT" out.wav [--baud B] [--mark F] [--shift S] [--noise RMS] [--seed N]
      rtty-tool encode "TEXT" out.wav [--baud B] [--mark F] [--shift S]
      rtty-tool decode in.wav [--baud B] [--mark F] [--shift S] [--demod iir|fir|pll|fft] [--no-afc]
    """

let argv = CommandLine.arguments
guard argv.count >= 2 else { fail(usage) }
let o = parse(argv.dropFirst(2))

switch argv[1] {
case "gen":
    guard o.positional.count == 2 else { fail(usage) }
    var s = RTTYSignalGenerator(baud: o.baud, markHz: o.mark, shiftHz: o.shift)
        .generate(text: o.positional[0])
    var n = NoiseGenerator(seed: o.seed)
    if o.noise > 0 { n.addNoise(to: &s, rms: o.noise) }
    do { try WaveFile.write(samples: s, sampleRate: 11025, to: URL(fileURLWithPath: o.positional[1])) }
    catch { fail("zápis selhal: \(error)") }

case "encode":
    guard o.positional.count == 2 else { fail(usage) }
    let m: RTTYModem
    do { m = try RTTYModem() } catch { fail("\(error)") }
    configure(m, o)
    m.beginTx(tune: false)
    m.queueTx(text: o.positional[0])
    var out: [Float] = [], buf = [Float](repeating: 0, count: 4096)
    var stopped = false
    for _ in 0..<1_000_000 {
        if !stopped && m.txPending == 0 { m.stopTx(); stopped = true }
        let st = buf.withUnsafeMutableBufferPointer { m.generateTx(into: $0) }
        out += buf
        if st == .finished { break }
    }
    do { try WaveFile.write(samples: out, sampleRate: 11025, to: URL(fileURLWithPath: o.positional[1])) }
    catch { fail("zápis selhal: \(error)") }

case "decode":
    guard o.positional.count == 1 else { fail(usage) }
    let samples: [Float], rate: Int
    do { (samples, rate) = try WaveFile.read(from: URL(fileURLWithPath: o.positional[0])) }
    catch { fail("čtení selhalo: \(error)") }
    let m: RTTYModem
    do { m = try RTTYModem(sampleRate: Double(rate)) }
    catch {
        fail("WAV má \(rate) Hz; podporováno 11025/12000. Resampling přijde v plánu 2 (AudioIO); převeďte např. ffmpeg -i in.wav -ar 11025 -ac 1 out.wav")
    }
    configure(m, o)
    let events = m.events
    let reader = Task {
        for await e in events { if case .rxText(let c, false) = e { print(c, terminator: "") } }
    }
    samples.withUnsafeBufferPointer { m.processRx($0) }
    m.abortTx()
    try? await Task.sleep(for: .milliseconds(100))
    reader.cancel()
    print()

default:
    fail(usage)
}
```

Ukončení streamu v `decode` přes `sleep` je křehké. Přidejte do `RTTYModem` veřejnou metodu `public func finishEvents()` (a `finishEventsForTesting` z Task 10 přepište tak, aby ji volala). V `decode` pak `m.finishEvents(); await reader.value` místo sleepu a `cancel`.

- [ ] **Step 3: Ruční ověření**

```bash
swift build -c release
.build/release/rtty-tool gen "CQ CQ DE OK1XOE K" /tmp/cq.wav --noise 0.1
.build/release/rtty-tool decode /tmp/cq.wav
.build/release/rtty-tool encode "TEST DE OK1XOE" /tmp/tx.wav
.build/release/rtty-tool decode /tmp/tx.wav
.build/release/rtty-tool decode Tests/MMTTYCoreTests/Fixtures/golden/noise6db-45-iir.wav
.build/release/rtty-tool decode /neexistuje.wav; echo "exit=$?"
```
Expected:
- 1. dekódování obsahuje `CQ CQ DE OK1XOE K`
- 2. obsahuje `TEST DE OK1XOE`
- 3. se shoduje s `noise6db-45-iir.expected.txt`
- 4. hláška na stderr a `exit=1`

- [ ] **Step 4: Doplnit README** (sekce „Nástroj rtty-tool“ s příklady ze Step 3)

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/rtty-tool Sources/RTTYModem README.md
git commit -m "feat(cli): rtty-tool gen/encode/decode"
```

---

## Hotovo, když

- `swift test` projde celý (Swift Testing, bez Xcode).
- Golden testy procházejí beze změny fixtures po Task 8.
- `rtty-tool decode` dekóduje skutečnou nahrávku RTTY z pásma převedenou na 11025 Hz. Ruční test: nahrajte 30 s RTTY z přijímače a převeďte přes `ffmpeg -ar 11025 -ac 1`. Výsledek zapište do PR / poznámky.
