import Foundation

/// Minimalistické čtení a zápis WAV. Zápis PCM 16 bit mono; čtení PCM 16/24/32 bit, float 32 bit
/// i WAVE_FORMAT_EXTENSIBLE, bere 1. kanál.
public enum WaveFile {
    public enum Error: Swift.Error, Equatable, LocalizedError {
        case notWave, unsupportedFormat(String), truncated
        public var errorDescription: String? {
            switch self {
            case .notWave: return "Soubor není WAV."
            case .unsupportedFormat(let f): return "Nepodporovaný formát WAV (\(f)). Podporováno: PCM 16/24/32 bit nebo float 32 bit."
            case .truncated: return "Soubor WAV je neúplný."
            }
        }
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
        d.reserveCapacity(d.count + samples.count * 2)
        for s in samples {
            let c = s.isFinite ? max(-1.0, min(1.0, s)) : 0
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
        return try d.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            func u16(_ o: Int) -> Int { Int(raw[o]) | Int(raw[o + 1]) << 8 }
            func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
            var pos = 12
            var channels = 0, rate = 0, bits = 0, format = 0
            while pos + 8 <= raw.count {
                let id = String(decoding: raw[pos..<pos + 4], as: UTF8.self)
                let size = u32(pos + 4)
                let body = pos + 8
                if id == "fmt " {
                    guard body + 16 <= raw.count else { throw Error.truncated }
                    format = u16(body); channels = u16(body + 2); rate = u32(body + 4); bits = u16(body + 14)
                    // WAVE_FORMAT_EXTENSIBLE: skutečný formát je v prvních 2 bajtech SubFormat GUID
                    if format == 0xFFFE, size >= 40, body + 26 <= raw.count { format = u16(body + 24) }
                } else if id == "data" {
                    let ok = (format == 1 && [16, 24, 32].contains(bits)) || (format == 3 && bits == 32)
                    guard ok, channels >= 1 else {
                        throw Error.unsupportedFormat("format \(format), \(bits) bit, \(channels) kan.")
                    }
                    let end = min(body + size, raw.count)
                    let bps = bits / 8, frame = bps * channels
                    var out = [Float](); out.reserveCapacity((end - body) / frame)
                    var p = body
                    while p + bps <= end {
                        switch (format, bits) {
                        case (1, 16): out.append(Float(Int16(bitPattern: UInt16(u16(p)))) / 32768)
                        case (1, 24):
                            let v = Int32(bitPattern: UInt32(raw[p]) << 8 | UInt32(raw[p + 1]) << 16 | UInt32(raw[p + 2]) << 24) >> 8
                            out.append(Float(v) / 8_388_608)
                        case (1, 32): out.append(Float(Int32(bitPattern: UInt32(u32(p)))) / 2_147_483_648)
                        default:
                            let f = Float(bitPattern: UInt32(u32(p)))
                            out.append(f.isFinite ? f : 0)
                        }
                        p += frame
                    }
                    return (out, rate)
                }
                pos = body + size + (size & 1)
            }
            throw Error.truncated
        }
    }
}
