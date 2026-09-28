import Foundation
import Testing
@testable import ModemKit

let baud = ParameterDescriptor(id: "baud", label: "Baud", kind: .double(20...300, unit: "Bd"),
                               defaultValue: .double(45.45))
let demod = ParameterDescriptor(id: "demodType", label: "Demodulator",
                                kind: .choice(["iir", "fir", "pll", "fft"]), defaultValue: .string("iir"))
let afc = ParameterDescriptor(id: "afc", label: "AFC", kind: .bool, defaultValue: .bool(true))
let taps = ParameterDescriptor(id: "firTap", label: "FIR taps", kind: .int(8...512), defaultValue: .int(72))

@Test func acceptsValidValues() throws {
    #expect(try baud.validate(.double(75)) == .double(75))
    #expect(try demod.validate(.string("pll")) == .string("pll"))
    #expect(try afc.validate(.bool(false)) == .bool(false))
    #expect(try taps.validate(.int(128)) == .int(128))
}

@Test func intIsAcceptedForDoubleParameter() throws {
    #expect(try baud.validate(.int(50)) == .double(50))
}

@Test func rejectsOutOfRangeAndWrongType() {
    #expect(throws: ParameterError.outOfRange("baud")) { try baud.validate(.double(0)) }
    #expect(throws: ParameterError.outOfRange("baud")) { try baud.validate(.double(.nan)) }
    #expect(throws: ParameterError.outOfRange("demodType")) { try demod.validate(.string("xyz")) }
    #expect(throws: ParameterError.typeMismatch("afc")) { try afc.validate(.string("yes")) }
    #expect(throws: ParameterError.outOfRange("firTap")) { try taps.validate(.int(4)) }
}

@Test func valueCodableRoundTrip() throws {
    let v: [ParameterValue] = [.bool(true), .int(3), .double(45.45), .string("iir")]
    let data = try JSONEncoder().encode(v)
    #expect(try JSONDecoder().decode([ParameterValue].self, from: data) == v)
}
