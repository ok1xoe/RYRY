// Copyright 2026 OK1XOE (RYRY), LGPL v3
// Settings written by the DMG version must load in the App Store edition (RYRY).
import Foundation
import Testing
@testable import Settings

func loadSettingsJSON(_ json: String) throws -> (AppSettings, [String]) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mig-\(UUID())")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try json.write(to: dir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
    let r = SettingsStore(directory: dir).load()
    return (r.0, r.warnings)
}

@Test func managedHamlibBecomesTCPRigctldWithAWarning() throws {
    let (s, w) = try loadSettingsJSON(#"{"rig":{"type":"hamlibManaged","serialPort":"/dev/cu.usb1","hamlibModel":3073}}"#)
    #expect(s.rig.type == .hamlib && s.rig.effectivePort == 4532 && s.rig.host == "127.0.0.1")
    #expect(w.contains { $0.contains("rigctld") })
}

@Test func oldLoTWKeysAreIgnored() throws {
    let (s, w) = try loadSettingsJSON(#"{"upload":{"lotwEnabled":true,"lotwTqslPath":"/x/tqsl","lotwAuto":true,"lotwLocation":"Home"}}"#)
    #expect(s.upload.lotwEnabled && w.isEmpty)
}

@Test func oldUpdateSettingsAreIgnored() throws {
    let (s, w) = try loadSettingsJSON(#"{"updates":{"autoCheck":false},"station":{"call":"OK1XOE"}}"#)
    #expect(s.station.call == "OK1XOE" && w.isEmpty)
    #expect(!String(decoding: try JSONEncoder().encode(s), as: UTF8.self).contains("\"updates\""))   // not written back
}
