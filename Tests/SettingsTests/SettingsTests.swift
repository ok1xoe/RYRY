import Foundation
import Testing
import AudioIO
import Engine
import Keying
import ModemKit
@testable import Settings

func tmp() -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("settings-\(UUID())")
    try! FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

@Test func defaults() {
    let s = AppSettings()
    #expect(s.schemaVersion == 1)
    #expect(s.api.fldigiPort == 7362 && s.api.jsonRPCPort == 7363 && !s.api.allowRemote)
    #expect(s.api.fldigiEnabled && s.api.jsonRPCEnabled)
    #expect(s.ptt.method == .none && s.ptt.pttTailMs == 200)
    #expect(s.macros.count == 12)
    #expect(s.rig.type == .none)
}

@Test func roundTrip() throws {
    let store = SettingsStore(directory: tmp())
    var s = AppSettings()
    s.station.call = "OK1XOE"; s.ptt.method = .rts; s.ptt.port = "/dev/cu.usb"
    s.rtty["baud"] = .double(50); s.fsk.output = .fskSoft; s.fsk.line = .rts
    s.macros[0].text = "CQ TEST %m\\"
    try store.save(s)
    let (loaded, warnings) = store.load()
    #expect(loaded == s)
    #expect(warnings.isEmpty)
}

@Test func missingFileGivesDefaultsWithoutWarning() {
    let (s, w) = SettingsStore(directory: tmp()).load()
    #expect(s == AppSettings() && w.isEmpty)
}

// Review Focus 4
@Test func toleratesMissingUnknownAndInvalidValues() throws {
    let dir = tmp()
    let json = """
    {"schemaVersion": 1, "station": {"call": "OK1XOE", "futureKey": 5},
     "api": {"fldigiPort": "abc", "allowRemote": true},
     "ptt": {"method": "laser"},
     "unknownSection": {"x": 1}}
    """
    try Data(json.utf8).write(to: dir.appendingPathComponent("settings.json"))
    let (s, w) = SettingsStore(directory: dir).load()
    #expect(s.station.call == "OK1XOE")
    #expect(s.api.fldigiPort == 7362)          // neplatné → výchozí
    #expect(s.api.allowRemote == true)          // platné se zachová
    #expect(s.ptt.method == .none)
    #expect(s.macros.count == 12)               // chybějící sekce → výchozí
    #expect(w.count >= 2)
}

@Test func unreadableFileKeepsDefaultsAndIsNotOverwritten() throws {
    let dir = tmp()
    let url = dir.appendingPathComponent("settings.json")
    try Data("{{ garbage".utf8).write(to: url)
    let (s, w) = SettingsStore(directory: dir).load()
    #expect(s == AppSettings())
    #expect(!w.isEmpty)
    #expect(try String(contentsOf: url, encoding: .utf8) == "{{ garbage")
}

@Test func engineConfigConversion() {
    var s = AppSettings()
    s.ptt.method = .rtsDtr; s.ptt.port = "/dev/cu.x"; s.ptt.txDelayMs = 50; s.ptt.pttTailMs = 300
    s.fsk.output = .fskUART; s.fsk.port = "/dev/cu.y"
    s.audio.inputUID = "IN"
    let c = s.engineConfig()
    #expect(c.ptt == .rtsDtr && c.pttPort == "/dev/cu.x")
    #expect(c.txDelay == .milliseconds(50) && c.pttTail == .milliseconds(300))
    #expect(c.txOutput == .fskUART(path: "/dev/cu.y"))
    #expect(c.audio.inputUID == "IN")
    s.fsk.output = .fskSoft; s.fsk.line = .txdBreak
    #expect(s.engineConfig().txOutput == .fskSoft(path: "/dev/cu.y", line: .txdBreak))
    s.fsk.port = nil
    #expect(s.engineConfig().txOutput == .afsk)          // FSK bez portu → AFSK
}

@Test func profilesHave16Slots() throws {
    let store = ProfileStore(directory: tmp())
    #expect(store.load().count == 16)
    #expect(store.load().allSatisfy { $0 == nil })
    let p = Profile(name: "Contest 45", rtty: ["baud": .double(45.45), "afc": .bool(false)])
    try store.save(p, slot: 3)
    let all = store.load()
    #expect(all[3] == p && all[0] == nil)
    try store.save(nil, slot: 3)
    #expect(store.load()[3] == nil)
    #expect(throws: SettingsError.self) { try store.save(p, slot: 16) }
    #expect(throws: SettingsError.self) { try store.save(p, slot: -1) }
}

// Review I6: jedno vadné makro / parametr nesmí zahodit ostatní
@Test func badMacroOrParamKeepsTheRest() throws {
    let dir = tmp()
    let json = """
    {"macros": [{"name": "CQ", "text": "CQ DE %m\\\\"}, {"name": 5}, {"name": "73", "text": "73"}],
     "rtty": {"baud": {"double": {"_0": 50}}, "afc": "nonsense"}}
    """
    try Data(json.utf8).write(to: dir.appendingPathComponent("settings.json"))
    let (s, w) = SettingsStore(directory: dir).load()
    #expect(s.macros.map(\.name) == ["CQ", "", "73"])
    #expect(s.macros[0].text == "CQ DE %m\\")
    #expect(s.rtty["baud"] == .double(50))
    #expect(s.rtty["afc"] == nil)
    #expect(w.count >= 2)
}

// Review I6: nečitelný profiles.json se nesmí tiše přepsat
@Test func unreadableProfilesAreNotOverwritten() throws {
    let dir = tmp()
    let url = dir.appendingPathComponent("profiles.json")
    try Data("{broken".utf8).write(to: url)
    let store = ProfileStore(directory: dir)
    #expect(throws: SettingsError.self) { try store.save(Profile(name: "x", rtty: [:]), slot: 0) }
    #expect(try String(contentsOf: url, encoding: .utf8) == "{broken")
}
