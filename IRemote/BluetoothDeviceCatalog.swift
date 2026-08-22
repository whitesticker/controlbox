import Foundation
import GameController
import IOKit.hid

enum DeviceKind: String, Codable, Equatable {
    case dualSense
    case dualSenseEdge
    case appleTVRemote
    case logitechMXMaster
    case unsupported

    var isSupported: Bool { self != .unsupported }

    var title: String {
        switch self {
        case .dualSense: return "PS5 DualSense"
        case .dualSenseEdge: return "PS5 DualSense Edge"
        case .appleTVRemote: return "Apple TV Remote"
        case .logitechMXMaster: return "MX Master"
        case .unsupported: return "Not supported yet"
        }
    }
}

struct ConnectedBluetoothDevice: Identifiable, Equatable {
    var id: String
    var name: String
    var address: String
    var deviceKind: DeviceKind
    var detail: String
    var isConnected: Bool

    var isSupported: Bool { deviceKind.isSupported }
    var kind: String { deviceKind.title }
}

enum DeviceSupport {
    static let sonyVendorID = 0x054C
    static let dualSenseProductID = 0x0CE6
    static let dualSenseEdgeProductID = 0x0DF2
    static let appleVendorID = 0x004C
    static let appleTVRemoteProductIDs: Set<Int> = [0x0314, 0x0315, 0x0266, 0x0267]
    static let logitechVendorID = 0x046D
    static let mxMasterProductIDs: Set<Int> = [
        0xB019, 0xB023, 0xB034, 0xB042, 0xB043, 0xB366,
        0x4069, 0x4082
    ]

    static func classify(name: String, vendorID: Int?, productID: Int?) -> DeviceKind {
        if vendorID == sonyVendorID {
            if productID == dualSenseProductID { return .dualSense }
            if productID == dualSenseEdgeProductID { return .dualSenseEdge }
        }
        if vendorID == appleVendorID, let productID, appleTVRemoteProductIDs.contains(productID) {
            return .appleTVRemote
        }
        if vendorID == logitechVendorID, let productID, mxMasterProductIDs.contains(productID) {
            return .logitechMXMaster
        }

        let lowered = name.lowercased()
        if lowered.contains("dualsense edge") { return .dualSenseEdge }
        if lowered.contains("dualsense") { return .dualSense }
        if lowered.contains("siri remote") || lowered.contains("apple tv remote") {
            return .appleTVRemote
        }
        if name.uppercased() == "DJ7FTR0Y17FC" {
            return .appleTVRemote
        }
        if isMXMasterName(name) { return .logitechMXMaster }
        return .unsupported
    }

    static func isMXMasterName(_ name: String) -> Bool {
        name.lowercased().contains("mx master")
    }
}

enum BluetoothDeviceCatalog {
    static func availableDevices() -> [ConnectedBluetoothDevice] {
        autoreleasepool {
            loadAvailableDevices()
        }
    }

    private static func loadAvailableDevices() -> [ConnectedBluetoothDevice] {
        let hid = HIDNameIndex.load()
        var devices: [ConnectedBluetoothDevice] = []
        var seen = Set<String>()

        for record in hid.records {
            let kind = DeviceSupport.classify(
                name: record.product,
                vendorID: record.vendorID,
                productID: record.productID
            )
            guard kind.isSupported else { continue }
            let name = record.product.isEmpty ? kind.title : record.product
            let identity = "\(record.vendorID):\(record.productID):\(name.lowercased())"
            guard seen.insert(identity).inserted else { continue }
            seen.insert(name.lowercased())
            devices.append(
                ConnectedBluetoothDevice(
                    id: "hid:\(identity)",
                    name: name,
                    address: "HID",
                    deviceKind: kind,
                    detail: kind.title,
                    isConnected: true
                )
            )
        }

        for controller in GCController.controllers() where controller.extendedGamepad is GCDualSenseGamepad {
            let name = controller.vendorName ?? "DualSense Wireless Controller"
            if seen.contains(name.lowercased()) { continue }
            let id = "gc:\(name)"
            guard seen.insert(id).inserted else { continue }
            seen.insert(name.lowercased())
            devices.append(
                ConnectedBluetoothDevice(
                    id: id,
                    name: name,
                    address: "Game Controller",
                    deviceKind: .dualSense,
                    detail: DeviceKind.dualSense.title,
                    isConnected: true
                )
            )
        }

        return devices.sorted { lhs, rhs in
            if lhs.isConnected != rhs.isConnected {
                return lhs.isConnected
            }
            if lhs.isSupported != rhs.isSupported {
                return lhs.isSupported
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}

private struct HIDRecord {
    var product: String
    var vendorID: Int
    var productID: Int
}

private struct HIDNameIndex {
    var records: [HIDRecord]

    static func load() -> HIDNameIndex {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        var matching: [[String: Any]] = [
            [kIOHIDVendorIDKey as String: DeviceSupport.sonyVendorID],
            [
                kIOHIDDeviceUsagePageKey as String: 1,
                kIOHIDDeviceUsageKey as String: 5
            ]
        ]
        for productID in DeviceSupport.appleTVRemoteProductIDs {
            matching.append([
                kIOHIDVendorIDKey as String: DeviceSupport.appleVendorID,
                kIOHIDProductIDKey as String: productID
            ])
        }
        for productID in DeviceSupport.mxMasterProductIDs {
            matching.append([
                kIOHIDVendorIDKey as String: DeviceSupport.logitechVendorID,
                kIOHIDProductIDKey as String: productID
            ])
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }

        var records: [HIDRecord] = []
        if let copied = IOHIDManagerCopyDevices(manager) {
            for case let device as IOHIDDevice in (copied as NSSet) {
                let product = stringProperty(kIOHIDProductKey as String, device: device) ?? ""
                let vendorID = intProperty(kIOHIDVendorIDKey as String, device: device)
                let productID = intProperty(kIOHIDProductIDKey as String, device: device)
                records.append(HIDRecord(product: product, vendorID: vendorID, productID: productID))
            }
        }
        return HIDNameIndex(records: records)
    }

    private static func stringProperty(_ key: String, device: IOHIDDevice) -> String? {
        IOHIDDeviceGetProperty(device, key as CFString) as? String
    }

    private static func intProperty(_ key: String, device: IOHIDDevice) -> Int {
        if let number = IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber {
            return number.intValue
        }
        return 0
    }
}
