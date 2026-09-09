import Foundation

/// Stable HID++ feature IDs. A device reports the live 8-bit index for each
/// supported feature during its IRoot / Feature Set handshake.
public enum LogitechHIDPPFeatureID {
    public static let featureSet: UInt16 = 0x0001
    public static let deviceInformation: UInt16 = 0x0003
    public static let deviceName: UInt16 = 0x0005
    public static let friendlyName: UInt16 = 0x0007
    public static let batteryStatus: UInt16 = 0x1000
    public static let batteryVoltage: UInt16 = 0x1001
    public static let unifiedBattery: UInt16 = 0x1004
    public static let changeHost: UInt16 = 0x1814
    public static let hostsInformation: UInt16 = 0x1815
    public static let backlight2: UInt16 = 0x1982
    public static let hapticFeedback: UInt16 = 0x19B0
    public static let forceSensing: UInt16 = 0x19C0
    public static let reprogrammableControlsV4: UInt16 = 0x1B04
    public static let smartShift: UInt16 = 0x2110
    public static let smartShiftEnhanced: UInt16 = 0x2111
    public static let highResolutionWheel: UInt16 = 0x2121
    public static let thumbWheel: UInt16 = 0x2150
    public static let adjustableDPI: UInt16 = 0x2201
    public static let extendedAdjustableDPI: UInt16 = 0x2202
    public static let pointerScale: UInt16 = 0x2205
}

public struct LogitechHIDPPCapabilities: Equatable, Codable, Sendable {
    public var deviceInformation: Bool
    public var deviceName: Bool
    public var friendlyName: Bool
    public var battery: Bool
    public var changeHost: Bool
    public var hostsInformation: Bool
    public var backlight: Bool
    public var hapticFeedback: Bool
    public var forceSensing: Bool
    public var reprogrammableControls: Bool
    public var smartShift: Bool
    public var highResolutionWheel: Bool
    public var thumbWheel: Bool
    public var adjustableDPI: Bool
    public var pointerScale: Bool

    public static let none = LogitechHIDPPCapabilities(
        deviceInformation: false,
        deviceName: false,
        friendlyName: false,
        battery: false,
        changeHost: false,
        hostsInformation: false,
        backlight: false,
        hapticFeedback: false,
        forceSensing: false,
        reprogrammableControls: false,
        smartShift: false,
        highResolutionWheel: false,
        thumbWheel: false,
        adjustableDPI: false,
        pointerScale: false
    )

    public var easySwitch: Bool {
        changeHost || hostsInformation
    }
}

public struct LogitechHIDPPFeatureCatalog: Equatable, Codable, Sendable {
    public private(set) var indices: [UInt16: UInt8]

    public init(indices: [UInt16: UInt8] = [:]) {
        self.indices = indices
    }

    public subscript(featureID: UInt16) -> UInt8? {
        get { indices[featureID] }
        set {
            if let newValue, newValue != 0 {
                indices[featureID] = newValue
            } else {
                indices.removeValue(forKey: featureID)
            }
        }
    }

    public mutating func removeAll() {
        indices.removeAll()
    }

    public var capabilities: LogitechHIDPPCapabilities {
        let has = { (id: UInt16) in indices[id] != nil }
        let hasAny = { (ids: [UInt16]) in ids.contains(where: has) }
        return LogitechHIDPPCapabilities(
            deviceInformation: has(LogitechHIDPPFeatureID.deviceInformation),
            deviceName: has(LogitechHIDPPFeatureID.deviceName),
            friendlyName: has(LogitechHIDPPFeatureID.friendlyName),
            battery: has(LogitechHIDPPFeatureID.unifiedBattery),
            changeHost: has(LogitechHIDPPFeatureID.changeHost),
            hostsInformation: has(LogitechHIDPPFeatureID.hostsInformation),
            backlight: has(LogitechHIDPPFeatureID.backlight2),
            hapticFeedback: has(LogitechHIDPPFeatureID.hapticFeedback),
            forceSensing: has(LogitechHIDPPFeatureID.forceSensing),
            reprogrammableControls: (0x1B00...0x1B04).contains(where: has),
            smartShift: hasAny([
                LogitechHIDPPFeatureID.smartShift,
                LogitechHIDPPFeatureID.smartShiftEnhanced
            ]),
            highResolutionWheel: has(LogitechHIDPPFeatureID.highResolutionWheel),
            thumbWheel: has(LogitechHIDPPFeatureID.thumbWheel),
            adjustableDPI: has(LogitechHIDPPFeatureID.adjustableDPI),
            pointerScale: has(LogitechHIDPPFeatureID.pointerScale)
        )
    }
}

public struct LogitechHIDPPControlDescriptor: Equatable, Codable, Sendable, Identifiable {
    public var id: UInt16 { cid }
    public var cid: UInt16
    public var task: UInt16
    public var isDivertable: Bool
    public var supportsRawXY: Bool
    public var supportsForceRawXY: Bool

    public init(
        cid: UInt16,
        task: UInt16,
        isDivertable: Bool,
        supportsRawXY: Bool,
        supportsForceRawXY: Bool
    ) {
        self.cid = cid
        self.task = task
        self.isDivertable = isDivertable
        self.supportsRawXY = supportsRawXY
        self.supportsForceRawXY = supportsForceRawXY
    }

    public init(cid: UInt16, task: UInt16, flagsLow: UInt8, flagsHigh: UInt8) {
        self.init(
            cid: cid,
            task: task,
            isDivertable: flagsLow & 0x20 != 0,
            supportsRawXY: flagsHigh & 0x01 != 0,
            supportsForceRawXY: flagsHigh & 0x02 != 0
        )
    }

    public var canOwnGestures: Bool {
        isDivertable && supportsRawXY
    }
}
