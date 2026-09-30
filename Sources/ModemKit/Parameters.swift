/// Kind of a modem parameter – a description for validation, the GUI and the API.
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

    /// Validates the value and returns it in the canonical type (e.g. .int → .double for a double parameter).
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
