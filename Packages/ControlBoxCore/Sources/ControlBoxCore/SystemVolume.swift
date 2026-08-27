import CoreAudio
import Foundation

enum SystemVolume {
    private static let virtualMainVolume: AudioObjectPropertySelector = 0x766D7663 // 'vmvc'

    @discardableResult
    static func adjust(by delta: Double) -> Double? {
        guard abs(delta) > 0.00005, let device = defaultOutputDevice() else { return nil }
        let next = min(max(volume(of: device) + delta, 0), 1)
        setVolume(next, on: device)
        if next > 0.0001 {
            setMuted(false, on: device)
        }
        return next
    }

    static func current() -> Double {
        guard let device = defaultOutputDevice() else { return 0 }
        return volume(of: device)
    }

    private static func defaultOutputDevice() -> AudioDeviceID? {
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

    private static func volume(of device: AudioDeviceID) -> Double {
        if let value = scalar(device, selector: Self.virtualMainVolume) {
            return value
        }
        let channels = [UInt32(1), UInt32(2)].compactMap {
            scalar(device, selector: kAudioDevicePropertyVolumeScalar, element: $0)
        }
        guard !channels.isEmpty else { return 0 }
        return channels.reduce(0, +) / Double(channels.count)
    }

    private static func setVolume(_ value: Double, on device: AudioDeviceID) {
        let clamped = Float32(min(max(value, 0), 1))
        if setScalar(device, selector: Self.virtualMainVolume, value: clamped) {
            return
        }
        _ = setScalar(device, selector: kAudioDevicePropertyVolumeScalar, value: clamped, element: 1)
        _ = setScalar(device, selector: kAudioDevicePropertyVolumeScalar, value: clamped, element: 2)
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

    private static func scalar(
        _ device: AudioDeviceID,
        selector: AudioObjectPropertySelector,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> Double? {
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr ? Double(value) : nil
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
}
