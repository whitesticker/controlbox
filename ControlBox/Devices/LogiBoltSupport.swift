import Foundation
import IOKit.hid

/// Logi Bolt USB receiver (`0xC548`) vendor HID++ only. Never the keyboard
/// or mouse collections, never seize. Pairing lives on Add Device → Logi Bolt.
enum LogiBoltSupport {
    static let vendorID = DeviceSupport.logitechVendorID
    static let productID = MXMasterHIDDiscovery.boltReceiverProductID
    static let hidppUsagePage = 0xFF00
    static let receiverIndex: UInt8 = 0xFF
    static let maxSlots = 6
    static let mouseEntropy: UInt8 = 0x0A
    static let keyboardEntropy: UInt8 = 0x14
    static let softwarePresentFlag: UInt8 = 0x08
    /// HID++ 1.0 receiver notification flags byte 1: wireless (0x41/0x40) + software present.
    static let wirelessNotificationFlag: UInt8 = 0x01
    static var receiverNotificationFlags: UInt8 { softwarePresentFlag | wirelessNotificationFlag }
    static let discoveryTimeoutSeconds = 30
    static let passkeyTimeoutSeconds = 45
    /// HID++ 1.0 `0x41` payload bit 6: link not established (paired, not present).
    static let linkNotEstablishedFlag: UInt8 = 0x40

    static func connectionSlot(from report: [UInt8]) -> Int? {
        guard report.count > 2 else { return nil }
        let slot = Int(report[1])
        guard slot >= 1, slot <= maxSlots else { return nil }
        switch report[2] {
        case 0x40:
            return slot
        case 0x41:
            return slot
        default:
            return nil
        }
    }

    static func isLinkEstablished(_ report: [UInt8]) -> Bool {
        guard report.count > 2, report[2] == 0x41 else { return false }
        let flags = report.count > 3 ? report[3] : 0
        return flags & linkNotEstablishedFlag == 0
    }

    static func hidManagerMatch() -> [String: Any] {
        [
            kIOHIDVendorIDKey as String: vendorID,
            kIOHIDProductIDKey as String: productID,
            kIOHIDDeviceUsagePageKey as String: hidppUsagePage
        ]
    }

    static func isVendorHIDPP(_ device: IOHIDDevice) -> Bool {
        let vendor = intProperty(kIOHIDVendorIDKey, device)
        let product = intProperty(kIOHIDProductIDKey, device)
        let page = intProperty(kIOHIDPrimaryUsagePageKey, device)
        let outSize = intProperty(kIOHIDMaxOutputReportSizeKey, device)
        return vendor == vendorID
            && product == productID
            && page == hidppUsagePage
            && outSize >= 20
    }

    static func identity(of device: IOHIDDevice) -> String {
        if let serial = stringProperty(kIOHIDSerialNumberKey, device), !serial.isEmpty {
            return serial
        }
        let location = intProperty(kIOHIDLocationIDKey, device)
        if location != 0 {
            return String(format: "loc-%08X", location)
        }
        return "bolt-\(ObjectIdentifier(device).hashValue)"
    }

    static func displayName(serial: String, product: String, index: Int, total: Int) -> String {
        let base = product.isEmpty ? "Logi Bolt" : product
        if !serial.isEmpty {
            return "\(base) · \(serial)"
        }
        if total > 1 {
            return "\(base) · \(index)"
        }
        return base
    }

    static func classify(wpid: Int, name: String, deviceClass: LogiBoltDeviceClass) -> DeviceKind {
        let kind = DeviceSupport.classify(
            name: name,
            vendorID: vendorID,
            productID: wpid
        )
        if kind.isSupported { return kind }
        if deviceClass == .keyboard, DeviceSupport.isMXMechanicalName(name) {
            return MXMechanicalSupport.kind(from: name)
        }
        if deviceClass == .mouse, DeviceSupport.isMXMasterName(name) {
            return DeviceSupport.mxKind(from: name)
        }
        return .unsupported
    }

    static func stringProperty(_ key: String, _ device: IOHIDDevice) -> String? {
        IOHIDDeviceGetProperty(device, key as CFString) as? String
    }

    static func intProperty(_ key: String, _ device: IOHIDDevice) -> Int {
        (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? 0
    }

    static func ascii(_ bytes: ArraySlice<UInt8>) -> String {
        String(bytes.compactMap { byte -> Character? in
            guard byte >= 32, byte < 127, let scalar = UnicodeScalar(UInt32(byte)) else { return nil }
            return Character(scalar)
        })
    }
}

enum LogiBoltDeviceClass: Int, Equatable, Sendable {
    case unknown = 0
    case keyboard = 1
    case mouse = 2
    case numpad = 3
    case presenter = 4
    case trackball = 8
    case touchpad = 9

    init(raw: Int) {
        self = LogiBoltDeviceClass(rawValue: raw) ?? .unknown
    }

    var title: String {
        switch self {
        case .keyboard, .numpad: return "Keyboard"
        case .mouse, .trackball, .touchpad: return "Mouse"
        case .presenter: return "Presenter"
        case .unknown: return "Device"
        }
    }

