import Foundation
import Spots
import Testing
@testable import Settings

@Test func spotSettingsDefaultsAreOff() {
    let s = AppSettings().spots
    #expect(!s.clusterEnabled && !s.rbnEnabled)          // networking only when explicitly turned on
    #expect(s.maxAgeMinutes == 30 && s.offsetHz == 0)
    #expect(s.filterBands == SpotFilter.allBandsSet && s.filterModes == [.rtty])   // all bands, RTTY only
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
    #expect(o.filterModes == SpotFilter.allModes)                                 // rttyOnly migration: false
}

@Test func spotShowInWaterfallDefaultsTrueAndIsTolerant() throws {
    #expect(AppSettings().spots.showInWaterfall)
    let dir = tmp()
    try #"{"spots":{"rttyOnly":false}}"#.write(to: dir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
    #expect(SettingsStore(directory: dir).load().0.spots.showInWaterfall)            // a missing key = the default
    try #"{"spots":{"showInWaterfall":"ne"}}"#.write(to: dir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
    #expect(SettingsStore(directory: dir).load().0.spots.showInWaterfall)            // an invalid value = the default
    try #"{"spots":{"showInWaterfall":false}}"#.write(to: dir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
    #expect(!SettingsStore(directory: dir).load().0.spots.showInWaterfall)
}

