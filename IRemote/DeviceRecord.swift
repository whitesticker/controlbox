import Foundation
import IRemoteControl

struct DeviceRecord: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var address: String
    var kind: DeviceKind
    var remembered: Bool
    var controlEnabled: Bool
    var controlWhileFocused: Bool
    var hapticFeedback: Bool?
    var profiles: [MappingProfile]
    var selectedProfileID: String

    var isAppleTVRemote: Bool { kind == .appleTVRemote }
    var isMXMaster: Bool { kind.isMXMaster }

    var hapticFeedbackEnabled: Bool {
        hapticFeedback ?? (kind == .dualSense || kind == .dualSenseEdge)
    }

    var selectedProfile: MappingProfile {
        profiles.first { $0.id == selectedProfileID }
            ?? profiles.first
            ?? MappingProfile.makeDefault(isAppleTVRemote: isAppleTVRemote, isMXMaster: isMXMaster)
    }

    static func make(from device: ConnectedBluetoothDevice, remembered: Bool = false) -> DeviceRecord {
        var profile = MappingProfile.makeDefault(
            isAppleTVRemote: device.deviceKind == .appleTVRemote,
            isMXMaster: device.deviceKind.isMXMaster
        )
        if device.deviceKind.isMXMaster3Family {
            profile.summary = "Gesture button is Gestures. Back and Forward are browser buttons."
        }
        if device.deviceKind == .logitechMXMaster4 {
            profile.hapticGestureSpeed = 0.61
        }
        return DeviceRecord(
            id: device.id,
            name: device.name,
            address: device.address,
            kind: device.deviceKind,
            remembered: remembered,
            controlEnabled: false,
            controlWhileFocused: false,
            hapticFeedback: device.deviceKind == .dualSense || device.deviceKind == .dualSenseEdge,
            profiles: [profile],
            selectedProfileID: profile.id
        )
    }
}

struct SidebarDevice: Identifiable, Hashable {
    var id: String
    var name: String
    var address: String
    var kind: DeviceKind
    var isConnected: Bool
    var controlEnabled: Bool
    var remembered: Bool

    var symbol: String {
        kind == .appleTVRemote
            ? "appletvremote.gen4.fill"
            : kind.isMXMaster ? "computermouse.fill" : "gamecontroller.fill"
    }

    var statusTitle: String {
        if isConnected { return "Connected" }
        return "Not connected"
    }
}
