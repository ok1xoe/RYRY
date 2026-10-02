// Copyright 2026 OK1XOE (RYRY), LGPL v3
import CoreAudio
import Foundation

/// Sound card clock calibration (a replacement for ClockAdj from MMTTY).
///
/// Core Audio continuously measures the device's actual sample rate against the system clock
/// (`kAudioDevicePropertyActualSampleRate`); the deviation from the nominal rate in ppm is
/// used as the RX/TX correction of the modem.
public enum ClockCalibration {
    /// Deviation in ppm from the measured actual rates (median, zeros = the device is not running).
    public static func ppm(actual: [Double], nominal: Double) -> Double? {
        let v = actual.filter { $0.isFinite && $0 > 0 }.sorted()
        guard !v.isEmpty, nominal > 0 else { return nil }
        let med = v.count % 2 == 1 ? v[v.count / 2] : (v[v.count / 2 - 1] + v[v.count / 2]) / 2
        return (med / nominal - 1) * 1e6
    }

    /// Nominal and actual device rate (the actual one is non-zero only while running).
    public static func rates(deviceUID uid: String?, input: Bool) -> (nominal: Double, actual: Double)? {
        let dev = uid.flatMap(AudioDevices.find(uid:)) ?? (input ? AudioDevices.defaultInput() : AudioDevices.defaultOutput())
        guard let dev else { return nil }
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyActualSampleRate,
                                           mScope: kAudioObjectPropertyScopeGlobal,
                                           mElement: kAudioObjectPropertyElementMain)
        var r: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        let ok = AudioObjectGetPropertyData(AudioObjectID(dev.id), &a, 0, nil, &size, &r) == noErr
        return (dev.sampleRate, ok ? r : 0)
    }
}
