// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import CoreAudio
import Foundation

/// Kalibrace hodin zvukové karty (náhrada ClockAdj z MMTTY).
///
/// Core Audio průběžně měří skutečnou vzorkovací frekvenci zařízení proti hodinám systému
/// (`kAudioDevicePropertyActualSampleRate`); odchylka od nominální frekvence v ppm se
/// použije jako korekce RX/TX modemu.
public enum ClockCalibration {
    /// Odchylka v ppm z naměřených skutečných frekvencí (medián, nuly = zařízení neběží).
    public static func ppm(actual: [Double], nominal: Double) -> Double? {
        let v = actual.filter { $0.isFinite && $0 > 0 }.sorted()
        guard !v.isEmpty, nominal > 0 else { return nil }
        let med = v.count % 2 == 1 ? v[v.count / 2] : (v[v.count / 2 - 1] + v[v.count / 2]) / 2
        return (med / nominal - 1) * 1e6
    }

    /// Nominální a skutečná frekvence zařízení (skutečná je nenulová jen za běhu).
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
