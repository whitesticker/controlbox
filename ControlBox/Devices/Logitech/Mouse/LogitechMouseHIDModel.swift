import Foundation
import IOKit.hid
import ControlBoxCore

/// Data-only exceptions for Logitech mice. The reader and HID++ feature
/// clients are shared; entries here never implement behavior.
struct LogitechMouseHIDModel {
    var kind: DeviceKind
    var acceptedKinds: Set<DeviceKind>
    var productIDs: Set<Int>
    var gestureCID: UInt16
    var extraButtonCIDs: Set<UInt16>
    var nativeHapticButtonBit: UInt8?
    var nativeMouseButtonBytes: Int
    var forceSensingFeature: UInt16?
    var forceThreshold: UInt16?
    var analyticsReportingFlags: UInt8
    var tryShortHIDPPReport: Bool
    var gestureControlTitle: String
    var lookingStatus: String
    var requiresMXMasterName: Bool
    var enablesHiddenFeatures: Bool
    var requiresGestureCID: Bool
    var divertsUnknownButtons: Bool
}

/// One capability-driven Logitech mouse registry, following OpenLogi's shape:
/// identify the endpoint, probe its feature/control tables, then apply only
/// compact data quirks that firmware cannot describe.
enum LogitechMouseRegistry {
    static let master3ProductIDs: Set<Int> = [0xB023, 0x4082]
    static let master3SProductIDs: Set<Int> = [0xB034, 0xB043]
    static let master3FamilyProductIDs = master3ProductIDs.union(master3SProductIDs)
    static let master4ProductIDs: Set<Int> = [0xB042, 0x4069]
    static let knownProductIDs = master3FamilyProductIDs.union(master4ProductIDs)

    private static let commonButtonCIDs: Set<UInt16> = [
        0x0052,
        0x0053, 0x0054, 0x0056,
        0x005B, 0x005D,
        0x00C3, 0x00C4,
        0x00D0, 0x00ED, 0x00FD
    ]

    static let generic = LogitechMouseHIDModel(
        kind: .logitechMouse,
        acceptedKinds: [.logitechMouse],
        productIDs: [],
        gestureCID: 0x00C3,
        extraButtonCIDs: commonButtonCIDs,
        nativeHapticButtonBit: nil,
        nativeMouseButtonBytes: 1,
        forceSensingFeature: nil,
        forceThreshold: nil,
        analyticsReportingFlags: 0,
        tryShortHIDPPReport: false,
        gestureControlTitle: "Gesture button",
        lookingStatus: "Looking for a Logitech mouse…",
        requiresMXMasterName: false,
        enablesHiddenFeatures: false,
        requiresGestureCID: false,
        divertsUnknownButtons: true
    )

    private static let master3Family = LogitechMouseHIDModel(
        kind: .logitechMXMaster3S,
        acceptedKinds: [.logitechMXMaster3, .logitechMXMaster3S],
        productIDs: master3FamilyProductIDs,
        gestureCID: 0x00C3,
        extraButtonCIDs: [0x0053, 0x0054, 0x0056, 0x00C4, 0x00D0],
        nativeHapticButtonBit: nil,
        nativeMouseButtonBytes: 2,
        forceSensingFeature: nil,
        forceThreshold: nil,
        analyticsReportingFlags: 0,
        tryShortHIDPPReport: false,
        gestureControlTitle: "Gesture button",
        lookingStatus: "Looking for an MX Master 3 / 3S…",
        requiresMXMasterName: true,
        enablesHiddenFeatures: true,
        requiresGestureCID: true,
        divertsUnknownButtons: true
    )

    private static let master4 = LogitechMouseHIDModel(
        kind: .logitechMXMaster4,
        acceptedKinds: [.logitechMXMaster4, .logitechMXMaster],
        productIDs: master4ProductIDs,
        gestureCID: 0x01A0,
        extraButtonCIDs: [
            0x0053, 0x0054, 0x0056, 0x00C3, 0x00C4,
            0x00D0, 0x00ED, 0x00FD
        ],
        nativeHapticButtonBit: 0x40,
        nativeMouseButtonBytes: 1,
        forceSensingFeature: 0x19C0,
        forceThreshold: 0x15A3,
        analyticsReportingFlags: 0x03,
        tryShortHIDPPReport: true,
        gestureControlTitle: "Haptic button",
        lookingStatus: "Looking for an MX Master 4…",
        requiresMXMasterName: true,
        enablesHiddenFeatures: true,
        requiresGestureCID: true,
        divertsUnknownButtons: true
    )

    static func kind(productID: Int, product: String) -> DeviceKind {
        if master3SProductIDs.contains(productID) { return .logitechMXMaster3S }
        if master3ProductIDs.contains(productID) { return .logitechMXMaster3 }
        if master4ProductIDs.contains(productID) { return .logitechMXMaster4 }
        let lowered = product.lowercased()
        if lowered.contains("3s") || lowered.contains("3 s") {
            return .logitechMXMaster3S
        }
        if lowered.contains("master 3") { return .logitechMXMaster3 }
        if lowered.contains("master 4") { return .logitechMXMaster4 }
        return .logitechMouse
    }

    static func model(productID: Int, product: String, kind: DeviceKind? = nil) -> LogitechMouseHIDModel {
        if master3FamilyProductIDs.contains(productID)
            || kind?.isMXMaster3Family == true {
            return master3Family
        }
        if master4ProductIDs.contains(productID)
            || kind == .logitechMXMaster4
            || kind == .logitechMXMaster {
            return master4
        }
        return generic
    }

    static func model(of device: IOHIDDevice) -> LogitechMouseHIDModel {
        model(
            productID: intProperty(kIOHIDProductIDKey, device),
            product: stringProperty(kIOHIDProductKey, device) ?? ""
        )
    }

    static func resolvedKind(of device: IOHIDDevice) -> DeviceKind {
        kind(
            productID: intProperty(kIOHIDProductIDKey, device),
            product: stringProperty(kIOHIDProductKey, device) ?? ""
        )
    }

    static func matches(_ device: IOHIDDevice) -> Bool {
        let vendorID = intProperty(kIOHIDVendorIDKey, device)
        let productID = intProperty(kIOHIDProductIDKey, device)
        guard vendorID == DeviceSupport.logitechVendorID,
              !LogitechHIDPPDiscovery.receiverProductIDs.contains(productID),
              !DeviceSupport.mxKeyboardProductIDs.contains(productID)
        else {
            return false
        }
        return knownProductIDs.contains(productID)
            || LogitechHIDPPDiscovery.isUnknownMouseEndpoint(device)
    }

    static func hidManagerMatches() -> [[String: Any]] {
        let known = knownProductIDs.map { productID in
            [
                kIOHIDVendorIDKey as String: DeviceSupport.logitechVendorID,
                kIOHIDProductIDKey as String: productID
            ]
        }
        return known + LogitechHIDPPDiscovery.hidManagerMatches()
    }

    private static func stringProperty(_ key: String, _ device: IOHIDDevice) -> String? {
        IOHIDDeviceGetProperty(device, key as CFString) as? String
    }

    private static func intProperty(_ key: String, _ device: IOHIDDevice) -> Int {
        (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? 0
    }
}

extension DeviceKind {
    var mxGestureControlTitle: String {
        switch self {
        case .logitechMXMaster3, .logitechMXMaster3S, .logitechMouse:
            return DeviceButton.mxSide.title
        default:
            return DeviceButton.mxHaptic.title
        }
    }

    var isMXMaster3Family: Bool {
        self == .logitechMXMaster3 || self == .logitechMXMaster3S
    }
}
