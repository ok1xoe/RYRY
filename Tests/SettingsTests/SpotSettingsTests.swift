import Foundation
import Testing
@testable import Settings

@Test func spotSettingsDefaultsAreOff() {
    let s = AppSettings().spots
    #expect(!s.clusterEnabled && !s.rbnEnabled)          // síť jen na výslovné zapnutí
    #expect(s.rttyOnly && s.maxAgeMinutes == 30 && s.offsetHz == 0)
    #expect(s.clusterPort == 23 && s.rbnPort == 7000 && s.rbnHost == "telnet.reversebeacon.net")
}

@Test func spotSettingsRoundTripAndTolerance() throws {
    let dir = tmp()
    var s = AppSettings()
    s.spots.clusterEnabled = true; s.spots.clusterHost = "dxfun.com"; s.spots.clusterPort = 8000
    s.spots.clusterCommands = ["set/skimmer", "sh/dx 30"]; s.spots.rbnEnabled = true
    s.spots.rttyOnly = false; s.spots.maxAgeMinutes = 60; s.spots.offsetHz = 2125
    try SettingsStore(directory: dir).save(s)
    #expect(SettingsStore(directory: dir).load().0 == s)

    try #"{"spots":{"clusterPort":99999,"clusterHost":"bad host","rbnPort":"x","maxAgeMinutes":0,"offsetHz":1e9,"clusterCommands":["  sh/dx  ","",5],"rttyOnly":false}}"#
        .write(to: dir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
    let o = SettingsStore(directory: dir).load().0.spots
    #expect(o.clusterPort == 23 && o.clusterHost == "dxc.ve7cc.net" && o.rbnPort == 7000)
    #expect(o.maxAgeMinutes == 30 && o.offsetHz == 0)
    #expect(o.clusterCommands == ["sh/dx"])
    #expect(!o.rttyOnly)
}
