import Foundation
import GameController
import IOBluetooth
import IOKit.hid

enum DeviceKind: String, Codable, Equatable {
    case dualSense
    case dualSenseEdge
    case appleTVRemote
    case unsupported

    var isSupported: Bool { self != .unsupported }

    var title: String {
        switch self {
        case .dualSense: return "PS5 DualSense"
        case .dualSenseEdge: return "PS5 DualSense Edge"
        case .appleTVRemote: return "Apple TV Remote"
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

    static func classify(name: String, vendorID: Int?, productID: Int?) -> DeviceKind {
        if vendorID == sonyVendorID {
            if productID == dualSenseProductID { return .dualSense }
            if productID == dualSenseEdgeProductID { return .dualSenseEdge }
        }
        if vendorID == appleVendorID, let productID, appleTVRemoteProductIDs.contains(productID) {
            return .appleTVRemote
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
        return .unsupported
    }
}

enum BluetoothDeviceCatalog {
    static func availableDevices() -> [ConnectedBluetoothDevice] {
        let hid = HIDNameIndex.load()
        var devices: [ConnectedBluetoothDevice] = []
        var seen = Set<String>()

        if let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] {
            for device in paired {
                let name = device.name ?? device.addressString ?? "Unknown device"
                let address = (device.addressString ?? "").uppercased()
                let connected = device.isConnected()
                let hidMatch = hid.match(name: name)
                let kind = DeviceSupport.classify(
                    name: name,
                    vendorID: hidMatch?.vendorID,
                    productID: hidMatch?.productID
                )
                if !connected && !kind.isSupported { continue }

                let id = address.isEmpty ? name : address
                guard seen.insert(id).inserted else { continue }
                seen.insert(name.lowercased())
                devices.append(
                    ConnectedBluetoothDevice(
                        id: id,
                        name: name,
                        address: address.isEmpty ? "Bluetooth" : address,
                        deviceKind: kind,
                        detail: kind.isSupported ? kind.title : "VibeRemote cannot use this device yet",
                        isConnected: connected
                    )
                )
            }
        }

        for record in hid.records where record.vendorID == DeviceSupport.sonyVendorID {
            let kind = DeviceSupport.classify(
                name: record.product,
                vendorID: record.vendorID,
                productID: record.productID
            )
            guard kind == .dualSense || kind == .dualSenseEdge else { continue }
            let name = record.product.isEmpty ? kind.title : record.product
            if seen.contains(name.lowercased()) { continue }
            let id = "hid:\(record.vendorID):\(record.productID):\(name)"
            guard seen.insert(id).inserted else { continue }
            seen.insert(name.lowercased())
            devices.append(
                ConnectedBluetoothDevice(
                    id: id,
                    name: name,
                    address: "USB",
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

    func match(name: String) -> HIDRecord? {
        if let exact = records.first(where: { $0.product.caseInsensitiveCompare(name) == .orderedSame }) {
            return exact
        }
        if name.lowercased().contains("dualsense") {
            return records.first { $0.vendorID == DeviceSupport.sonyVendorID }
        }
        if DeviceSupport.classify(name: name, vendorID: nil, productID: nil) == .appleTVRemote {
            return records.first {
                $0.vendorID == DeviceSupport.appleVendorID
                    && DeviceSupport.appleTVRemoteProductIDs.contains($0.productID)
            }
        }
        return nil
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
