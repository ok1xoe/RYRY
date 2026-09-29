// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import Testing
import Engine
@testable import Settings

@Test func decoderSettingsDefaultsRoundTripAndTolerance() throws {
    let d = AppSettings().decoders
    #expect(!d.secondEnabled && d.secondDemod == nil && !d.channelsEnabled)
    #expect(d.maxChannels == 4 && d.channelTimeoutS == 15 && d.showChannelMarks)
    let dir = tmp()
    var s = AppSettings()
    s.decoders.secondEnabled = true; s.decoders.secondDemod = "pll"
    s.decoders.channelsEnabled = true; s.decoders.maxChannels = 8; s.decoders.channelTimeoutS = 30
    s.decoders.showChannelMarks = false
    try SettingsStore(directory: dir).save(s)
    #expect(SettingsStore(directory: dir).load().0 == s)
    try #"{"decoders":{"secondEnabled":true,"secondDemod":"xyz","maxChannels":20,"channelTimeoutS":-1}}"#
        .write(to: dir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
    let o = SettingsStore(directory: dir).load().0.decoders
    #expect(o.secondEnabled && o.secondDemod == nil && o.maxChannels == 4 && o.channelTimeoutS == 15)
    // starší nastavení bez sekce → výchozí
    try #"{"station":{"call":"OK1XOE"}}"#.write(to: dir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
    #expect(SettingsStore(directory: dir).load().0.decoders == DecoderSettings())
}

@Test func decoderSettingsToAuxConfig() {
    var d = DecoderSettings()
    d.secondEnabled = true; d.secondDemod = "fir"; d.channelsEnabled = true; d.maxChannels = 6; d.channelTimeoutS = 40
    let a = d.auxConfig()
    #expect(a.secondEnabled && a.secondDemod == "fir" && a.channelsEnabled && a.maxChannels == 6 && a.channelTimeout == 40)
    d.maxChannels = 99; d.channelTimeoutS = .nan
    #expect(d.auxConfig().maxChannels == 8 && d.auxConfig().channelTimeout == 15)
}
