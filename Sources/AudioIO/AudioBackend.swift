// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3

public enum AudioChannel: String, Sendable, Codable, CaseIterable { case left, right, mono }

public struct AudioConfig: Sendable, Equatable, Codable {
    public var inputUID: String?
    public var outputUID: String?
    public var inputChannel: AudioChannel = .left
    public var outputChannel: AudioChannel = .mono
    public var outputGain: Float = 1.0
    public init() {}
}

/// Zvukový backend: RX i TX vzorky na frekvenci modemu (převod řeší backend).
/// `readRx`/`writeTx`/`clearTx` volá jedno (DSP) vlákno.
public protocol AudioBackend: AnyObject, Sendable {
    func start(modemRate: Double, config: AudioConfig) throws
    func stop()
    func readRx(into: inout [Float]) -> Int
    func writeTx(_ samples: [Float]) -> Int
    func clearTx()
    var txQueued: Int { get }          // vzorky (na frekvenci modemu) čekající na výstup
    var isRunning: Bool { get }
    /// Nenulové, když zařízení selhalo (odpojeno, změna konfigurace) – Engine přeruší TX.
    var failure: String? { get }
}
