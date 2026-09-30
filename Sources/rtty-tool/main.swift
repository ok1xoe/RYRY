import APIServer
import AppCore
import AudioIO
import Engine
import Foundation
import Keying
import MacroEngine
import QSOLog
import Settings
import RigControl
import ModemKit
import RTTYModem
import RTTYSignalKit
import WaveFile

struct Options {
    var baud = 45.45, mark = 2125.0, shift = 170.0, noise: Float = 0, seed: UInt64 = 1
    var demod = "iir", afc = true
    var inUID: String?, outUID: String?, ptt = "none", port: String?, rig = "none", fsk: String?
    var call = "", his = ""
    var settingsDir: String?, pttSet = false, rigSet = false, noAPI = false
    var modemFlags: Set<String> = []      // modem switches given on the command line
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
        case "--baud": o.baud = num(a); o.modemFlags.insert("baud")
        case "--mark": o.mark = num(a); o.modemFlags.insert("mark")
        case "--shift": o.shift = num(a); o.modemFlags.insert("shift")
        case "--noise": o.noise = Float(num(a))
        case "--seed": o.seed = UInt64(max(0, num(a)))
        case "--demod":
            guard let v = it.next() else { fail("--demod očekává iir|fir|pll|fft") }
            o.demod = v; o.modemFlags.insert("demodType")
        case "--no-afc": o.afc = false; o.modemFlags.insert("afc")
        case "--in": o.inUID = it.next()
        case "--out": o.outUID = it.next()
        case "--ptt": o.ptt = it.next() ?? "none"; o.pttSet = true
        case "--port": o.port = it.next()
        case "--rig": o.rig = it.next() ?? "none"; o.rigSet = true
        case "--fsk": o.fsk = it.next()
        case "--call": o.call = it.next() ?? ""
        case "--settings": o.settingsDir = it.next()
        case "--no-api": o.noAPI = true
        case "--his": o.his = it.next() ?? ""
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

/// SIGINT/SIGTERM handling outside the main actor (the main thread is blocked in readLine()).
nonisolated(unsafe) var signalSources: [DispatchSourceSignal] = []   // must stay alive for the whole run

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
      rtty-tool macro "TEMPLATE" [--call MY --his HIS]   náhled makra (MMTTY syntaxe)
      rtty-tool level [--in UID]          úroveň vstupu (5 s)
      rtty-tool live [--in UID] [--out UID] [--ptt none|rts|dtr|rtsDtr|cat] [--port /dev/cu.X]
                     [--rig none|hamlib|flrig] [--fsk uart|soft-dtr|soft-rts|soft-break] [--baud B] [--mark F]
         stdin: text = odvysílat (TX → text → RX po dovysílání), :tx, :rx, :abort, :tune, :q,
                :c ZNAČKA (protistanice), :m1…:m12 (makra), :log; [--call MOJE] [--his PROTISTANICE] [--settings DIR] [--no-api]
         nastavení: ~/Library/Application Support/mmtty4mac/settings.json (API: fldigi :7362, JSON-RPC :7363)
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
    writeWav(out + [Float](repeating: 0, count: 2205), o.positional[1])   // + 0.2 s tail

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
    let reader = Task.detached {   // off the main actor so it reads concurrently with processRx
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

case "macro":
    guard o.positional.count == 1 else { fail(usage) }
    var mc = MacroContext(); mc.myCall = o.call; mc.hisCall = o.his
    let tpl = o.positional[0].replacingOccurrences(of: "\\r", with: "\r").replacingOccurrences(of: "\\n", with: "\n")
    let r = MacroEngine.expand(tpl, context: mc)
    print(r.plainText.replacingOccurrences(of: "\r\n", with: "⏎\n"))
    print("[konec: \(r.end), režim: \(r.mode)\(r.logQSO ? ", log" : "")]")

case "live":
    // Settings from the file (or --settings DIR); the command-line switches take precedence.
    let store = SettingsStore(directory: o.settingsDir.map { URL(fileURLWithPath: $0) } ?? SettingsPaths.defaultDirectory)
    var (settings, warnings) = store.load()
    for w in warnings { FileHandle.standardError.write(Data("[nastavení] \(w)\n".utf8)) }
    if !o.call.isEmpty { settings.station.call = o.call.uppercased() }
    if let v = o.inUID { settings.audio.inputUID = v }
    if let v = o.outUID { settings.audio.outputUID = v }
    if o.pttSet { guard let pm = PTTMethod(rawValue: o.ptt) else { fail("--ptt: \(o.ptt)") }; settings.ptt.method = pm }
    if let p = o.port { settings.ptt.port = p; settings.fsk.port = p }
    switch o.fsk {
    case nil: break
    case "uart"?: settings.fsk.output = .fskUART
    case "soft-dtr"?: settings.fsk.output = .fskSoft; settings.fsk.line = .dtr
    case "soft-rts"?: settings.fsk.output = .fskSoft; settings.fsk.line = .rts
    case "soft-break"?: settings.fsk.output = .fskSoft; settings.fsk.line = .txdBreak
    default: fail("--fsk: \(o.fsk!)")
    }
    if o.fsk != nil && settings.fsk.port == nil { fail("--fsk potřebuje --port") }
    if o.rigSet { guard let t = RigType(rawValue: o.rig) else { fail("--rig: \(o.rig)") }; settings.rig.type = t }
    if o.noAPI { settings.api.fldigiEnabled = false; settings.api.jsonRPCEnabled = false }
    // command-line modem switches take precedence over the saved parameters (only those given)
    if o.modemFlags.contains("baud") { settings.rtty["baud"] = .double(o.baud) }
    if o.modemFlags.contains("mark") { settings.rtty["mark"] = .double(o.mark) }
    if o.modemFlags.contains("shift") { settings.rtty["shift"] = .double(o.shift) }
    if o.modemFlags.contains("demodType") { settings.rtty["demodType"] = .string(o.demod) }
    if o.modemFlags.contains("afc") { settings.rtty["afc"] = .bool(o.afc) }

    let m: RTTYModem
    do { m = try RTTYModem() } catch { fail("\(error)") }
    let rig: Rig = RigFactory.make(settings.rig)
    let engine = Engine(modem: m, rig: rig, audio: CoreAudioBackend(), config: settings.engineConfig())
    let log: QSOLogStore?
    do { log = try QSOLogStore(directory: URL(fileURLWithPath: settings.log.directory), baseName: settings.log.name) }
    catch { log = nil; FileHandle.standardError.write(Data("[log] nedostupný: \(error)\n".utf8)) }
    let app = AppController(settings: settings, engine: engine, log: log, profiles: ProfileStore(directory: store.url.deletingLastPathComponent()))
    let events = app.events()
    let printer = Task.detached {
        for await e in events {
            switch e {
            case .engine(.modem(.rxText(let c, _))):
                FileHandle.standardOutput.write(Data(String(c).utf8))
            case .engine(.state(let s)): FileHandle.standardError.write(Data("\n[\(s.rawValue)]\n".utf8))
            case .engine(.rig(let r)):
                FileHandle.standardError.write(Data("\n[rig \(r.online ? "online" : "offline") \(r.frequency.map { String(Int($0)) } ?? "")]\n".utf8))
            case .engine(.error(let err)): FileHandle.standardError.write(Data("\n[chyba \(err)]\n".utf8))
            case .engine(.pttTimeout): FileHandle.standardError.write(Data("\n[PTT timeout]\n".utf8))
            case .qsoLogged(let r): FileHandle.standardError.write(Data("\n[zalogováno \(r.call)]\n".utf8))
            case .error(let msg): FileHandle.standardError.write(Data("\n[chyba \(msg)]\n".utf8))
            default: break
            }
        }
    }
    do { try await app.start() } catch { fail("start: \(error)") }
    if !o.his.isEmpty { try? await app.setQSOField("call", o.his) }
    let bindHost = settings.api.allowRemote ? "0.0.0.0" : "127.0.0.1"
    var fldigiServer: FldigiXMLRPCServer?, jsonServer: JSONRPCServer?
    if settings.api.fldigiEnabled {
        let srv = FldigiXMLRPCServer(app: app, host: bindHost, port: UInt16(settings.api.fldigiPort))
        do { let p = try await srv.start(); fldigiServer = srv; FileHandle.standardError.write(Data("[api] fldigi XML-RPC http://\(bindHost):\(p)/RPC2\n".utf8)) }
        catch { FileHandle.standardError.write(Data("[api] fldigi XML-RPC nespuštěno: \(error)\n".utf8)) }
    }
    if settings.api.jsonRPCEnabled {
        let srv = JSONRPCServer(app: app, host: bindHost, port: UInt16(settings.api.jsonRPCPort))
        do { let p = try await srv.start(); jsonServer = srv; FileHandle.standardError.write(Data("[api] JSON-RPC ws://\(bindHost):\(p)/v1\n".utf8)) }
        catch { FileHandle.standardError.write(Data("[api] JSON-RPC nespuštěno: \(error)\n".utf8)) }
    }
    // Ctrl-C / SIGTERM: always switch off PTT and the FSK line safely
    installStopOnSignals(engine)
    FileHandle.standardError.write(Data("mmtty4mac live – text + Enter = vysílat, :q = konec\n".utf8))
    while let line = readLine() {
        if line.hasPrefix(":c ") { try? await app.setQSOField("call", String(line.dropFirst(3))); continue }
        if line == ":log" { do { _ = try await app.logQSO() } catch { print("log: \(error)") }; continue }
        if line.hasPrefix(":m"), let n = Int(line.dropFirst(2)) {
            do { try await app.runMacro(index: n - 1) } catch { print("makro: \(error)") }
            continue
        }
        switch line {
        case ":q": break
        case ":tx": do { try await app.tx() } catch { print("TX: \(error)") }; continue
        case ":tune": do { try await app.tune() } catch { print("TX: \(error)") }; continue
        case ":rx": await app.rx(); continue
        case ":abort": await app.rxNow(); continue
        default:
            await app.send(text: line + "\r\n")
            do { try await app.tx(); await app.rx() } catch { print("TX: \(error)") }
            continue
        }
        break
    }
    fldigiServer?.stop(); jsonServer?.stop()
    await app.stop()
    await printer.value

default:
    fail(usage)
}
