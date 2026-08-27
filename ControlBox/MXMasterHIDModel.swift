import Foundation
import IOKit.hid

/// Per-model HID++ matching and control IDs. Shared transport / gesture code
/// lives in `LogitechMXMasterReader`; the 3/3S family and 4 stay separate.
struct MXMasterHIDModel {
    var kind: DeviceKind
    var acceptedKinds: Set<DeviceKind>
    var productIDs: Set<Int>
    var hidppUsagePages: [Int]
    var gestureCID: UInt16
    var extraButtonCIDs: Set<UInt16>
    var nativeHapticButtonBit: UInt8?
    var nativeMouseButtonBytes: Int
    var forceSensingFeature: UInt16?
    var forceThreshold: UInt16?
    var analyticsReportingFlags: UInt8
    /// BLE 3S / MX4 have no short report `0x10`. Sending it can wedge HID++.
    var tryShortHIDPPReport: Bool
    var gestureControlTitle: String
    var lookingStatus: String

    func matches(productID: Int, product: String) -> Bool {
        if productIDs.contains(productID) { return true }
        return acceptedKinds.contains(DeviceSupport.mxKind(from: product))
    }

    func matches(_ device: IOHIDDevice) -> Bool {
        let product = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? ""
        let productID = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue ?? 0
        return matches(productID: productID, product: product)
    }

    func resolvedKind(of device: IOHIDDevice) -> DeviceKind {
        if acceptedKinds.contains(.logitechMXMaster3) || acceptedKinds.contains(.logitechMXMaster3S) {
            return MXMaster3Support.kind(of: device)
        }
        return kind
    }

    /// Product-ID matches only. Never a generic Logitech vendor page (that
    /// opened Bolt receivers and a second mouse).
    func hidManagerMatches() -> [[String: Any]] {
        productIDs.map { productID in
            [
                kIOHIDVendorIDKey as String: DeviceSupport.logitechVendorID,
                kIOHIDProductIDKey as String: productID
            ]
        }
    }
}

enum MXMasterHIDDiscovery {
    static let boltReceiverProductID = 0xC548

    static func connectedProductIDs() -> Set<Int> {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        var matches: [[String: Any]] = []
        for productID in DeviceSupport.mxMasterProductIDs {
            matches.append([
                kIOHIDVendorIDKey as String: DeviceSupport.logitechVendorID,
                kIOHIDProductIDKey as String: productID
            ])
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }
        guard let copied = IOHIDManagerCopyDevices(manager) else { return [] }
        var ids = Set<Int>()
        for case let device as IOHIDDevice in (copied as NSSet) {
            let productID = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue ?? 0
            if productID != 0, productID != boltReceiverProductID {
                ids.insert(productID)
            }
        }
        return ids
    }

    static func activeModel() -> MXMasterHIDModel {
        let ids = connectedProductIDs()
        if ids.contains(where: { MXMaster3Support.productIDs.contains($0) }) {
            return MXMaster3Support.model
        }
        if ids.contains(where: { MXMaster4Support.productIDs.contains($0) }) {
            return MXMaster4Support.model
        }
        return MXMaster3Support.model
    }
}

extension DeviceKind {
    var mxGestureControlTitle: String {
        switch self {
        case .logitechMXMaster3, .logitechMXMaster3S:
            return "Gesture"
        default:
            return "Haptic"
        }
    }

    var isMXMaster3Family: Bool {
        self == .logitechMXMaster3 || self == .logitechMXMaster3S
    }
}
