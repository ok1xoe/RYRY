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

// Zaškrtávátko „ostatní“ u pásem (spoty mimo pevný seznam): výchozí zaškrtnuté, i ve starém settings.json;
// tlačítka Vše / Nic ho přepínají spolu s pevným seznamem, takže po „Nic“ neprojde ani jeden spot.
@Test func otherBandsFilterDefaultsOnAndIsTolerant() throws {
    #expect(SpotSettings().filterOtherBands && SpotSettings().filter.otherBands)
    let dir = tmp()
    func load(_ json: String) throws -> SpotSettings {
        try json.write(to: dir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
        return SettingsStore(directory: dir).load().0.spots
    }
    #expect(try load(#"{"spots":{}}"#).filterOtherBands)                                  // starý settings.json
    #expect(try load(#"{"spots":{"filterBands":["20m"]}}"#).filterOtherBands)              // i s filtrem pásem
    #expect(try load(#"{"spots":{"rttyOnly":true}}"#).filterOtherBands)                    // migrace „Jen RTTY“
    #expect(try load(#"{"spots":{"filterOtherBands":"ne"}}"#).filterOtherBands)            // neplatná = výchozí
    #expect(try load(#"{"spots":{"filterOtherBands":false}}"#).filterOtherBands == false)

    var s = AppSettings()
    s.spots.setAllBands(false)
    #expect(s.spots.filterBands.isEmpty && !s.spots.filterOtherBands)
    let hidden = [Spot(frequencyKHz: 475, call: "OK1LF", spotter: "OK1XOE", comment: "", time: Date(), mode: "RTTY"),
                  Spot(frequencyKHz: 5000, call: "OK1UNK", spotter: "OK1XOE", comment: "", time: Date(), mode: "RTTY")]
    #expect(hidden.map(\.band) == ["630m", nil])
    #expect(s.spots.filter.apply(to: hidden).isEmpty)                                     // „Nic“ = prázdná tabulka
    s.spots.setAllBands(true)
    #expect(s.spots.filterBands == SpotFilter.allBandsSet && s.spots.filterOtherBands)
    #expect(s.spots.filter.apply(to: hidden).count == 2)                                  // „Vše“ = zpátky vidět
    try SettingsStore(directory: dir).save(s)
    #expect(SettingsStore(directory: dir).load().0 == s)                                   // kolo uložení/načtení
}

// „Jen RTTY“ se počítá z filtru módů (vlastní klíč nemá); zaškrtnutí si pamatuje předchozí volbu
// a odškrtnutí ji vrátí. Když není co vracet, zaškrtnou se všechny skupiny.
@Test func rttyOnlyRemembersPreviousModes() {
    var s = SpotSettings()
    #expect(s.rttyOnly)                                               // výchozí: jen RTTY
    s.setRTTYOnly(false)
    #expect(!s.rttyOnly && s.filterModes == SpotFilter.allModes)       // nebylo co vracet → všechny skupiny
    s.setFilterModes([.cw, .psk])
    #expect(!s.rttyOnly)
    s.setRTTYOnly(true)
    #expect(s.rttyOnly && s.filterModes == [.rtty] && s.previousFilterModes == [.cw, .psk])
    s.setRTTYOnly(false)
    #expect(s.filterModes == [.cw, .psk])                             // vrátí se předchozí volba
    // zaškrtnutí právě RTTY v okně módů má stejný účinek jako zaškrtávátko
    s.setFilterModes([.rtty])
    #expect(s.rttyOnly && s.previousFilterModes == [.cw, .psk])
    s.setRTTYOnly(false)
    #expect(s.filterModes == [.cw, .psk])
    // prázdná volba („Nic“) není co vracet
    s.setFilterModes([])
    #expect(!s.rttyOnly)
    s.setRTTYOnly(true)
    #expect(s.filterModes == [.rtty] && s.previousFilterModes.isEmpty)
    s.setRTTYOnly(false)
    #expect(s.filterModes == SpotFilter.allModes)
    // opakované zaškrtnutí pamatovanou volbu nepřepíše na „jen RTTY“
    s.setRTTYOnly(true); s.setRTTYOnly(true)
    #expect(s.previousFilterModes == SpotFilter.allModes && s.filterModes == [.rtty])
    s.setRTTYOnly(false)
    #expect(s.filterModes == SpotFilter.allModes)
}

// Pamatovaná volba módů přežije restart a dekóduje se tolerantně; zrušený klíč „rttyOnly“ se neukládá.
@Test func rttyOnlyPreviousModesSurviveRestart() throws {
    let dir = tmp()
    var s = AppSettings()
    s.spots.setFilterModes([.cw, .digi]); s.spots.setRTTYOnly(true)
    try SettingsStore(directory: dir).save(s)
    var back = SettingsStore(directory: dir).load().0
    #expect(back.spots.rttyOnly && back.spots.previousFilterModes == [.cw, .digi])
    back.spots.setRTTYOnly(false)
    #expect(back.spots.filterModes == [.cw, .digi])                   // po restartu se vrátí totéž

    func load(_ json: String) throws -> SpotSettings {
        try json.write(to: dir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
        return SettingsStore(directory: dir).load().0.spots
    }
    #expect(try load(#"{"spots":{}}"#).previousFilterModes == SpotFilter.allModes)       // bez klíče = výchozí
    #expect(try load(#"{"spots":{"previousFilterModes":"CW"}}"#).previousFilterModes == SpotFilter.allModes)
    #expect(try load(#"{"spots":{"previousFilterModes":["CW","NIC"]}}"#).previousFilterModes == [.cw])
    #expect(try load(#"{"spots":{"previousFilterModes":[]}}"#).previousFilterModes.isEmpty)
    var e = AppSettings(); e.spots.setRTTYOnly(true)
    try SettingsStore(directory: dir).save(e)
    let json = try String(contentsOf: dir.appendingPathComponent("settings.json"), encoding: .utf8)
    #expect(!json.contains("rttyOnly"))
}
