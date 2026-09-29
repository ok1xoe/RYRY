import Foundation
import Testing
@testable import AudioIO

@Test func ringFifoAndWrap() {
    let r = RingBuffer(capacity: 8)
    #expect(r.write([1, 2, 3, 4, 5]) == 5)
    var out = [Float](repeating: 0, count: 3)
    #expect(r.read(into: &out, count: 3) == 3)
    #expect(out == [1, 2, 3])
    #expect(r.write([6, 7, 8, 9, 10, 11]) == 6)       // přes konec bufferu
    #expect(r.write([99]) == 0)                        // plný (8)
    var all = [Float](repeating: 0, count: 10)
    #expect(r.read(into: &all, count: 10) == 8)
    #expect(Array(all[0..<8]) == [4, 5, 6, 7, 8, 9, 10, 11])
    #expect(r.available == 0)
}

@Test func ringStressTwoThreads() async {
    let r = RingBuffer(capacity: 1024)
    let total = 500_000
    let producer = Task.detached {
        var next: Float = 0
        var chunk = [Float](repeating: 0, count: 100)
        var sent = 0
        while sent < total {
            let n = min(100, total - sent)
            for i in 0..<n { chunk[i] = next + Float(i) }
            let w = r.write(Array(chunk[0..<n]))
            next += Float(w); sent += w
            if w == 0 { await Task.yield() }
        }
    }
    var expected: Float = 0
    var got = 0
    var ok = true
    var buf = [Float](repeating: 0, count: 128)
    while got < total {
        let n = r.read(into: &buf, count: 128)
        for i in 0..<n where buf[i] != expected + Float(i) { ok = false }
        expected += Float(n); got += n
        if n == 0 { await Task.yield() }
    }
    await producer.value
    #expect(ok && got == total)
}

func toneFrequency(_ s: [Float], rate: Double) -> Double {
    var c = 0
    for i in 1..<s.count where (s[i - 1] < 0) != (s[i] < 0) { c += 1 }
    return Double(c) / 2 / (Double(s.count) / rate)
}

@Test(arguments: [(48000.0, 11025.0), (11025.0, 48000.0), (44100.0, 11025.0)])
func converterPreservesTone(from: Double, to: Double) throws {
    let conv = try SampleRateConverter(from: from, to: to)
    let n = Int(from)                                 // 1 s
    let tone = (0..<n).map { Float(0.5 * sin(2 * Double.pi * 2125 * Double($0) / from)) }
    var out: [Float] = []
    for start in stride(from: 0, to: n, by: 480) {      // po blocích jako z audia
        out += conv.process(Array(tone[start..<min(n, start + 480)]))
    }
    #expect(abs(Double(out.count) - to) / to < 0.02)
    let mid = Array(out[out.count / 4..<out.count * 3 / 4])
    #expect(abs(toneFrequency(mid, rate: to) - 2125) < 3)
}

@Test func deviceEnumerationDoesNotCrash() {
    let all = AudioDevices.all()
    for d in all { #expect(!d.uid.isEmpty) }
    _ = AudioDevices.defaultInput()
    _ = AudioDevices.defaultOutput()
}

@Test func requestClearIsAppliedByConsumer() {
    let r = RingBuffer(capacity: 16)
    r.write([1, 2, 3, 4])
    r.requestClear()
    var out = [Float](repeating: 0, count: 8)
    #expect(r.read(into: &out, count: 8) == 0)
    r.write([5])
    #expect(r.read(into: &out, count: 8) == 1 && out[0] == 5)
}
