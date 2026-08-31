import Foundation
import IOKit.hid

/// MX Mechanical and MX Mechanical Mini. Same HID++ feature set
/// (BACKLIGHT2, UNIFIED BATTERY). Match by product ID, not a generic
/// Logitech vendor page. Bolt receiver `0xC548` is never this keyboard.
enum MXMechanicalSupport {
    static let mechanicalProductIDs: Set<Int> = [0xB366]
    static let miniProductIDs: Set<Int> = [0xB367]
    static let productIDs: Set<Int> = mechanicalProductIDs.union(miniProductIDs)

    static func kind(productID: Int, product: String) -> DeviceKind {
        if miniProductIDs.contains(productID) { return .logitechMXMechanicalMini }
        if mechanicalProductIDs.contains(productID) { return .logitechMXMechanical }
        return kind(from: product)
    }

    static func kind(from product: String) -> DeviceKind {
        let lowered = product.lowercased()
        if lowered.contains("mini") { return .logitechMXMechanicalMini }
        return .logitechMXMechanical
    }

    static func kind(of device: IOHIDDevice) -> DeviceKind {
        let product = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? ""
        let productID = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue ?? 0
        return kind(productID: productID, product: product)
    }

    static func matches(productID: Int, product: String) -> Bool {
        if productIDs.contains(productID) { return true }
        return DeviceSupport.isMXMechanicalName(product)
    }

    static func matches(_ device: IOHIDDevice) -> Bool {
        let product = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? ""
        let productID = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue ?? 0
        return matches(productID: productID, product: product)
    }

    static func hidManagerMatches() -> [[String: Any]] {
        productIDs.map { productID in
            [
                kIOHIDVendorIDKey as String: DeviceSupport.logitechVendorID,
                kIOHIDProductIDKey as String: productID
            ]
        }
    }
}
