// Copyright 2026 OK1XOE (RYRY), LGPL v3

public enum AudioChannel: String, Sendable, Codable, CaseIterable { case left, right, mono }

public struct AudioConfig: Sendable, Equatable, Codable {
    public var inputUID: String?
    public var outputUID: String?
    public var inputChannel: AudioChannel = .left
    public var outputChannel: AudioChannel = .mono
    public var outputGain: Float = 1.0
    public init() {}
}

/// Audio backend: both RX and TX samples at the modem rate (the backend handles the conversion).
/// `readRx`/`writeTx`/`clearTx` are called from a single (DSP) thread.
public protocol AudioBackend: AnyObject, Sendable {
    func start(modemRate: Double, config: AudioConfig) throws
    func stop()
    func readRx(into: inout [Float]) -> Int
    func writeTx(_ samples: [Float]) -> Int
    func clearTx()
    var txQueued: Int { get }          // samples (at the modem rate) waiting for output
    var isRunning: Bool { get }
    /// Non-nil when the device has failed (disconnected, configuration change) – the Engine aborts TX.
    var failure: String? { get }
}
