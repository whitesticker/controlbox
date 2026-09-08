import Foundation
import ControlBoxCore

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
    var unitID: UInt32?
    var wirelessProductID: Int?

    var isAppleTVRemote: Bool { kind == .appleTVRemote }
    var isMXMaster: Bool { kind.isMXMaster }
    var isMXKeyboard: Bool { kind.isMXKeyboard }

    var hapticFeedbackEnabled: Bool {
        hapticFeedback ?? (kind == .dualSense || kind == .dualSenseEdge)
    }

    var selectedProfile: MappingProfile {
        profiles.first { $0.id == selectedProfileID }
            ?? profiles.first
            ?? MappingProfile.makeDefault(
                isAppleTVRemote: isAppleTVRemote,
                isMXMaster: isMXMaster,
                isMXKeyboard: isMXKeyboard
            )
    }

    var logitechKey: LogitechDeviceKey {
        LogitechDeviceKey(
            name: name,
            kind: kind,
            address: address,
            unitID: unitID,
            wirelessProductID: wirelessProductID,
            connection: DeviceIdentity.isBoltWPID(address) || id.hasPrefix("bolt-")
                ? .bolt
                : .bluetooth
        )
    }

    static func make(from device: ConnectedBluetoothDevice, remembered: Bool = false) -> DeviceRecord {
        var profile = MappingProfile.makeDefault(
            isAppleTVRemote: device.deviceKind == .appleTVRemote,
            isMXMaster: device.deviceKind.isMXMaster,
            isMXKeyboard: device.deviceKind.isMXKeyboard
        )
        if device.deviceKind.isMXMaster3Family {
            profile.summary = "Gesture button is Gestures. Back and Forward are browser buttons."
        }
        if device.deviceKind == .logitechMXMaster4 {
            profile.hapticGestureSpeed = 0.61
            profile.sensorDPI = 4000
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
            selectedProfileID: profile.id,
            unitID: device.unitID,
            wirelessProductID: device.wirelessProductID
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
    var connection: DeviceConnection = .bluetooth
    var unitID: UInt32? = nil
    var wirelessProductID: Int? = nil

    var glyph: String { kind.paneGlyph }

    var isBoltConnection: Bool { connection == .bolt }

    var logitechKey: LogitechDeviceKey {
        LogitechDeviceKey(
            name: name,
            kind: kind,
            address: address,
            unitID: unitID,
            wirelessProductID: wirelessProductID,
            connection: connection
        )
    }

    var statusTitle: String {
        if isConnected { return "Connected" }
        return "Not connected"
    }

    func rowCaption(showBrand: Bool) -> String {
        if isConnected {
            return "\(kind.brand) · \(connection.title)"
        }
        if showBrand { return kind.brand }
        return statusTitle
    }
}
