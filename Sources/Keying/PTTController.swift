// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import RigControl

public enum PTTMethod: String, Sendable, Equatable, Codable, CaseIterable { case none, cat, rts, dtr, rtsDtr }

public enum PTTError: Error, Equatable, Sendable {
    case unavailable(String)
    case failed(String)
}

/// Ovládání PTT jednou metodou. Volání serializuje Engine.
public final class PTTController: @unchecked Sendable {
    public let method: PTTMethod
    private let port: SerialPort?
    private let rig: Rig?
    private let invert: Bool
    public private(set) var isOn = false

    public init(method: PTTMethod, port: SerialPort?, rig: Rig?, invert: Bool = false) {
        self.method = method; self.port = port; self.rig = rig; self.invert = invert
    }

    /// Ověří dostupnost a nastaví klidový stav (PTT vypnuté).
    public func prepare() async throws {
        switch method {
        case .none: return
        case .cat:
            guard let rig else { throw PTTError.unavailable("CAT PTT bez rigu") }
            do { try await rig.connect() } catch { throw PTTError.unavailable("rig: \(error)") }
        case .rts, .dtr, .rtsDtr:
            guard let port else { throw PTTError.unavailable("PTT bez sériového portu") }
            do { try port.open(); try lines(false) } catch { throw PTTError.unavailable("\(port.path): \(error)") }
        }
    }

    private func lines(_ on: Bool) throws {
        guard let port else { return }
        let level = on != invert
        if method == .rts || method == .rtsDtr { try port.setRTS(level) }
        if method == .dtr || method == .rtsDtr { try port.setDTR(level) }
    }

    public func set(_ on: Bool) async throws {
        do {
            switch method {
            case .none: break
            case .cat: try await rig?.setPTT(on)
            default: try lines(on)
            }
            isOn = on
        } catch {
            throw PTTError.failed("\(error)")
        }
    }

    /// Vypne PTT všemi dostupnými cestami; nikdy nehází.
    public func forceOff() async {
        isOn = false
        if let port {
            try? port.setRTS(invert)
            try? port.setDTR(invert)
        }
        if method == .cat, let rig {
            _ = try? await withThrowingTaskGroup(of: Void.self) { g in
                g.addTask { try await rig.setPTT(false) }
                g.addTask { try await Task.sleep(for: .seconds(2)); throw RigError.timeout }
                try await g.next(); g.cancelAll()
            }
        }
    }
}