// Migration of the retired "rttyOnly" key to the mode filter: true = RTTY only, false = all modes, missing = the default.
@Test func spotFilterMigratesFromRTTYOnly() throws {
    let dir = tmp()
    func load(_ json: String) throws -> SpotSettings {
        try json.write(to: dir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
        return SettingsStore(directory: dir).load().0.spots
    }
    #expect(try load(#"{"spots":{"rttyOnly":true}}"#).filterModes == [.rtty])
    #expect(try load(#"{"spots":{"rttyOnly":false}}"#).filterModes == SpotFilter.allModes)
    #expect(try load(#"{"spots":{}}"#).filterModes == [.rtty])                      // no key = the default
    #expect(try load(#"{"spots":{"rttyOnly":true}}"#).filterBands == SpotFilter.allBandsSet)
    // the new key takes precedence over the old one
    #expect(try load(#"{"spots":{"rttyOnly":true,"filterModes":["CW"]}}"#).filterModes == [.cw])
    #expect(try load(#"{"spots":{"rttyOnly":"ano"}}"#).filterModes == [.rtty])       // an invalid value = RTTY only
}

// The band and mode filter: tolerant decoding and a save/load round trip.
@Test func spotFilterSettingsAreTolerant() throws {
    let dir = tmp()
    func load(_ json: String) throws -> SpotSettings {
        try json.write(to: dir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
        return SettingsStore(directory: dir).load().0.spots
    }
    #expect(try load(#"{"spots":{"filterBands":["20m","40m"]}}"#).filterBands == ["20m", "40m"])
    #expect(try load(#"{"spots":{"filterBands":[]}}"#).filterBands.isEmpty)          // "None" is a valid state
    #expect(try load(#"{"spots":{"filterModes":[]}}"#).filterModes.isEmpty)
    #expect(try load(#"{"spots":{"filterBands":["20m","2m","xx",7]}}"#).filterBands == ["20m"])   // anything outside the list is dropped
    #expect(try load(#"{"spots":{"filterBands":"20m"}}"#).filterBands == SpotFilter.allBandsSet)  // invalid = the default
    #expect(try load(#"{"spots":{"filterModes":"CW"}}"#).filterModes == [.rtty])
    #expect(try load(#"{"spots":{"filterModes":["CW","NIC","OTHER"]}}"#).filterModes == [.cw, .other])

    var s = AppSettings()
    s.spots.filterBands = ["160m", "6m"]; s.spots.filterModes = [.digi, .ssb, .psk]
    try SettingsStore(directory: dir).save(s)
    let back = SettingsStore(directory: dir).load().0.spots
    #expect(back.filterBands == ["160m", "6m"] && back.filterModes == [.digi, .ssb, .psk])
    #expect(back.filter == SpotFilter(bands: ["160m", "6m"], modes: [.digi, .ssb, .psk]))
}

// An unknown band or mode group name is dropped, but it is named in a warning – just as an invalid type on the same key
// (a silently unchecked filter would look like a lost setting).
@Test func unknownFilterNamesAreReported() throws {
    let dir = tmp()
    func load(_ json: String) throws -> (SpotSettings, [String]) {
        try json.write(to: dir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
        let r = SettingsStore(directory: dir).load()
        return (r.0.spots, r.1)
    }
    var (s, w) = try load(#"{"spots":{"filterBands":["20m","2m","xx"]}}"#)
    #expect(s.filterBands == ["20m"])
    #expect(w.contains { $0.contains("spots.filterBands") && $0.contains("2m") && $0.contains("xx") })
    (s, w) = try load(#"{"spots":{"filterModes":["CW","NIC"]}}"#)
    #expect(s.filterModes == [.cw])
    #expect(w.contains { $0.contains("spots.filterModes") && $0.contains("NIC") })
    (s, w) = try load(#"{"spots":{"previousFilterModes":["SSB","XY"]}}"#)
    #expect(s.previousFilterModes == [.ssb])
    #expect(w.contains { $0.contains("spots.previousFilterModes") && $0.contains("XY") })
    (s, w) = try load(#"{"spots":{"filterBands":["20m"],"filterModes":["CW"]}}"#)
    #expect(s.filterBands == ["20m"] && w.isEmpty)                      // only known names → no warning
    (s, w) = try load(#"{"spots":{"filterBands":"20m"}}"#)              // an invalid type warns as before
    #expect(s.filterBands == SpotFilter.allBandsSet && w.contains { $0.contains("spots.filterBands") })
}

// The "other" check box for the bands (spots outside the fixed list): checked by default, even in an old settings.json;
// the All / None buttons toggle it together with the fixed list, so after "None" not a single spot gets through.
@Test func otherBandsFilterDefaultsOnAndIsTolerant() throws {
    #expect(SpotSettings().filterOtherBands && SpotSettings().filter.otherBands)
    let dir = tmp()
    func load(_ json: String) throws -> SpotSettings {
        try json.write(to: dir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
        return SettingsStore(directory: dir).load().0.spots
    }
    #expect(try load(#"{"spots":{}}"#).filterOtherBands)                                  // an old settings.json
    #expect(try load(#"{"spots":{"filterBands":["20m"]}}"#).filterOtherBands)              // with a band filter as well
    #expect(try load(#"{"spots":{"rttyOnly":true}}"#).filterOtherBands)                    // migration of "RTTY only"
    #expect(try load(#"{"spots":{"filterOtherBands":"ne"}}"#).filterOtherBands)            // invalid = the default
    #expect(try load(#"{"spots":{"filterOtherBands":false}}"#).filterOtherBands == false)

    var s = AppSettings()
    s.spots.setAllBands(false)
    #expect(s.spots.filterBands.isEmpty && !s.spots.filterOtherBands)
    let hidden = [Spot(frequencyKHz: 475, call: "OK1LF", spotter: "OK1XOE", comment: "", time: Date(), mode: "RTTY"),
                  Spot(frequencyKHz: 5000, call: "OK1UNK", spotter: "OK1XOE", comment: "", time: Date(), mode: "RTTY")]
    #expect(hidden.map(\.band) == ["630m", nil])
    #expect(s.spots.filter.apply(to: hidden).isEmpty)                                     // "None" = an empty table
    s.spots.setAllBands(true)
    #expect(s.spots.filterBands == SpotFilter.allBandsSet && s.spots.filterOtherBands)
    #expect(s.spots.filter.apply(to: hidden).count == 2)                                  // "All" = visible again
    try SettingsStore(directory: dir).save(s)
    #expect(SettingsStore(directory: dir).load().0 == s)                                   // a save/load round trip
}

// "RTTY only" is derived from the mode filter (it has no key of its own); checking it remembers the previous choice
// and unchecking it restores that choice. When there is nothing to restore, all the groups are checked.
@Test func rttyOnlyRemembersPreviousModes() {
    var s = SpotSettings()
    #expect(s.rttyOnly)                                               // the default: RTTY only
    s.setRTTYOnly(false)
    #expect(!s.rttyOnly && s.filterModes == SpotFilter.allModes)       // there was nothing to restore → all the groups
    s.setFilterModes([.cw, .psk])
    #expect(!s.rttyOnly)
    s.setRTTYOnly(true)
    #expect(s.rttyOnly && s.filterModes == [.rtty] && s.previousFilterModes == [.cw, .psk])
    s.setRTTYOnly(false)
    #expect(s.filterModes == [.cw, .psk])                             // the previous choice is restored
    // checking exactly RTTY in the modes window has the same effect as the check box
    s.setFilterModes([.rtty])
    #expect(s.rttyOnly && s.previousFilterModes == [.cw, .psk])
    s.setRTTYOnly(false)
    #expect(s.filterModes == [.cw, .psk])
    // an empty choice ("None") is nothing to restore
    s.setFilterModes([])
    #expect(!s.rttyOnly)
    s.setRTTYOnly(true)
    #expect(s.filterModes == [.rtty] && s.previousFilterModes.isEmpty)
    s.setRTTYOnly(false)
    #expect(s.filterModes == SpotFilter.allModes)
    // checking it again does not overwrite the remembered choice with "RTTY only"
    s.setRTTYOnly(true); s.setRTTYOnly(true)
    #expect(s.previousFilterModes == SpotFilter.allModes && s.filterModes == [.rtty])
    s.setRTTYOnly(false)
    #expect(s.filterModes == SpotFilter.allModes)
}

// The remembered mode choice survives a restart and is decoded tolerantly; the retired "rttyOnly" key is not written.
@Test func rttyOnlyPreviousModesSurviveRestart() throws {
    let dir = tmp()
    var s = AppSettings()
    s.spots.setFilterModes([.cw, .digi]); s.spots.setRTTYOnly(true)
    try SettingsStore(directory: dir).save(s)
    var back = SettingsStore(directory: dir).load().0
    #expect(back.spots.rttyOnly && back.spots.previousFilterModes == [.cw, .digi])
    back.spots.setRTTYOnly(false)
    #expect(back.spots.filterModes == [.cw, .digi])                   // after a restart the same thing comes back

    func load(_ json: String) throws -> SpotSettings {
        try json.write(to: dir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
        return SettingsStore(directory: dir).load().0.spots
    }
    #expect(try load(#"{"spots":{}}"#).previousFilterModes == SpotFilter.allModes)       // no key = the default
    #expect(try load(#"{"spots":{"previousFilterModes":"CW"}}"#).previousFilterModes == SpotFilter.allModes)
    #expect(try load(#"{"spots":{"previousFilterModes":["CW","NIC"]}}"#).previousFilterModes == [.cw])
    #expect(try load(#"{"spots":{"previousFilterModes":[]}}"#).previousFilterModes.isEmpty)
    var e = AppSettings(); e.spots.setRTTYOnly(true)
    try SettingsStore(directory: dir).save(e)
    let json = try String(contentsOf: dir.appendingPathComponent("settings.json"), encoding: .utf8)
    #expect(!json.contains("rttyOnly"))
}