    var isKeyboard: Bool {
        self == .keyboard || self == .numpad
    }

    var isMouse: Bool {
        self == .mouse || self == .trackball || self == .touchpad
    }

    var paneGlyph: String {
        isKeyboard ? DeviceKind.logitechMXMechanical.paneGlyph : DeviceKind.logitechMXMaster4.paneGlyph
    }
}

struct LogiBoltDiscoveredDevice: Identifiable, Equatable {
    var address: [UInt8]
    var wpid: Int
    var deviceClass: LogiBoltDeviceClass
    var auth: UInt8
    var name: String

    var id: String {
        address.map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    var deviceKind: DeviceKind {
        LogiBoltSupport.classify(wpid: wpid, name: name, deviceClass: deviceClass)
    }

    var displayName: String {
        if !name.isEmpty { return name }
        if deviceKind.isSupported { return deviceKind.title }
        return deviceClass.title
    }

    var detail: String {
        String(format: "%@ · WPID %04X", deviceClass.title, wpid)
    }
}

enum LogiBoltPairKind: String, Equatable {
    case mouse
    case keyboard

    var title: String { rawValue.capitalized }
    var matches: (LogiBoltDeviceClass) -> Bool {
        switch self {
        case .mouse: return { $0.isMouse }
        case .keyboard: return { $0.isKeyboard }
        }
    }

    var entropy: UInt8 {
        self == .keyboard ? LogiBoltSupport.keyboardEntropy : LogiBoltSupport.mouseEntropy
    }

    var channelHint: String {
        "Hold the device Easy-Switch channel button until the LED blinks fast."
    }
}

enum LogiBoltDiscovery {
    static let status = "Put a mouse or keyboard in pairing mode. Advertising devices appear below."
}

enum LogiBoltClick: Equatable {
    case left
    case right

    var title: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        }
    }
}

enum LogiBoltKeypress: Equatable {
    case started
    case registered
    case erased
    case cleared
    case completed

    init?(code: UInt8) {
        switch code {
        case 0: self = .started
        case 1: self = .registered
        case 2: self = .erased
        case 3: self = .cleared
        case 4: self = .completed
        default: return nil
        }
    }
}

struct LogiBoltPairedDevice: Identifiable, Equatable {
    var receiverID: String
    var slot: Int
    var deviceClass: LogiBoltDeviceClass
    var wpid: Int
    var unitID: UInt32
    var name: String
    var entropyBits: Int
    var online: Bool
    var status: String
    var deviceKind: DeviceKind

    var id: String { "\(receiverID)-slot-\(slot)" }

    var displayName: String {
        if !name.isEmpty { return name }
        if deviceKind.isSupported { return deviceKind.title }
        return deviceClass.title
    }

    var detail: String {
        String(format: "Slot %d · %@ · WPID %04X", slot, deviceClass.title, wpid)
    }

    var logitechKey: LogitechDeviceKey {
        LogitechDeviceKey(
            name: displayName,
            kind: deviceKind,
            address: identityAddress,
            unitID: unitID == 0 ? nil : unitID,
            wirelessProductID: wpid == 0 ? nil : wpid,
            connection: .bolt
        )
    }

    var identityAddress: String {
        if unitID != 0 { return DeviceIdentity.unitToken(unitID) }
        if wpid != 0 { return String(format: "WPID %04X", wpid) }
        return DeviceIdentity.hidFallback
    }

    func asConnectedDevice() -> ConnectedBluetoothDevice {
        ConnectedBluetoothDevice(
            id: "bolt-\(receiverID)-\(slot)",
            name: displayName,
            address: identityAddress,
            deviceKind: deviceKind,
            detail: deviceKind.title,
            isConnected: online,
            unitID: unitID == 0 ? nil : unitID,
            wirelessProductID: wpid == 0 ? nil : wpid,
            connection: .bolt
        )
    }
}

struct LogiBoltReceiverSnapshot: Identifiable, Equatable {
    var id: String
    var serial: String
    var productName: String
    var title: String
    var slotCount: Int
    var pairedCount: Int
    var devices: [LogiBoltPairedDevice]
    var status: String?
    var isLoading: Bool

    var hasEmptySlot: Bool { devices.count < slotCount }

    var emptySlot: Int? {
        let used = Set(devices.map(\.slot))
        return (1...max(slotCount, 1)).first { !used.contains($0) }
    }

    var onlineDevices: [LogiBoltPairedDevice] { devices.filter(\.online) }

    var offlineDevices: [LogiBoltPairedDevice] { devices.filter { !$0.online } }
}

enum LogiBoltReply {
    case ok([UInt8])
    case error(UInt8)
    case timeout

    var bytes: [UInt8]? {
        if case .ok(let bytes) = self { return bytes }
        return nil
    }
}

enum LogiBoltPairingPhase: Equatable {
    case discovering
    case connecting
    case enterPasskey
    case succeeded
    case failed(String)
    case cancelled

    var isFinished: Bool {
        switch self {
        case .succeeded, .failed, .cancelled: return true
        default: return false
        }
    }
}
