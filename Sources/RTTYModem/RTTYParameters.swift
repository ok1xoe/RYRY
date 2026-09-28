import MMTTYCore
import ModemKit

/// Popis a převod RTTY parametrů mezi ModemKit (ID + ParameterValue) a C API jádra.
enum RTTYParameters {
    enum Map {
        case double(RTTYCoreParam)
        case int(RTTYCoreParam)
        case bool(RTTYCoreParam)
        case choice(RTTYCoreParam, [String], [Double])   // názvy ↔ hodnoty jádra
        case shift                                        // space − mark
        case mark                                         // mark se zachováním shiftu
    }

    static let table: [(ParameterDescriptor, Map)] = [
        (.init(id: "baud", label: "Baud", kind: .double(20...300, unit: "Bd"), defaultValue: .double(45.45)), .double(RC_BAUD)),
        (.init(id: "mark", label: "Mark", kind: .double(100...3000, unit: "Hz"), defaultValue: .double(2125)), .mark),
        (.init(id: "shift", label: "Shift", kind: .double(20...2000, unit: "Hz"), defaultValue: .double(170)), .shift),
        (.init(id: "reverse", label: "Reverse", kind: .bool, defaultValue: .bool(false)), .bool(RC_REVERSE)),
        (.init(id: "afc", label: "AFC", kind: .bool, defaultValue: .bool(true)), .bool(RC_AFC)),
        (.init(id: "afcMode", label: "AFC mode", kind: .choice(["free", "fixed", "ham", "fsk"]), defaultValue: .string("fixed")),
         .choice(RC_AFC_MODE, ["free", "fixed", "ham", "fsk"], [0, 1, 2, 3])),
        (.init(id: "afcSquelch", label: "AFC squelch", kind: .double(0...1024, unit: nil), defaultValue: .double(32)), .double(RC_AFC_SQ)),
        (.init(id: "afcTime", label: "AFC time constant", kind: .double(1...64, unit: nil), defaultValue: .double(8)), .double(RC_AFC_TIME)),
        (.init(id: "afcSweep", label: "AFC sweep", kind: .double(0.1...3.0, unit: nil), defaultValue: .double(1)), .double(RC_AFC_SWEEP)),
        (.init(id: "net", label: "NET (TX follows RX)", kind: .bool, defaultValue: .bool(true)), .bool(RC_NET)),
        (.init(id: "atc", label: "ATC", kind: .bool, defaultValue: .bool(false)), .bool(RC_ATC)),
        (.init(id: "squelch", label: "Squelch", kind: .bool, defaultValue: .bool(false)), .bool(RC_SQUELCH)),
        (.init(id: "squelchLevel", label: "Squelch level", kind: .double(0...32768, unit: nil), defaultValue: .double(600)), .double(RC_SQUELCH_LEVEL)),
        (.init(id: "demodType", label: "Demodulator", kind: .choice(["iir", "fir", "pll", "fft"]), defaultValue: .string("iir")),
         .choice(RC_DEMOD_TYPE, ["iir", "fir", "pll", "fft"], [0, 1, 2, 3])),
        (.init(id: "iirBandwidth", label: "IIR bandwidth", kind: .double(20...500, unit: "Hz"), defaultValue: .double(60)), .double(RC_IIR_BW)),
        (.init(id: "firTaps", label: "FIR taps", kind: .int(8...512), defaultValue: .int(72)), .int(RC_FIR_TAP)),
        (.init(id: "integrator", label: "Integrator", kind: .choice(["average", "lpf"]), defaultValue: .string("average")),
         .choice(RC_SMOOTH_TYPE, ["average", "lpf"], [0, 1])),
        (.init(id: "smoothFreq", label: "Smoothing", kind: .double(10...1000, unit: "Hz"), defaultValue: .double(70)), .double(RC_SMOOTH_FREQ)),
        (.init(id: "lpfFreq", label: "LPF cutoff", kind: .double(10...1000, unit: "Hz"), defaultValue: .double(40)), .double(RC_LPF_FREQ)),
        (.init(id: "lpfOrder", label: "LPF order", kind: .int(1...8), defaultValue: .int(5)), .int(RC_LPF_ORDER)),
        (.init(id: "majority", label: "Majority logic", kind: .bool, defaultValue: .bool(true)), .bool(RC_MAJORITY)),
        (.init(id: "ignoreFraming", label: "Ignore framing errors", kind: .bool, defaultValue: .bool(false)), .bool(RC_IGNORE_FRAMING)),
        (.init(id: "bitLength", label: "Bit length", kind: .int(5...8), defaultValue: .int(5)), .int(RC_BIT_LENGTH)),
        (.init(id: "stopBits", label: "Stop bits", kind: .choice(["1", "1.5", "2", "1.42"]), defaultValue: .string("1.42")),
         .choice(RC_STOP_BITS, ["1", "1.5", "2", "1.42"], [0, 1, 2, 4])),
        (.init(id: "parity", label: "Parity", kind: .choice(["none", "even", "odd", "mark", "space"]), defaultValue: .string("none")),
         .choice(RC_PARITY, ["none", "even", "odd", "mark", "space"], [0, 1, 2, 3, 4])),
        (.init(id: "limiterAGC", label: "Limiter AGC", kind: .bool, defaultValue: .bool(true)), .bool(RC_LIMITER_AGC)),
        (.init(id: "limiterOversampling", label: "Limiter oversampling", kind: .bool, defaultValue: .bool(false)), .bool(RC_LIMITER_OVERSAMPLE)),
        (.init(id: "uos", label: "Unshift on space", kind: .bool, defaultValue: .bool(false)), .bool(RC_UOS)),
        (.init(id: "diddle", label: "Diddle", kind: .choice(["off", "blk", "ltr"]), defaultValue: .string("ltr")),
         .choice(RC_DIDDLE, ["off", "blk", "ltr"], [0, 1, 2])),
        (.init(id: "echo", label: "TX echo", kind: .int(0...2), defaultValue: .int(1)), .int(RC_ECHO)),
        (.init(id: "bpf", label: "RX BPF", kind: .bool, defaultValue: .bool(false)), .bool(RC_RX_BPF)),
        (.init(id: "bpfWidth", label: "RX BPF margin", kind: .double(20...500, unit: "Hz"), defaultValue: .double(100)), .double(RC_RX_BPF_WIDTH)),
        (.init(id: "lms", label: "RX LMS/notch", kind: .bool, defaultValue: .bool(false)), .bool(RC_RX_LMS)),
        (.init(id: "txGain", label: "TX output gain", kind: .double(0...32768, unit: nil), defaultValue: .double(24576)), .double(RC_TX_OUTPUT_GAIN)),
    ]

