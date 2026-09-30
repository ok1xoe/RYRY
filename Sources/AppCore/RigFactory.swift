// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import RigControl
import Settings

/// Radio control according to the settings (the app as well as rtty-tool).
public enum RigFactory {
    public static func make(_ r: RigSettings) -> Rig {
        switch r.type {
        case .hamlib: return HamlibClient(host: r.host, port: UInt16(clamping: r.effectivePort))
        case .flrig: return FlrigClient(host: r.host, port: r.effectivePort)
        case .cat:
            guard !r.serialPort.isEmpty else { return NoRig() }
            let t = SerialCATTransport(path: r.serialPort, baud: r.baud, stopBits: r.stopBits, rts: r.effectiveCatRTS)
            let p: CATProtocol
            switch r.catProtocol {
            case .icom: p = .icom(address: UInt8(clamping: r.civAddress))
            case .yaesu: p = .text(.yaesu)
            case .kenwood: p = .text(.kenwood)
            case .elecraft: p = .text(.elecraft)
            }
            return SerialCATRig(transport: t, protocol: p, name: "CAT \(r.catProtocol.rawValue) \(r.serialPort)")
        case .none: return NoRig()
        }
    }
}
