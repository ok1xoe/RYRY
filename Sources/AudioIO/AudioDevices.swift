// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import CoreAudio
import Foundation

public struct AudioDevice: Sendable, Hashable, Codable {
    public let id: UInt32
    public let uid: String
    public let name: String
    public let inputChannels: Int
    public let outputChannels: Int
    public let sampleRate: Double
}

public enum AudioDevices {
    private static func address(_ sel: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func string(_ id: AudioObjectID, _ sel: AudioObjectPropertySelector) -> String? {
        var a = address(sel)
        var v: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &v) == noErr, let s = v else { return nil }
        return s.takeRetainedValue() as String
    }

    private static func channels(_ id: AudioObjectID, _ scope: AudioObjectPropertyScope) -> Int {
        var a = address(kAudioDevicePropertyStreamConfiguration, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func rate(_ id: AudioObjectID) -> Double {
        var a = address(kAudioDevicePropertyNominalSampleRate)
        var r: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        return AudioObjectGetPropertyData(id, &a, 0, nil, &size, &r) == noErr ? r : 0
    }

    private static func device(_ id: AudioObjectID) -> AudioDevice? {
        guard let uid = string(id, kAudioDevicePropertyDeviceUID) else { return nil }
        return AudioDevice(id: id, uid: uid, name: string(id, kAudioObjectPropertyName) ?? uid,
                           inputChannels: channels(id, kAudioObjectPropertyScopeInput),
                           outputChannels: channels(id, kAudioObjectPropertyScopeOutput),
                           sampleRate: rate(id))
    }

    public static func all() -> [AudioDevice] {
        var a = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        let sys = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(sys, &a, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(sys, &a, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap(device)
    }

    private static func defaultDevice(_ sel: AudioObjectPropertySelector) -> AudioDevice? {
        var a = address(sel)
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &id) == noErr,
              id != 0 else { return nil }
        return device(id)
    }

    public static func defaultInput() -> AudioDevice? { defaultDevice(kAudioHardwarePropertyDefaultInputDevice) }
    public static func defaultOutput() -> AudioDevice? { defaultDevice(kAudioHardwarePropertyDefaultOutputDevice) }
    public static func find(uid: String) -> AudioDevice? { all().first { $0.uid == uid } }
}
