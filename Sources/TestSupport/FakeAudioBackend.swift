// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AudioIO
import Foundation

/// Audio without hardware: RX from an array of samples, TX is stored.
public final class FakeAudioBackend: AudioBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var rx: [Float] = []
    private var rxPos = 0
    public private(set) var tx: [Float] = []
    public private(set) var writeCalls = 0
    public var rxChunk = 1103            // samples per readRx call (≈ 100 ms)
    public var failStart = false
    public private(set) var isRunning = false
    public var stuckQueued = 0            // >0 = the output is stuck (the device disappeared)
    public var txQueued: Int { stuckQueued }   // otherwise the output "consumes" samples immediately
    public var failure: String?

    public init() {}

    public func feedRx(_ s: [Float]) { lock.withLock { rx += s } }

    public func start(modemRate: Double, config: AudioConfig) throws {
        if failStart { throw AudioError.device("fake") }
        isRunning = true
    }
    public func stop() { isRunning = false }

    public func readRx(into a: inout [Float]) -> Int {
        lock.withLock {
            let n = min(a.count, rxChunk, rx.count - rxPos)
            for i in 0..<max(0, n) { a[i] = rx[rxPos + i] }
            rxPos += max(0, n)
            return max(0, n)
        }
    }

    public func writeTx(_ samples: [Float]) -> Int {
        lock.withLock { tx += samples; writeCalls += 1 }
        return samples.count
    }
    public func clearTx() {}
    public var rxRemaining: Int { lock.withLock { rx.count - rxPos } }
}
