import Foundation
import IOKit.hid

/// MX Master 3 and 3S share one HID++ module. logiops/Solaar list the same
/// Reprog V4 CIDs on both: left/right/middle, back `0x0053`, forward `0x0056`,
/// gesture `0x00C3`, smart shift `0x00C4`, thumb wheel `0x00D7`. Neither has
/// the Master 4 haptic pad (`0x01A0`) or Force Sensing.
///
/// What differs is only transport: 3 is Unifying `0x4082` / BLE `0xB023`;
/// 3S is Bolt `0xB043` / BLE `0xB034`. BLE nests HID++ on the mouse device
/// (page `0xFF43`, report `0x11`). Match by product ID, not a generic vendor
/// page. Bolt receiver `0xC548` is never this mouse.
enum MXMaster3Support {
    static let master3ProductIDs: Set<Int> = [0xB023, 0x4082]
    static let master3SProductIDs: Set<Int> = [0xB034, 0xB043]
    static let productIDs: Set<Int> = master3ProductIDs.union(master3SProductIDs)
    static let hidppUsagePages = [0xFF43, 0xFF00]
    static let gestureCID: UInt16 = 0x00C3
    static let extraButtonCIDs: Set<UInt16> = [
        0x0053, 0x0054, 0x0056, 0x00C4, 0x00D0
    ]

    static let model = MXMasterHIDModel(
        kind: .logitechMXMaster3S,
        acceptedKinds: [.logitechMXMaster3, .logitechMXMaster3S],
        productIDs: productIDs,
        hidppUsagePages: hidppUsagePages,
        gestureCID: gestureCID,
        extraButtonCIDs: extraButtonCIDs,
        nativeHapticButtonBit: nil,
        nativeMouseButtonBytes: 2,
        forceSensingFeature: nil,
        forceThreshold: nil,
        analyticsReportingFlags: 0,
        tryShortHIDPPReport: false,
        gestureControlTitle: "Gesture",
        lookingStatus: "Looking for an MX Master 3 / 3S…"
    )

    static func kind(productID: Int, product: String) -> DeviceKind {
        if master3SProductIDs.contains(productID) { return .logitechMXMaster3S }
        if master3ProductIDs.contains(productID) { return .logitechMXMaster3 }
        return DeviceSupport.mxKind(from: product)
    }

    static func kind(of device: IOHIDDevice) -> DeviceKind {
        let product = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? ""
        let productID = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue ?? 0
        let classified = kind(productID: productID, product: product)
        return model.acceptedKinds.contains(classified) ? classified : .logitechMXMaster3S
    }
}
