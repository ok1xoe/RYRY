import Foundation
import Testing
@testable import Settings

@Test func clusterMacrosDefaultsAreTenDXSpiderCommands() {
    let m = AppSettings().spots.clusterMacros
    #expect(m.count == SpotSettings.clusterMacroCount && m.count == 10)
    #expect(m.map(\.name) == ["SH/DX", "RTTY", "20 m", "40 m", "WWV", "Slunce", "Skimmer ON", "Skimmer OFF", "Uživatelé", "Spot"])
    #expect(m[0].text == "sh/dx 30" && m[4].text == "sh/wwv" && m[9].text == "dx %k %c RTTY")
}

@Test func clusterMacrosRoundTripAndTolerance() throws {
    let dir = tmp()
    var s = AppSettings()
    s.spots.clusterMacros[2] = Macro(name: "Moje", text: "sh/dx 5\nsh/wwv", color: "#FF0000")
    try SettingsStore(directory: dir).save(s)
    #expect(SettingsStore(directory: dir).load().0 == s)
    // chybějící klíč = výchozí; krátký seznam se doplní na 10; dlouhý se ořízne; vadná položka se nahradí prázdnou
    let d = JSONDecoder()
    #expect(try d.decode(SpotSettings.self, from: Data("{}".utf8)).clusterMacros == SpotSettings.defaultClusterMacros)
    let short = try d.decode(SpotSettings.self, from: Data(#"{"clusterMacros":[{"name":"A","text":"sh/dx"}]}"#.utf8)).clusterMacros
    #expect(short.count == 10 && short[0].name == "A" && short[1] == Macro(name: "", text: ""))
    let many = "[" + (0..<15).map { #"{"name":"n\#($0)","text":"t"}"# }.joined(separator: ",") + "]"
    #expect(try d.decode(SpotSettings.self, from: Data(#"{"clusterMacros":\#(many)}"#.utf8)).clusterMacros.count == 10)
    let bad = try d.decode(SpotSettings.self, from: Data(#"{"clusterMacros":[5,{"name":"B","text":"x","color":"zzz","repeatSeconds":-3}]}"#.utf8)).clusterMacros
    #expect(bad.count == 10 && bad[0] == Macro(name: "", text: "") && bad[1].name == "B" && bad[1].color == nil && bad[1].repeatSeconds == nil)
    let notArray = try d.decode(SpotSettings.self, from: Data(#"{"clusterMacros":"x"}"#.utf8)).clusterMacros
    #expect(notArray.count == 10)
}
