import Foundation
import Spots
import Testing
@testable import Settings

@Test func spotSettingsDefaultsAreOff() {
    let s = AppSettings().spots
    #expect(!s.clusterEnabled && !s.rbnEnabled)          // síť jen na výslovné zapnutí
    #expect(s.maxAgeMinutes == 30 && s.offsetHz == 0)
    #expect(s.filterBands == SpotFilter.allBandsSet && s.filterModes == [.rtty])   // všechna pásma, jen RTTY
    #expect(s.clusterPort == 23 && s.rbnPort == 7000 && s.rbnHost == "telnet.reversebeacon.net")
}

@Test func spotSettingsRoundTripAndTolerance() throws {
    let dir = tmp()
    var s = AppSettings()
    s.spots.clusterEnabled = true; s.spots.clusterHost = "dxfun.com"; s.spots.clusterPort = 8000
    s.spots.clusterCommands = ["set/skimmer", "sh/dx 30"]; s.spots.rbnEnabled = true
    s.spots.filterBands = ["20m", "40m"]; s.spots.filterModes = [.rtty, .cw, .other]
    s.spots.maxAgeMinutes = 60; s.spots.offsetHz = 2125
    try SettingsStore(directory: dir).save(s)
    #expect(SettingsStore(directory: dir).load().0 == s)

    try #"{"spots":{"clusterPort":99999,"clusterHost":"bad host","rbnPort":"x","maxAgeMinutes":0,"offsetHz":1e9,"clusterCommands":["  sh/dx  ","",5],"rttyOnly":false}}"#
        .write(to: dir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
    let o = SettingsStore(directory: dir).load().0.spots
    #expect(o.clusterPort == 23 && o.clusterHost == "dxc.ve7cc.net" && o.rbnPort == 7000)
    #expect(o.maxAgeMinutes == 30 && o.offsetHz == 0)
    #expect(o.clusterCommands == ["sh/dx"])
    #expect(o.filterModes == SpotFilter.allModes)                                 // migrace rttyOnly: false
}

@Test func spotShowInWaterfallDefaultsTrueAndIsTolerant() throws {
    #expect(AppSettings().spots.showInWaterfall)
    let dir = tmp()
    try #"{"spots":{"rttyOnly":false}}"#.write(to: dir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
    #expect(SettingsStore(directory: dir).load().0.spots.showInWaterfall)            // chybějící klíč = výchozí
    try #"{"spots":{"showInWaterfall":"ne"}}"#.write(to: dir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
    #expect(SettingsStore(directory: dir).load().0.spots.showInWaterfall)            // neplatná hodnota = výchozí
    try #"{"spots":{"showInWaterfall":false}}"#.write(to: dir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
    #expect(!SettingsStore(directory: dir).load().0.spots.showInWaterfall)
}

// Migrace zrušeného „rttyOnly“ na filtr módů: true = jen RTTY, false = všechny módy, chybějící = výchozí.
@Test func spotFilterMigratesFromRTTYOnly() throws {
    let dir = tmp()
    func load(_ json: String) throws -> SpotSettings {
        try json.write(to: dir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
        return SettingsStore(directory: dir).load().0.spots
    }
    #expect(try load(#"{"spots":{"rttyOnly":true}}"#).filterModes == [.rtty])
    #expect(try load(#"{"spots":{"rttyOnly":false}}"#).filterModes == SpotFilter.allModes)
    #expect(try load(#"{"spots":{}}"#).filterModes == [.rtty])                      // bez klíče = výchozí
    #expect(try load(#"{"spots":{"rttyOnly":true}}"#).filterBands == SpotFilter.allBandsSet)
    // nový klíč má přednost před starým
    #expect(try load(#"{"spots":{"rttyOnly":true,"filterModes":["CW"]}}"#).filterModes == [.cw])
    #expect(try load(#"{"spots":{"rttyOnly":"ano"}}"#).filterModes == [.rtty])       // neplatná hodnota = jen RTTY
}

// Filtr pásem a módů: tolerantní dekódování a kolo uložení/načtení.
@Test func spotFilterSettingsAreTolerant() throws {
    let dir = tmp()
    func load(_ json: String) throws -> SpotSettings {
        try json.write(to: dir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
        return SettingsStore(directory: dir).load().0.spots
    }
    #expect(try load(#"{"spots":{"filterBands":["20m","40m"]}}"#).filterBands == ["20m", "40m"])
    #expect(try load(#"{"spots":{"filterBands":[]}}"#).filterBands.isEmpty)          // „Nic“ je platný stav
    #expect(try load(#"{"spots":{"filterModes":[]}}"#).filterModes.isEmpty)
    #expect(try load(#"{"spots":{"filterBands":["20m","2m","xx",7]}}"#).filterBands == ["20m"])   // mimo seznam pryč
    #expect(try load(#"{"spots":{"filterBands":"20m"}}"#).filterBands == SpotFilter.allBandsSet)  // neplatná = výchozí
    #expect(try load(#"{"spots":{"filterModes":"CW"}}"#).filterModes == [.rtty])
    #expect(try load(#"{"spots":{"filterModes":["CW","NIC","OTHER"]}}"#).filterModes == [.cw, .other])

    var s = AppSettings()
    s.spots.filterBands = ["160m", "6m"]; s.spots.filterModes = [.digi, .ssb, .psk]
    try SettingsStore(directory: dir).save(s)
    let back = SettingsStore(directory: dir).load().0.spots
    #expect(back.filterBands == ["160m", "6m"] && back.filterModes == [.digi, .ssb, .psk])
    #expect(back.filter == SpotFilter(bands: ["160m", "6m"], modes: [.digi, .ssb, .psk]))
}
