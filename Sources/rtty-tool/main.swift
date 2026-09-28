import AudioIO
import Engine
import Foundation
import Keying
import RigControl
import ModemKit
import RTTYModem
import RTTYSignalKit
import WaveFile

struct Options {
    var baud = 45.45, mark = 2125.0, shift = 170.0, noise: Float = 0, seed: UInt64 = 1
    var demod = "iir", afc = true
    var inUID: String?, outUID: String?, ptt = "none", port: String?, rig = "none", fsk: String?
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
        case "--seed": o.seed = UInt64(max(0, num(a)))
        case "--demod":
            guard let v = it.next() else { fail("--demod očekává iir|fir|pll|fft") }
            o.demod = v
        case "--no-afc": o.afc = false
        case "--in": o.inUID = it.next()
        case "--out": o.outUID = it.next()
        case "--ptt": o.ptt = it.next() ?? "none"
        case "--port": o.port = it.next()
        case "--rig": o.rig = it.next() ?? "none"
        case "--fsk": o.fsk = it.next()
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

func writeWav(_ s: [Float], _ path: String) {
    do { try WaveFile.write(samples: s, sampleRate: 11025, to: URL(fileURLWithPath: path)) }
    catch { fail("zápis \(path) selhal: \(error)") }
}

/// Obsluha SIGINT/SIGTERM mimo hlavní actor (hlavní vlákno blokuje readLine()).
nonisolated(unsafe) var signalSources: [DispatchSourceSignal] = []   // musí žít po celou dobu běhu

nonisolated func installStopOnSignals(_ engine: Engine) {
    signal(SIGINT, SIG_IGN); signal(SIGTERM, SIG_IGN)
    let q = DispatchQueue(label: "signals")
    signalSources = [SIGINT, SIGTERM].map { sig in
        let src = DispatchSource.makeSignalSource(signal: sig, queue: q)
        src.setEventHandler { @Sendable in
            FileHandle.standardError.write(Data("\n[ukončuji – PTT off]\n".utf8))
            Task.detached { await engine.stop(); exit(0) }
        }
        src.resume()
        return src
    }
}

let usage = """
    použití:
      rtty-tool gen "TEXT" out.wav [--baud B] [--mark F] [--shift S] [--noise RMS] [--seed N]
      rtty-tool encode "TEXT" out.wav [--baud B] [--mark F] [--shift S]
      rtty-tool decode in.wav [--baud B] [--mark F] [--shift S] [--demod iir|fir|pll|fft] [--no-afc]
      rtty-tool devices
      rtty-tool level [--in UID]          úroveň vstupu (5 s)
      rtty-tool live [--in UID] [--out UID] [--ptt none|rts|dtr|rtsDtr|cat] [--port /dev/cu.X]
                     [--rig none|hamlib|flrig] [--fsk uart|soft-dtr|soft-rts|soft-break] [--baud B] [--mark F]
         stdin: text = odvysílat (TX → text → RX po dovysílání), :tx, :rx, :abort, :tune, :q
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
    writeWav(s, o.positional[1])

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
    writeWav(out + [Float](repeating: 0, count: 2205), o.positional[1])   // + 0,2 s doběh

case "decode":
    guard o.positional.count == 1 else { fail(usage) }
    let samples: [Float], rate: Int
    do { (samples, rate) = try WaveFile.read(from: URL(fileURLWithPath: o.positional[0])) }
    catch { fail("čtení \(o.positional[0]) selhalo: \(error)") }
    let m: RTTYModem
    do { m = try RTTYModem(sampleRate: Double(rate)) }
    catch {
        fail("WAV má \(rate) Hz; podporováno 11025/12000. Resampling přijde s AudioIO; převeďte např. ffmpeg -i in.wav -ar 11025 -ac 1 out.wav")
    }
    configure(m, o)
    let events = m.events
    let reader = Task.detached {   // mimo main actor, aby četl souběžně s processRx
        var text = ""
        for await e in events { if case .rxText(let c, false) = e { text.append(c) } }
        return text
    }
    samples.withUnsafeBufferPointer { m.processRx($0) }
    m.finishEvents()
    print(await reader.value)

case "devices":
    print("Zvuková zařízení:")
    for d in AudioDevices.all() {
        print("  \(d.name)  [uid: \(d.uid)]  in:\(d.inputChannels) out:\(d.outputChannels) \(Int(d.sampleRate)) Hz")
    }
    print("Výchozí vstup: \(AudioDevices.defaultInput()?.name ?? "-"), výstup: \(AudioDevices.defaultOutput()?.name ?? "-")")
    print("Sériové porty:")
    for p in POSIXSerialPort.availablePorts() { print("  \(p)") }

case "level":
    let be = CoreAudioBackend()
    var cfg = AudioConfig(); cfg.inputUID = o.inUID
    do { try be.start(modemRate: 11025, config: cfg) } catch { fail("audio: \(error)") }
    var buf = [Float](repeating: 0, count: 11025)
    for _ in 0..<10 {
        try? await Task.sleep(for: .milliseconds(500))
        var n = 0, sum: Float = 0, got = 0
        repeat { n = be.readRx(into: &buf); for i in 0..<n { sum += buf[i] * buf[i] }; got += n } while n > 0
        let rms = got > 0 ? (sum / Float(got)).squareRoot() : 0
        print(String(format: "vzorků %5d  RMS %.4f  (%.1f dBFS)", got, rms, 20 * log10(max(rms, 1e-9))))
    }
    be.stop()

case "live":
    let m: RTTYModem
    do { m = try RTTYModem() } catch { fail("\(error)") }
    configure(m, o)
    var cfg = EngineConfig()
    cfg.audio.inputUID = o.inUID
    cfg.audio.outputUID = o.outUID
    guard let pm = PTTMethod(rawValue: o.ptt) else { fail("--ptt: \(o.ptt)") }
    cfg.ptt = pm
    cfg.pttPort = o.port
    func fskPort() -> String {
        guard let p = o.port else { fail("--fsk potřebuje --port") }
        return p
    }
    switch o.fsk {
    case nil: cfg.txOutput = .afsk
    case "uart"?: cfg.txOutput = .fskUART(path: fskPort())
    case "soft-dtr"?: cfg.txOutput = .fskSoft(path: fskPort(), line: .dtr)
    case "soft-rts"?: cfg.txOutput = .fskSoft(path: fskPort(), line: .rts)
    case "soft-break"?: cfg.txOutput = .fskSoft(path: fskPort(), line: .txdBreak)
    default: fail("--fsk: \(o.fsk!)")
    }
    let rig: Rig
    switch o.rig {
    case "hamlib": rig = HamlibClient()
    case "flrig": rig = FlrigClient()
    case "none": rig = NoRig()
    default: fail("--rig: \(o.rig)")
    }
    let engine = Engine(modem: m, rig: rig, audio: CoreAudioBackend(), config: cfg)
    let events = engine.events()
    let printer = Task.detached {
        for await e in events {
            switch e {
            case .modem(.rxText(let c, _)):
                FileHandle.standardOutput.write(Data(String(c).utf8))
            case .state(let s): FileHandle.standardError.write(Data("\n[\(s.rawValue)]\n".utf8))
            case .rig(let r):
                FileHandle.standardError.write(Data("\n[rig \(r.online ? "online" : "offline") \(r.frequency.map { String(Int($0)) } ?? "")]\n".utf8))
            case .error(let err): FileHandle.standardError.write(Data("\n[chyba \(err)]\n".utf8))
            case .pttTimeout: FileHandle.standardError.write(Data("\n[PTT timeout]\n".utf8))
            default: break
            }
        }
    }
    do { try await engine.start() } catch { fail("start: \(error)") }
    // Ctrl-C / SIGTERM: vždy bezpečně vypnout PTT a FSK linku
    installStopOnSignals(engine)
    FileHandle.standardError.write(Data("mmtty4mac live – text + Enter = vysílat, :q = konec\n".utf8))
    while let line = readLine() {
        switch line {
        case ":q": break
        case ":tx": do { try await engine.tx() } catch { print("TX: \(error)") }; continue
        case ":tune": do { try await engine.tune() } catch { print("TX: \(error)") }; continue
        case ":rx": await engine.rx(); continue
        case ":abort": await engine.rxNow(); continue
        default:
            await engine.send(text: line + "\r\n")
            do { try await engine.tx(); await engine.rx() } catch { print("TX: \(error)") }
            continue
        }
        break
    }
    await engine.stop()
    await printer.value

default:
    fail(usage)
}
