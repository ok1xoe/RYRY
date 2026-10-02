// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Foundation
import RigControl

public enum PTTMethod: String, Sendable, Equatable, Codable, CaseIterable { case none, cat, rts, dtr, rtsDtr }

public enum PTTError: Error, Equatable, Sendable {
    case unavailable(String)
    case failed(String)
}

/// PTT control by a single method. Calls are serialized by the Engine.
public final class PTTController: @unchecked Sendable {
    public let method: PTTMethod
    private let port: SerialPort?
    private let rig: Rig?
    private let invert: Bool
    public private(set) var isOn = false

    public init(method: PTTMethod, port: SerialPort?, rig: Rig?, invert: Bool = false) {
        self.method = method; self.port = port; self.rig = rig; self.invert = invert
    }

    /// Verifies availability and sets the idle state (PTT off).
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

    /// Switches PTT off by every available path; never throws.
    public func forceOff() async {
        isOn = false
        if let port {
            try? port.setRTS(invert)
            try? port.setDTR(invert)
        }
        // Always switch CAT off when there is a rig (even with RTS/DTR PTT – the rig may have been keyed elsewhere).
        // Waits at most 2 s and does not wait for a task that ignores cancellation.
        // PTT via RTS/DTR: CAT just in case and only on an open rig (do not open a port / start rigctld for it),
        // without waiting. A late command after rig disconnect opens nothing (rig reports offline after disconnect()).
        guard let rig else { return }
        if method != .cat {
            if !rig.isIdle { Task { try? await rig.setPTT(false) } }
            return
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let once = Once()
            Task { try? await rig.setPTT(false); if once.first() { cont.resume() } }
            Task { try? await Task.sleep(for: .seconds(2)); if once.first() { cont.resume() } }
        }
    }
}

final class Once: @unchecked Sendable {
    private let lock = NSLock(); private var done = false
    func first() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
}
