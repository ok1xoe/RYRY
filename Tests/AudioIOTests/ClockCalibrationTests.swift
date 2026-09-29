import Testing
@testable import AudioIO

@Test func ppmFromActualRates() {
    #expect(ClockCalibration.ppm(actual: [48000.048, 48000.048, 48000.048], nominal: 48000)! - 1.0 < 0.01)
    let p = ClockCalibration.ppm(actual: [44100 * 1.000123], nominal: 44100)!
    #expect(abs(p - 123) < 0.01)
}

@Test func ppmIgnoresOutliersAndEmpty() {
    #expect(ClockCalibration.ppm(actual: [], nominal: 48000) == nil)
    #expect(ClockCalibration.ppm(actual: [0, 0], nominal: 48000) == nil)          // zařízení neběží
    // medián: jeden úlet (start zařízení) výsledek nezmění
    let p = ClockCalibration.ppm(actual: [48000.96, 48000.96, 47000, 48000.96, 48000.96], nominal: 48000)!
    #expect(abs(p - 20) < 0.01)
}