    static let descriptors: [ParameterDescriptor] = table.map(\.0)

    static func entry(_ id: String) -> (ParameterDescriptor, Map)? {
        table.first { $0.0.id == id }
    }

    /// Zapíše již zvalidovanou hodnotu do jádra.
    static func apply(id: String, value v: ParameterValue, core: OpaquePointer) throws(ParameterError) {
        guard let (_, map) = entry(id) else { throw .unknown(id) }
        func set(_ p: RTTYCoreParam, _ d: Double) throws(ParameterError) {
            if rttycore_set_param(core, p, d) != RC_OK { throw .outOfRange(id) }
        }
        switch (map, v) {
        case (.double(let p), .double(let d)): try set(p, d)
        case (.int(let p), .int(let i)): try set(p, Double(i))
        case (.bool(let p), .bool(let b)): try set(p, b ? 1 : 0)
        case (.choice(let p, let names, let vals), .string(let s)):
            guard let i = names.firstIndex(of: s) else { throw .outOfRange(id) }
            try set(p, vals[i])
        case (.shift, .double(let d)):
            try set(RC_SPACE, rttycore_get_param(core, RC_MARK) + d)
        case (.mark, .double(let d)):
            let shift = rttycore_get_param(core, RC_SPACE) - rttycore_get_param(core, RC_MARK)
            // pořadí tak, aby mezistav nebyl mimo povolený shift
            if d < rttycore_get_param(core, RC_MARK) {
                try set(RC_MARK, d); try set(RC_SPACE, d + shift)
            } else {
                try set(RC_SPACE, d + shift); try set(RC_MARK, d)
            }
        default:
            throw .typeMismatch(id)
        }
    }

    static func read(id: String, core: OpaquePointer) -> ParameterValue? {
        guard let (_, map) = entry(id) else { return nil }
        switch map {
        case .double(let p): return .double(rttycore_get_param(core, p))
        case .int(let p): return .int(Int(rttycore_get_param(core, p)))
        case .bool(let p): return .bool(rttycore_get_param(core, p) != 0)
        case .choice(let p, let names, let vals):
            let d = rttycore_get_param(core, p)
            guard let i = vals.firstIndex(of: d) else { return nil }
            return .string(names[i])
        case .shift: return .double(rttycore_get_param(core, RC_SPACE) - rttycore_get_param(core, RC_MARK))
        case .mark: return .double(rttycore_get_param(core, RC_MARK))
        }
    }
}
