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

// Review #3: NUL v textu nesmí zablokovat frontu.
@Test func nulInTextDoesNotStallQueue() throws {
    let m = try RTTYModem()
    m.beginTx(tune: false)
    m.queueTx(text: "AB\u{0}CD")
    var buf = [Float](repeating: 0, count: 4096)
    for _ in 0..<60 { _ = buf.withUnsafeMutableBufferPointer { m.generateTx(into: $0) } }
    #expect(m.txPending == 0)
}

// Review #4: text zadaný před beginTx se neztratí.
@Test func textQueuedBeforeBeginTxIsKept() throws {
    let m = try RTTYModem()
    m.queueTx(text: "CQ CQ")
    #expect(m.txPending == 5)
    m.beginTx(tune: false)
    #expect(m.txPending > 0)
}

// Review #6: pomalý odběratel nesmí přijít o přijatý text.
@Test func slowConsumerDoesNotLoseText() async throws {
    let m = try RTTYModem()
    try m.set(parameter: "baud", value: .double(110))
    let line = "0123456789 ABCDEFGHIJ KLMNOPQRST UVWXYZ\r\n"
    let text = String(repeating: line, count: 250)        // 10 000 znaků
    let s = RTTYSignalGenerator(baud: 110).generate(text: text)
    let stream = m.events
    s.withUnsafeBufferPointer { m.processRx($0) }           // nikdo zatím nečte
    m.finishEvents()
    var got = ""
    for await e in stream { if case .rxText(let c, false) = e { got.append(c) } }
    #expect(got.hasPrefix("0123456789 ABCDEFGHIJ"))
    #expect(got.count >= text.count - 5)
}

@Test func modemExposesFskCodes() throws {
    let m = try RTTYModem()
    try m.set(parameter: "diddle", value: .string("off"))
    m.beginTx(tune: false)
    m.queueTx(text: "RY")
    var buf = [Float](repeating: 0, count: 1024)
    var codes: [UInt8] = []
    for _ in 0..<16 {
        _ = buf.withUnsafeMutableBufferPointer { m.generateTx(into: $0) }
        codes += m.takeFskCodes()
    }
    #expect(codes == [0x1F, 0x0A, 0x15])
}

@Test func intBaudUpdatesCurrentMode() throws {
    let m = try RTTYModem()
    try m.set(parameter: "baud", value: .int(50))
    #expect(m.currentMode.id == "RTTY-50")
}

@Test func markFarBelowCurrentIsReachable() throws {
    let m = try RTTYModem()
    try m.set(parameter: "mark", value: .double(200))
    #expect(m.get(parameter: "mark") == .double(200))
    #expect(m.get(parameter: "shift") == .double(170))
}

@Test func modemXYScope() throws {
    let m = try RTTYModem()
    m.setXYScope(true)
    let s = RTTYSignalGenerator().generate(text: "RYRY", leadIn: 0.5)
    s.withUnsafeBufferPointer { m.processRx($0) }
    let pts = try #require(m.xyScope())
    #expect(pts.count == 512)
}
