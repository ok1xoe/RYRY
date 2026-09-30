// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation

public indirect enum XMLRPCValue: Sendable, Equatable {
    case int(Int), bool(Bool), string(String), double(Double), base64(Data)
    case array([XMLRPCValue]), dict([String: XMLRPCValue]), nil_
}

public struct XMLRPCFault: Error, Equatable, Sendable {
    public let code: Int
    public let message: String
    public init(code: Int, message: String) { self.code = code; self.message = message }
}

public enum XMLRPCCodecError: Error, Equatable, Sendable {
    case malformed(String)
}

public extension XMLRPCValue {
    /// Convenience conversions (fldigi/flrig often send numbers as strings).
    var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return b ? "1" : "0"
        default: return nil
        }
    }
    var doubleValue: Double? {
        switch self {
        case .double(let d): return d
        case .int(let i): return Double(i)
        case .string(let s): return Double(s.trimmingCharacters(in: .whitespaces))
        case .bool(let b): return b ? 1 : 0
        default: return nil
        }
    }
    var intValue: Int? {
        switch self {
        case .int(let i): return i
        case .bool(let b): return b ? 1 : 0
        case .double(let d): return Int(exactly: d.rounded(.towardZero))
        case .string(let s): return Int(s.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }
    var boolValue: Bool? {
        switch self {
        case .bool(let b): return b
        case .int(let i): return i != 0
        case .string(let s): return ["1", "true"].contains(s.lowercased()) ? true : (["0", "false"].contains(s.lowercased()) ? false : nil)
        default: return nil
        }
    }
}
