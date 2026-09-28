// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AudioIO
import Keying
import ModemKit
import RigControl

public enum TxOutput: Sendable, Equatable, Codable {
    case afsk
    case fskUART(path: String)
    case fskSoft(path: String, line: FSKLine)
}

public struct EngineConfig: Sendable, Equatable {
    public var audio = AudioConfig()
    public var ptt: PTTMethod = .none
    public var pttPort: String? = nil
    public var pttInvert = false
    public var txOutput: TxOutput = .afsk
    public var fskInvert = false
    public var audioDuringFSK = false
    public var txDelay: Duration = .milliseconds(0)      // PTT → modulace
    public var pttTail: Duration = .milliseconds(200)    // konec modulace → PTT off
    public var pttTimeout: Duration = .seconds(600)
    public var rigPollInterval: Duration = .seconds(1)
    public init() {}
}

/// keying = PTT se právě zapíná; pttOff = PTT se vypíná (doběh nebo přerušení).
public enum EngineState: String, Sendable { case stopped, rx, keying, pttOn, tx, drain, pttOff }

public enum EngineError: Error, Equatable, Sendable {
    case pttUnavailable(String), audio(String), keying(String), rig(String), notRunning
}

public enum EngineEvent: Sendable {
    case state(EngineState)
    case modem(ModemEvent)
    case rig(RigStatus)
    case error(EngineError)
    case pttTimeout
}

/// Rozesílá události více odběratelům (každý dostane vlastní AsyncStream).
final class EventBroadcaster: @unchecked Sendable {
    private let lock = NSLock()
    private var subs: [UUID: AsyncStream<EngineEvent>.Continuation] = [:]
    private var finished = false

    func subscribe() -> AsyncStream<EngineEvent> {
        let (s, c) = AsyncStream.makeStream(of: EngineEvent.self, bufferingPolicy: .unbounded)
        let id = UUID()
        lock.withLock {
            if finished { c.finish() } else { subs[id] = c }
        }
        c.onTermination = { [weak self] _ in self?.lock.withLock { _ = self?.subs.removeValue(forKey: id) } }
        return s
    }

    func send(_ e: EngineEvent) {
        let cs = lock.withLock { Array(subs.values) }
        for c in cs { c.yield(e) }
    }

    func finish() {
        let cs = lock.withLock { () -> [AsyncStream<EngineEvent>.Continuation] in
            finished = true; let v = Array(subs.values); subs.removeAll(); return v
        }
        for c in cs { c.finish() }
    }
}

import Foundation
