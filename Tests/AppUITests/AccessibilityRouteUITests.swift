// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
// Keyboard routes for what used to need the mouse: tune to the strongest signal (click in the waterfall),
// a notch on the strongest interference (right button in the spectrum) and the last received callsign
// into the QSO window (clicking a word in the receive window).
import Foundation
import Testing
import Engine
import ModemKit
import Settings
@testable import AppUI

/// A spectrum with tones at the given frequencies (5 = noise floor).
private func tones(_ hz: [Double], level: Float = 240, binHz: Double = 5.3833, bins: Int = 743) -> SpectrumFrame {
    var m = [Float](repeating: 5, count: bins)
    for f in hz { m[Int(f / binHz)] = level }
    return SpectrumFrame(binHz: binHz, magnitudes: m)
}

// MARK: The pure search in the line spectrum

@Test func strongestMarkFindsTonePairSeparatedByShift() {
    // 600 bins over 0…3000 Hz = 5 Hz per bin; a pair 1500/1670 Hz (shift 170)
    var line = [Float](repeating: 0.05, count: 600)
    line[300] = 1; line[334] = 1                              // 1502.5 and 1672.5 Hz
    let mark = AppModel.strongestMark(in: line, from: 0, to: 3000, shiftHz: 170)
    #expect(mark != nil)
    #expect(abs((mark ?? 0) - 1502.5) < 6)
}

@Test func strongestMarkPrefersThePairOverALoneTone() {
    var line = [Float](repeating: 0.05, count: 600)
    line[100] = 0.9                                            // a lone strong carrier at 502.5 Hz
    line[400] = 0.6; line[434] = 0.6                           // a weaker but complete RTTY pair
    let mark = AppModel.strongestMark(in: line, from: 0, to: 3000, shiftHz: 170)
    #expect(abs((mark ?? 0) - 2002.5) < 6)
}

@Test func strongestMarkIsNilOnNoiseAndOnEmptySpectrum() {
    #expect(AppModel.strongestMark(in: [], from: 0, to: 3000, shiftHz: 170) == nil)
    #expect(AppModel.strongestMark(in: [Float](repeating: 0.05, count: 600), from: 0, to: 3000, shiftHz: 170) == nil)
    // a shift wider than the displayed range cannot be searched for
    #expect(AppModel.strongestMark(in: [Float](repeating: 1, count: 600), from: 0, to: 3000, shiftHz: 9000) == nil)
}

@Test func strongestInterferenceSkipsTheReceivedSignal() {
    var line = [Float](repeating: 0.05, count: 600)
    line[425] = 1; line[459] = 1                               // mark 2125 / space 2295 - the signal being received
    line[120] = 0.8                                            // interference at 602.5 Hz
    let hz = AppModel.strongestInterference(in: line, from: 0, to: 3000, mark: 2125, space: 2295)
    #expect(abs((hz ?? 0) - 602.5) < 6)
    // with nothing but the received signal there is nothing to notch
    var only = [Float](repeating: 0.05, count: 600)
    only[425] = 1; only[459] = 1
    #expect(AppModel.strongestInterference(in: only, from: 0, to: 3000, mark: 2125, space: 2295) == nil)
}

// MARK: The last received callsign

@Test func lastReceivedCallTakesTheNewestCallsign() {
    #expect(AppModel.lastReceivedCall(in: "CQ CQ DE DL1ABC DL1ABC K") == "DL1ABC")
    #expect(AppModel.lastReceivedCall(in: "OK1XOE DE G3BBB 599 599 OK2XYZ") == "OK2XYZ")
    #expect(AppModel.lastReceivedCall(in: "599 599 TU QRZ") == nil)          // nothing that looks like a callsign
    #expect(AppModel.lastReceivedCall(in: "") == nil)
}

@Test func lastReceivedCallSkipsOwnCall() {
    #expect(AppModel.lastReceivedCall(in: "DL1ABC DE OK1XOE", own: "OK1XOE") == "DL1ABC")
    #expect(AppModel.lastReceivedCall(in: "DL1ABC DE OK1XOE/P", own: "OK1XOE") == "DL1ABC")
    #expect(AppModel.lastReceivedCall(in: "DL1ABC DE OK1XOE") == "OK1XOE")   // no own call given = take it
}

// MARK: Dispatch through the model

@Test @MainActor func tuneToStrongestSignalMovesTheMark() async throws {
    let f = Fixture()
    f.configure = { $0.rtty["shift"] = .double(170) }
    await f.model.start()
    let before = f.model.mark
    f.model.pushSpectrumForTesting(tones([1500, 1670]))
    await f.model.tuneToStrongestSignal()
    await f.settle()
    #expect(f.model.mark != before)
    #expect(abs(f.model.mark - 1500) < 40, "mark \(f.model.mark)")
    await f.model.stop()
}

@Test @MainActor func tuneToStrongestSignalReportsAnEmptySpectrum() async throws {
    let f = Fixture()
    await f.model.start()
    let before = f.model.mark
    await f.model.tuneToStrongestSignal()                        // no spectrum pushed
    #expect(f.model.mark == before)
    #expect(f.model.messages.last?.isEmpty == false)
    await f.model.stop()
}

@Test @MainActor func notchStrongestInterferenceReportsWhenThereIsNothing() async throws {
    let f = Fixture()
    await f.model.start()
    await f.model.notchStrongestInterference()
    #expect(f.model.messages.last?.isEmpty == false)
    await f.model.stop()
}

@Test @MainActor func insertLastReceivedCallFillsTheCallField() async throws {
    let f = Fixture()
    await f.model.start()
    f.model.appendRx("CQ CQ DE DL1ABC DL1ABC K", echo: false)
    await f.model.insertLastReceivedCall()
    await f.settle()
    #expect(f.model.qso.call == "DL1ABC")
    await f.model.stop()
}

@Test @MainActor func insertLastReceivedCallReportsWhenThereIsNoCall() async throws {
    let f = Fixture()
    await f.model.start()
    f.model.appendRx("599 599 TU", echo: false)
    await f.model.insertLastReceivedCall()
    #expect(f.model.qso.call.isEmpty)
    #expect(f.model.messages.last?.isEmpty == false)
    await f.model.stop()
}

@Test @MainActor func editMacroRequestIsAPlainRequestFlag() {
    let f = Fixture()
    #expect(f.model.editMacroRequest == nil)
    f.model.editMacroRequest = 3
    #expect(f.model.editMacroRequest == 3)
    f.model.editMacroRequest = nil                              // the macro bar clears it after opening the sheet
    #expect(f.model.editMacroRequest == nil)
}
