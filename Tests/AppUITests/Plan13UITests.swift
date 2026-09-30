// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import Testing
import AppCore
import Engine
import ModemKit
import Settings
@testable import AppUI

// Word wrapping of typed text at a column (MMTTY "Word wrap on keyboard")
@Test func txWrap() {
    #expect(TxWrap.wrap("CQ CQ DE OK1XOE", column: 0) == "CQ CQ DE OK1XOE")
    #expect(TxWrap.wrap("CQ CQ DE OK1XOE", column: 10) == "CQ CQ DE\nOK1XOE")
    #expect(TxWrap.wrap("ABCDEFGHIJKLMN", column: 10) == "ABCDEFGHIJ\nKLMN")          // no space = a hard break
    #expect(TxWrap.wrap("AB CD\nEF GH IJ KL MN", column: 8) == "AB CD\nEF GH IJ\nKL MN")
    #expect(TxWrap.wrap("0123456789", column: 10) == "0123456789")                    // exactly at the column – unchanged
}

// Waterfall palettes: grey has R = G = B; every palette runs from dark to light
@Test func waterfallPalettes() {
    for p in WaterfallPalette.allCases {
        let lo = WaterfallRenderer.color(0, p), hi = WaterfallRenderer.color(1, p)
        #expect(lo & 0xFFFFFF == 0, "\(p)")
        #expect(hi & 0xFF + (hi >> 8) & 0xFF + (hi >> 16) & 0xFF > 400, "\(p)")
    }
    let g = WaterfallRenderer.color(0.5, .gray)
    #expect(g & 0xFF == (g >> 8) & 0xFF && g & 0xFF == (g >> 16) & 0xFF)
}

// FFT response: the slow one decays longer than the fast one
@Test func fftResponseDecay() {
    func afterDrop(_ r: FFTResponse) -> Float {
        var w = WaterfallRenderer(width: 10, height: 2); w.autoGain = false; w.decay = r.decay
        w.push(SpectrumFrame(binHz: 300, magnitudes: [Float](repeating: 256, count: 10)), fromHz: 0, toHz: 3000)
        w.push(SpectrumFrame(binHz: 300, magnitudes: [Float](repeating: 0, count: 10)), fromHz: 0, toHz: 3000)
        return w.spectrumLine[5]
    }
    #expect(afterDrop(.slow) > afterDrop(.normal) && afterDrop(.normal) > afterDrop(.fast))
}

// Automatic CR LF with the TX button (MMTTY "Auto send CR/LF with TX button")
@Test @MainActor func autoCRLFOnTx() async throws {
    let f = Fixture()
    f.configure = { $0.txWindow.autoCRLF = true; $0.ptt.method = .none }
    await f.model.start()
    await f.model.toggleTx()
    #expect(f.model.lastSentForTesting == "\r\n")
    await f.model.stop()
}

// Review (deferred): wrapping also counts the text transmitted since the last line end
@Test func txWrapWithSentPrefix() {
    #expect(TxWrap.wrap("DE OK1XOE", column: 10, startColumn: 6) == "DE\nOK1XOE")
    #expect(TxWrap.wrap("AB", column: 10, startColumn: 9) == "\nAB")               // at the end of the line the break comes before the word
    #expect(TxWrap.wrap("CQ CQ", column: 10, startColumn: 0) == "CQ CQ")
    #expect(TxWrap.column(afterSending: "CQ CQ\r\nDE OK1") == 6 && TxWrap.column(afterSending: "XY", from: 3) == 5)
}
