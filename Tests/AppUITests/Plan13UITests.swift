// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import Testing
import AppCore
import Engine
import ModemKit
import Settings
@testable import AppUI

// Zalamování psaného textu na sloupci (MMTTY „Word wrap on keyboard“)
@Test func txWrap() {
    #expect(TxWrap.wrap("CQ CQ DE OK1XOE", column: 0) == "CQ CQ DE OK1XOE")
    #expect(TxWrap.wrap("CQ CQ DE OK1XOE", column: 10) == "CQ CQ DE\nOK1XOE")
    #expect(TxWrap.wrap("ABCDEFGHIJKLMN", column: 10) == "ABCDEFGHIJ\nKLMN")          // bez mezery = tvrdý zlom
    #expect(TxWrap.wrap("AB CD\nEF GH IJ KL MN", column: 8) == "AB CD\nEF GH IJ\nKL MN")
    #expect(TxWrap.wrap("0123456789", column: 10) == "0123456789")                    // přesně na sloupci – beze změny
}

// Palety vodopádu: šedá má R = G = B; každá paleta je od tmavé po světlou
@Test func waterfallPalettes() {
    for p in WaterfallPalette.allCases {
        let lo = WaterfallRenderer.color(0, p), hi = WaterfallRenderer.color(1, p)
        #expect(lo & 0xFFFFFF == 0, "\(p)")
        #expect(hi & 0xFF + (hi >> 8) & 0xFF + (hi >> 16) & 0xFF > 400, "\(p)")
    }
    let g = WaterfallRenderer.color(0.5, .gray)
    #expect(g & 0xFF == (g >> 8) & 0xFF && g & 0xFF == (g >> 16) & 0xFF)
}

// Odezva FFT: pomalá doznívá déle než rychlá
@Test func fftResponseDecay() {
    func afterDrop(_ r: FFTResponse) -> Float {
        var w = WaterfallRenderer(width: 10, height: 2); w.autoGain = false; w.decay = r.decay
        w.push(SpectrumFrame(binHz: 300, magnitudes: [Float](repeating: 256, count: 10)), fromHz: 0, toHz: 3000)
        w.push(SpectrumFrame(binHz: 300, magnitudes: [Float](repeating: 0, count: 10)), fromHz: 0, toHz: 3000)
        return w.spectrumLine[5]
    }
    #expect(afterDrop(.slow) > afterDrop(.normal) && afterDrop(.normal) > afterDrop(.fast))
}

// Automatické CR LF při TX tlačítkem (MMTTY „Auto send CR/LF with TX button“)
@Test @MainActor func autoCRLFOnTx() async throws {
    let f = Fixture()
    f.configure = { $0.txWindow.autoCRLF = true; $0.ptt.method = .none }
    await f.model.start()
    await f.model.toggleTx()
    #expect(f.model.lastSentForTesting == "\r\n")
    await f.model.stop()
}
