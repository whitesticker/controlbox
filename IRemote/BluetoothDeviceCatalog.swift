import Foundation
import GameController
import IOKit.hid

enum DeviceKind: String, Codable, Equatable {
    case dualSense
    case dualSenseEdge
    case appleTVRemote
    case logitechMXMaster
    case logitechMXMaster3
    case logitechMXMaster3S
    case logitechMXMaster4
    case unsupported

    var isSupported: Bool { self != .unsupported }

    var isMXMaster: Bool {
        switch self {
        case .logitechMXMaster, .logitechMXMaster3, .logitechMXMaster3S, .logitechMXMaster4:
            return true
        default:
            return false
        }
    }

    var usesMXMasterHIDPP: Bool {
        switch self {
        case .logitechMXMaster, .logitechMXMaster3, .logitechMXMaster3S, .logitechMXMaster4:
            return true
        default:
            return false
        }
    }

    var title: String {
        switch self {
        case .dualSense: return "PS5 DualSense"
        case .dualSenseEdge: return "PS5 DualSense Edge"
        case .appleTVRemote: return "Apple TV Remote"
        case .logitechMXMaster, .logitechMXMaster4: return "MX Master 4"
        case .logitechMXMaster3: return "MX Master 3"
        case .logitechMXMaster3S: return "MX Master 3S"
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
    static var appleTVRemoteProductIDs: Set<Int> { AppleTVRemoteGenerations.productIDs }
    static let logitechVendorID = 0x046D
    static let mxMasterProductIDs: Set<Int> =
        MXMaster3Support.productIDs
            .union(MXMaster4Support.productIDs)

    static func classify(name: String, vendorID: Int?, productID: Int?) -> DeviceKind {
        if vendorID == sonyVendorID {
            if productID == dualSenseProductID { return .dualSense }
            if productID == dualSenseEdgeProductID { return .dualSenseEdge }
        }
        if vendorID == appleVendorID, let productID, appleTVRemoteProductIDs.contains(productID) {
            return .appleTVRemote
        }
        if vendorID == logitechVendorID, let productID {
            if MXMaster4Support.productIDs.contains(productID) { return .logitechMXMaster4 }
            if MXMaster3Support.productIDs.contains(productID) {
                return MXMaster3Support.kind(productID: productID, product: name)
            }
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
        if isMXMasterName(name) { return mxKind(from: name) }
        return .unsupported
    }

    static func mxKind(from name: String) -> DeviceKind {
        let lowered = name.lowercased()
        if lowered.contains("3s") || lowered.contains("3 s") { return .logitechMXMaster3S }
        if lowered.contains("master 4") { return .logitechMXMaster4 }
        if lowered.contains("master 3") { return .logitechMXMaster3 }
        return .logitechMXMaster4
    }

    static func isMXMasterName(_ name: String) -> Bool {
        name.lowercased().contains("mx master")
    }
}

enum DeviceIdentity {
    static let hidFallback = "HID"
    static let placeholders: Set<String> = [
        "", "HID", "HID++", "Bluetooth", "USB", "Game Controller"
    ]

    static func isConcrete(_ address: String) -> Bool {
        !placeholders.contains(address)
    }

    static func same(_ lhs: String, _ rhs: String) -> Bool {
        guard isConcrete(lhs), isConcrete(rhs) else { return false }
        return format(lhs).caseInsensitiveCompare(format(rhs)) == .orderedSame
    }

    static func displayLabel(for address: String) -> String {
        looksLikeHardwareAddress(address) ? "Address" : "Identifier"
    }

    static func looksLikeHardwareAddress(_ value: String) -> Bool {
        value.filter(\.isHexDigit).count == 12
    }

    static func format(_ raw: String) -> String {
        let hex = raw.filter(\.isHexDigit).uppercased()
        guard hex.count == 12 else { return raw }
        let pairs = stride(from: 0, to: 12, by: 2).map { index in
            let start = hex.index(hex.startIndex, offsetBy: index)
            let end = hex.index(start, offsetBy: 2)
            return String(hex[start..<end])
        }
        return pairs.joined(separator: ":")
    }

    static func fromHID(_ device: IOHIDDevice) -> String {
        if let address = stringProperty("DeviceAddress", device: device), !address.isEmpty {
            return format(address)
        }
        if let serial = stringProperty(kIOHIDSerialNumberKey as String, device: device), !serial.isEmpty {
            return serial
        }
        return ""
    }

    private static func stringProperty(_ key: String, device: IOHIDDevice) -> String? {
        IOHIDDeviceGetProperty(device, key as CFString) as? String
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
            let token = record.address.isEmpty ? name.lowercased() : record.address.lowercased()
            let identity = "\(record.vendorID):\(record.productID):\(token)"
            guard seen.insert(identity).inserted else { continue }
            seen.insert(name.lowercased())
            devices.append(
                ConnectedBluetoothDevice(
                    id: "hid:\(identity)",
                    name: name,
                    address: record.address.isEmpty ? DeviceIdentity.hidFallback : record.address,
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
    var address: String
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
                records.append(
                    HIDRecord(
                        product: product,
                        vendorID: vendorID,
                        productID: productID,
                        address: DeviceIdentity.fromHID(device)
                    )
                )
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
