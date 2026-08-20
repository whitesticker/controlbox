import CoreAudio
import Foundation

enum AudioInputProbe {
    static func inputDeviceNames() -> [String] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        ) == noErr else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &devices
        ) == noErr else {
            return []
        }

        return devices.compactMap { device in
            guard hasInputStreams(device) else { return nil }
            return deviceName(device)
        }
    }

    private static func hasInputStreams(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var streamSize: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &streamSize) == noErr && streamSize > 0
    }

    private static func deviceName(_ device: AudioDeviceID) -> String? {
        var name: CFString = "" as CFString
        var nameSize = UInt32(MemoryLayout<CFString>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = withUnsafeMutablePointer(to: &name) { pointer in
            AudioObjectGetPropertyData(device, &address, 0, nil, &nameSize, pointer)
        }
        guard status == noErr else { return nil }
        return name as String
    }
}
