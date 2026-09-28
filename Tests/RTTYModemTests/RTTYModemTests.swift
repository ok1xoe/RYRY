import Testing
import ModemKit
@testable import RTTYModem
import RTTYSignalKit

func collectText(_ m: RTTYModem, _ samples: [Float]) async -> String {
    let stream = m.events
    samples.withUnsafeBufferPointer { p in
        var i = 0
        while i < p.count {
            let n = min(512, p.count - i)
            m.processRx(UnsafeBufferPointer(rebasing: p[i..<i + n])); i += n
        }
    }
    m.finishEvents()
    var text = ""
    for await e in stream { if case .rxText(let c, false) = e { text.append(c) } }
    return text
}

@Test func decodesViaModemProtocol() async throws {
    let m = try RTTYModem()
    let text = "CQ CQ DE OK1XOE K\r\n"
    let s = RTTYSignalGenerator().generate(text: text)
    #expect(await collectText(m, s) == text)
}

@Test func rejectsUnsupportedRate() {
    #expect(throws: RTTYModem.Error.unsupportedSampleRate(48000)) { try RTTYModem(sampleRate: 48000) }
}

@Test func parameterRoundTripAndValidation() throws {
    let m = try RTTYModem()
    try m.set(parameter: "shift", value: .double(850))
    #expect(m.get(parameter: "shift") == .double(850))
    #expect(m.get(parameter: "mark") == .double(2125))
    try m.set(parameter: "demodType", value: .string("pll"))
    #expect(m.get(parameter: "demodType") == .string("pll"))
    try m.set(parameter: "stopBits", value: .string("1.5"))
    #expect(m.get(parameter: "stopBits") == .string("1.5"))
    #expect(throws: RTTYModem.Error.parameter(.outOfRange("baud"))) {
        try m.set(parameter: "baud", value: .double(1000))
    }
    #expect(throws: RTTYModem.Error.parameter(.unknown("nope"))) {
        try m.set(parameter: "nope", value: .bool(true))
    }
}

@Test func settingMarkKeepsShift() throws {
    let m = try RTTYModem()
    try m.set(parameter: "mark", value: .double(1275))
    #expect(m.get(parameter: "shift") == .double(170))
    #expect(m.get(parameter: "mark") == .double(1275))
}

@Test func selectModeChangesBaud() throws {
    let m = try RTTYModem()
    let m75 = try #require(m.modes.first { $0.id == "RTTY-75" })
    try m.select(mode: m75)
    #expect(m.currentMode == m75)
    #expect(m.get(parameter: "baud") == .double(75))
}

@Test func everyParameterDefaultIsValidAndReadable() throws {
    let m = try RTTYModem()
    for p in m.parameters {
        #expect(throws: Never.self) { _ = try p.validate(p.defaultValue) }
        let v = m.get(parameter: p.id)
        #expect(v != nil, "get(\(p.id)) vrací nil")
        if let v { #expect(throws: Never.self) { _ = try p.validate(v) } }
    }
}

@Test func everyParameterCanBeSetToItsDefault() throws {
    let m = try RTTYModem()
    for p in m.parameters {
        #expect(throws: Never.self, "\(p.id)") { try m.set(parameter: p.id, value: p.defaultValue) }
    }
}

// Review Focus 4: text delší než TX buffer jádra se odvysílá celý
@Test func longTextIsFullyTransmitted() async throws {
    let tx = try RTTYModem()
    let long = String(repeating: "RYRYRY CQ TEST ", count: 200)      // 3000 znaků
    tx.beginTx(tune: false)
    tx.queueTx(text: long)
    var out: [Float] = []
    var buf = [Float](repeating: 0, count: 4096)
    var stopped = false
    for _ in 0..<10_000 {
        if !stopped && tx.txPending == 0 { tx.stopTx(); stopped = true }
        let st = buf.withUnsafeMutableBufferPointer { tx.generateTx(into: $0) }
        out += buf
        if st == .finished { break }
    }
    let rx = try RTTYModem()
    let decoded = await collectText(rx, out + [Float](repeating: 0, count: 4000))
    #expect(decoded.components(separatedBy: "CQ TEST").count - 1 >= 199)
}

@Test func spectrumAvailableAfterProcessing() throws {
    let m = try RTTYModem()
    let s = RTTYSignalGenerator().generate(codes: [], leadIn: 1.0, tail: 0)
    s.withUnsafeBufferPointer { m.processRx($0) }
    let frame = try #require(m.spectrum())
    #expect(frame.binHz > 0 && !frame.magnitudes.isEmpty)
}

@Test func tuningEventAfterAFC() async throws {
    let m = try RTTYModem()
    let s = RTTYSignalGenerator(markHz: 2065).generate(text: String(repeating: "RYRYRYRY ", count: 8))
    let stream = m.events
    s.withUnsafeBufferPointer { m.processRx($0) }
    m.finishEvents()
    var last: TuningInfo?
    for await e in stream { if case .tuning(let t) = e { last = t } }
    let t = try #require(last)
    #expect(abs(t.mark - 2065) < 6)
}

@Test func declaredDefaultsMatchCoreState() throws {
    let m = try RTTYModem()
    for p in m.parameters {
        #expect(m.get(parameter: p.id) == p.defaultValue, "\(p.id)")
    }
}
