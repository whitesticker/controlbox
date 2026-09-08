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
    /// Sidebar title. Hardware / Bluetooth name stays in `name` for identity.
    var customName: String? = nil

    var displayName: String {
        let custom = customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return custom.isEmpty ? name : custom
    }

    var isAppleTVRemote: Bool { kind == .appleTVRemote }
    var isMXMaster: Bool { kind.isMXMaster }
    var isMXKeyboard: Bool { kind.isMXKeyboard }
    var isGamepad: Bool { kind.isGamepad }
    var usesAppProfiles: Bool { isMXMaster || isGamepad || isAppleTVRemote }

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

    var mxDefaultProfile: MappingProfile {
        profiles.first(where: \.treatsAsMXDefault)
            ?? profiles.first { $0.appCategory == nil && ($0.frontmostAppBundleID ?? "").isEmpty }
            ?? selectedProfile
    }

    mutating func ensureAppProfiles() {
        guard usesAppProfiles else { return }
        if !profiles.contains(where: \.treatsAsMXDefault) {
            if let index = profiles.firstIndex(where: { $0.id == selectedProfileID }) {
                profiles[index].isMXDefault = true
                profiles[index].appCategory = nil
                profiles[index].frontmostAppBundleID = nil
                profiles[index].name = "Default"
            } else if var first = profiles.first {
                first.isMXDefault = true
                first.appCategory = nil
                first.frontmostAppBundleID = nil
                first.name = "Default"
                profiles[0] = first
                selectedProfileID = first.id
            }
        }
        let removedIDs = Set(profiles.filter { $0.appCategory != nil && ($0.frontmostAppBundleID ?? "").isEmpty }.map(\.id))
        profiles.removeAll { removedIDs.contains($0.id) }
        if removedIDs.contains(selectedProfileID) {
            selectedProfileID = mxDefaultProfile.id
        }
    }

    mutating func ensureControllerDeviceSettings() {
        guard isGamepad || isAppleTVRemote, !profiles.isEmpty else { return }
        let deviceSettings = mxDefaultProfile
        for index in profiles.indices {
            profiles[index].leftStick = deviceSettings.leftStick
            profiles[index].rightStick = deviceSettings.rightStick
            profiles[index].dualSenseTouchpad = deviceSettings.dualSenseTouchpad
            profiles[index].appleTVClickpad = deviceSettings.appleTVClickpad
            profiles[index].appleTVWheel = deviceSettings.appleTVWheel
            profiles[index].pointerAcceleration = deviceSettings.pointerAcceleration
            profiles[index].pointerAccelerationAmount = deviceSettings.pointerAccelerationAmount
            profiles[index].stickyTargeting = deviceSettings.stickyTargeting
            profiles[index].pointerSpeed = deviceSettings.pointerSpeed
            profiles[index].wheelScrollSpeed = deviceSettings.wheelScrollSpeed
            profiles[index].thumbScrollSpeed = deviceSettings.thumbScrollSpeed
            profiles[index].naturalScrolling = deviceSettings.naturalScrolling
            profiles[index].scrollAcceleration = deviceSettings.scrollAcceleration
            profiles[index].scrollAccelerationAmount = deviceSettings.scrollAccelerationAmount
            profiles[index].dualSenseTabRepeatInterval = deviceSettings.dualSenseTabRepeatInterval
        }
    }

    func appScopeProfiles() -> [MappingProfile] {
        let defaultProfile = mxDefaultProfile
        var ordered: [MappingProfile] = [defaultProfile]
        ordered.append(contentsOf: profiles.filter { ($0.frontmostAppBundleID ?? "").isEmpty == false }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        ordered.append(contentsOf: profiles.filter(\.isMXLeftoverNamedProfile)
            .filter { $0.id != defaultProfile.id }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        return ordered
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
            profile.sensorDPI = 4000
        }
        var record = DeviceRecord(
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
        record.ensureAppProfiles()
        record.ensureControllerDeviceSettings()
        return record
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
