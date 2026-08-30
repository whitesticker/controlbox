import CoreAudio
import Foundation

public struct AudioOutput: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var isDefault: Bool

    public init(id: String, name: String, isDefault: Bool) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
    }
}

public enum SystemAudio {
    public static func outputs() -> [AudioOutput] {
        let defaultUID = defaultOutputUID()
        return deviceIDs().compactMap { device in
            guard outputStreamCount(device) > 0, let uid = stringProperty(device, kAudioDevicePropertyDeviceUID) else {
                return nil
            }
            let name = stringProperty(device, kAudioObjectPropertyName) ?? uid
            if isMixerDevice(uid: uid, name: name) {
                return nil
            }
            return AudioOutput(id: uid, name: name, isDefault: uid == defaultUID)
        }
    }

    public static func defaultOutputUID() -> String? {
        guard let device = defaultOutputDevice(),
              let uid = stringProperty(device, kAudioDevicePropertyDeviceUID) else {
            return nil
        }
        let name = stringProperty(device, kAudioObjectPropertyName) ?? uid
        if !isMixerDevice(uid: uid, name: name) {
            return uid
        }
        return deviceIDs().compactMap { candidate -> String? in
            guard outputStreamCount(candidate) > 0,
                  let candidateUID = stringProperty(candidate, kAudioDevicePropertyDeviceUID) else {
                return nil
            }
            let candidateName = stringProperty(candidate, kAudioObjectPropertyName) ?? candidateUID
            return isMixerDevice(uid: candidateUID, name: candidateName) ? nil : candidateUID
        }.first
    }

    static func isMixerDevice(uid: String, name: String) -> Bool {
        uid.hasPrefix("ControlBox-mix-") || name.hasPrefix("Control Box Mix")
    }

    public static func setDefaultOutput(uid: String) {
        guard let device = device(uid: uid) else { return }
        var value = device
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        _ = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            size,
            &value
        )
    }

    public static func volume() -> Double {
        SystemVolume.current()
    }

    public static func setVolume(_ value: Double) {
        guard let device = defaultOutputDevice() else { return }
        let clamped = min(max(value, 0), 1)
        setVolume(clamped, on: device)
        if clamped > 0.0001 {
            setMuted(false, on: device)
        }
    }

    public static func isMuted() -> Bool {
        guard let device = defaultOutputDevice() else { return false }
        return muted(device)
    }

    public static func setMuted(_ muted: Bool) {
        guard let device = defaultOutputDevice() else { return }
        setMuted(muted, on: device)
    }

    static func defaultOutputDevice() -> AudioDeviceID? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &device
        )
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    static func device(uid: String) -> AudioDeviceID? {
        deviceIDs().first { stringProperty($0, kAudioDevicePropertyDeviceUID) == uid }
    }

    static func nominalSampleRate(_ device: AudioDeviceID) -> Double {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else {
            return 48_000
        }
        return value > 0 ? value : 48_000
    }

    private static func deviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        ) == noErr, size > 0 else {
            return []
        }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &devices
        ) == noErr else {
            return []
        }
        return devices
    }

    private static func outputStreamCount(_ device: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr else { return 0 }
        return Int(size) / MemoryLayout<AudioStreamID>.size
    }

    private static func muted(_ device: AudioDeviceID) -> Bool {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else {
            return false
        }
        return value != 0
    }

    private static func setMuted(_ muted: Bool, on device: AudioDeviceID) {
        var value: UInt32 = muted ? 1 : 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        let size = UInt32(MemoryLayout<UInt32>.size)
        _ = AudioObjectSetPropertyData(device, &address, 0, nil, size, &value)
    }

    private static func setVolume(_ value: Double, on device: AudioDeviceID) {
        let clamped = Float32(min(max(value, 0), 1))
        if setScalar(device, selector: 0x766D7663, value: clamped) { return }
        _ = setScalar(device, selector: kAudioDevicePropertyVolumeScalar, value: clamped, element: 1)
        _ = setScalar(device, selector: kAudioDevicePropertyVolumeScalar, value: clamped, element: 2)
    }

    private static func setScalar(
        _ device: AudioDeviceID,
        selector: AudioObjectPropertySelector,
        value: Float32,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> Bool {
        var next = value
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        let size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectSetPropertyData(device, &address, 0, nil, size, &next) == noErr
    }

    private static func stringProperty(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString?
        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
        guard status == noErr, let value else { return nil }
        return value as String
    }
}
