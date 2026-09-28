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
        case "--seed": o.seed = UInt64(max(0, num(a)))
        case "--demod":
            guard let v = it.next() else { fail("--demod očekává iir|fir|pll|fft") }
            o.demod = v
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

func writeWav(_ s: [Float], _ path: String) {
    do { try WaveFile.write(samples: s, sampleRate: 11025, to: URL(fileURLWithPath: path)) }
    catch { fail("zápis \(path) selhal: \(error)") }
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
    let reader = Task {
        var text = ""
        for await e in events { if case .rxText(let c, false) = e { text.append(c) } }
        return text
    }
    samples.withUnsafeBufferPointer { m.processRx($0) }
    m.finishEvents()
    print(await reader.value)

default:
    fail(usage)
}
