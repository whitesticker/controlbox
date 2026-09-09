import Foundation
import ControlBoxCore
import IOKit.hid

/// Read-only discovery for Logitech HID++ endpoints. It matches only the
/// vendor collections that carry HID++ reports; it never matches or opens the
/// standard mouse/keyboard collections for input capture.
enum LogitechHIDPPDiscovery {
    static let receiverProductIDs = LogitechHIDPP2.knownReceiverProductIDs

    struct Collection: Equatable, Sendable {
        var usagePage: Int
        var usage: Int
        var longOnly: Bool
    }

    static let collections = [
        Collection(usagePage: 0xFF00, usage: 0x0002, longOnly: false),
        Collection(usagePage: 0xFF43, usage: 0x0202, longOnly: true),
        Collection(usagePage: 0xFF43, usage: 0x0602, longOnly: false)
    ]

    private static let claimLock = NSLock()
    private static var claims: [String: UUID] = [:]

    static func hidManagerMatches() -> [[String: Any]] {
        collections.map { collection in
            [
                kIOHIDVendorIDKey as String: DeviceSupport.logitechVendorID,
                kIOHIDDeviceUsagePageKey as String: collection.usagePage,
                kIOHIDDeviceUsageKey as String: collection.usage
            ]
        }
    }

    static func collection(for device: IOHIDDevice) -> Collection? {
        let vendor = intProperty(kIOHIDVendorIDKey, device)
        let product = intProperty(kIOHIDProductIDKey, device)
        let page = intProperty(kIOHIDPrimaryUsagePageKey, device)
        let usage = intProperty(kIOHIDPrimaryUsageKey, device)
        let outputSize = intProperty(kIOHIDMaxOutputReportSizeKey, device)
        guard vendor == DeviceSupport.logitechVendorID,
              !receiverProductIDs.contains(product),
              outputSize >= 20
        else {
            return nil
        }
        return collections.first {
            $0.usagePage == page && $0.usage == usage
        }
    }

    static func isUnknownMouseEndpoint(_ device: IOHIDDevice) -> Bool {
        guard collection(for: device) != nil else { return false }
        let productID = intProperty(kIOHIDProductIDKey, device)
        guard !DeviceSupport.mxMasterProductIDs.contains(productID),
              !DeviceSupport.mxKeyboardProductIDs.contains(productID)
        else {
            return false
        }
        return connectedMouseProductIDs().contains(productID)
    }

    static func claim(_ device: IOHIDDevice, owner: UUID) -> Bool {
        let key = endpointKey(for: device)
        claimLock.lock()
        defer { claimLock.unlock() }
        if let current = claims[key] {
            return current == owner
        }
        claims[key] = owner
        return true
    }

    static func release(_ device: IOHIDDevice, owner: UUID) {
        let key = endpointKey(for: device)
        claimLock.lock()
        defer { claimLock.unlock() }
        if claims[key] == owner {
            claims[key] = nil
        }
    }

    /// Correlates a vendor HID++ endpoint with a standard mouse collection by
    /// product ID. The standard collection is enumerated only; device readers
    /// never open it or register input callbacks on it.
    static func connectedMouseProductIDs() -> Set<Int> {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey as String: DeviceSupport.logitechVendorID,
            kIOHIDDeviceUsagePageKey as String: 0x01,
            kIOHIDDeviceUsageKey as String: 0x02
        ] as CFDictionary)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }
        guard let copied = IOHIDManagerCopyDevices(manager) else { return [] }
        var productIDs = Set<Int>()
        for case let device as IOHIDDevice in (copied as NSSet) {
            let productID = intProperty(kIOHIDProductIDKey, device)
            if productID != 0,
               !receiverProductIDs.contains(productID) {
                productIDs.insert(productID)
            }
        }
        return productIDs
    }

    private static func intProperty(_ key: String, _ device: IOHIDDevice) -> Int {
        (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? 0
    }

    static func endpointKey(for device: IOHIDDevice) -> String {
        let productID = intProperty(kIOHIDProductIDKey, device)
        let location = intProperty(kIOHIDLocationIDKey, device)
        let address = DeviceIdentity.fromHID(device)
        if DeviceIdentity.isConcrete(address) {
            return "\(productID):\(address.lowercased())"
        }
        if location != 0 {
            return "\(productID):loc-\(location)"
        }
        return "\(productID):object-\(ObjectIdentifier(device).hashValue)"
    }
}
