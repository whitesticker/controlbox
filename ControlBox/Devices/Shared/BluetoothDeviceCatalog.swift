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
    case logitechMouse
    case logitechMXMechanical
    case logitechMXMechanicalMini
    case unsupported

    var isSupported: Bool { self != .unsupported }

    var isMXMaster: Bool {
        switch self {
        case .logitechMXMaster, .logitechMXMaster3, .logitechMXMaster3S, .logitechMXMaster4,
             .logitechMouse:
            return true
        default:
            return false
        }
    }

    var isMXKeyboard: Bool {
        self == .logitechMXMechanical || self == .logitechMXMechanicalMini
    }

    var isGamepad: Bool {
        self == .dualSense || self == .dualSenseEdge
    }

    var paneGlyph: String {
        if self == .appleTVRemote { return "device-siri-remote-filled" }
        if isMXMaster { return "device-mx-master-line" }
        if isMXKeyboard { return "device-mx-mechanical-filled" }
        return "device-dualsense-filled"
    }

    var usesMXMasterHIDPP: Bool {
        switch self {
        case .logitechMXMaster, .logitechMXMaster3, .logitechMXMaster3S, .logitechMXMaster4,
             .logitechMouse:
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
        case .logitechMouse: return "Logitech Mouse"
        case .logitechMXMechanical: return "MX Mechanical"
        case .logitechMXMechanicalMini: return "MX Mechanical Mini"
        case .unsupported: return "Not supported yet"
        }
    }

    var supportBlurb: String {
        switch self {
        case .dualSense, .dualSenseEdge:
            return "Buttons, sticks, and the touchpad map to pointer, keys, and gestures. 1-finger and 2-finger pads are separate."
        case .appleTVRemote:
            return "Click, swipe, and Back from the Siri Remote / Apple TV remote."
        case .logitechMXMaster3:
            return "Pointer, wheel, thumb, and the gesture button. Same bindings as MX Master 3S."
        case .logitechMXMaster3S:
            return "Pointer, wheel, thumb, and the gesture button. Tap is click; hold then move is swipe."
        case .logitechMXMaster, .logitechMXMaster4:
            return "Pointer, wheel, thumb, Gesture, and the haptic pad. Control this Mac is a mouse toggle."
        case .logitechMouse:
            return "Pointer, scrolling, and the controls this mouse reports over HID++."
        case .logitechMXMechanical, .logitechMXMechanicalMini:
            return "Backlight, lighting effect, battery saving, and battery. Keys stay native."
        case .unsupported:
            return "Control Box does not attach this device yet."
        }
    }

    var supportGroup: String { sidebarType.title }

    var sidebarType: DeviceSidebarType {
        switch self {
        case .logitechMXMaster, .logitechMXMaster3, .logitechMXMaster3S, .logitechMXMaster4,
             .logitechMouse:
            return .mouse
        case .dualSense, .dualSenseEdge:
            return .gamepad
        case .appleTVRemote:
            return .remote
        case .logitechMXMechanical, .logitechMXMechanicalMini:
            return .keyboard
        case .unsupported:
            return .other
        }
    }

    var brand: String {
        switch self {
        case .dualSense, .dualSenseEdge:
            return "Sony"
        case .appleTVRemote:
            return "Apple"
        case .logitechMXMaster, .logitechMXMaster3, .logitechMXMaster3S, .logitechMXMaster4,
             .logitechMouse, .logitechMXMechanical, .logitechMXMechanicalMini:
            return "Logitech"
        case .unsupported:
            return "Other"
        }
    }
}

enum DeviceSidebarType: String, CaseIterable, Identifiable {
    case mouse
    case gamepad
    case remote
    case keyboard
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mouse: return "Mouse"
        case .gamepad: return "Gamepad"
        case .remote: return "Remote"
        case .keyboard: return "Keyboard"
        case .other: return "Other"
        }
    }
}

enum DeviceConnection: String, Codable, Equatable, Sendable {
    case bluetooth
    case bolt

    var title: String {
        switch self {
        case .bluetooth: return "Bluetooth"
        case .bolt: return "Bolt"
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
    var unitID: UInt32? = nil
    var wirelessProductID: Int? = nil
    var connection: DeviceConnection = .bluetooth

    var isSupported: Bool { deviceKind.isSupported }
    var kind: String { deviceKind.title }

    var logitechKey: LogitechDeviceKey {
        LogitechDeviceKey(
            name: name,
            kind: deviceKind,
            address: address,
            unitID: unitID,
            wirelessProductID: wirelessProductID,
            connection: connection
        )
    }
}

enum DeviceSupport {
    static let sonyVendorID = 0x054C
    static let dualSenseProductID = 0x0CE6
    static let dualSenseEdgeProductID = 0x0DF2
    static let appleVendorID = 0x004C
    static var appleTVRemoteProductIDs: Set<Int> { AppleTVRemoteGenerations.productIDs }
    static let logitechVendorID = 0x046D
    static let mxMasterProductIDs = LogitechMouseRegistry.knownProductIDs
    static var mxKeyboardProductIDs: Set<Int> { MXMechanicalSupport.productIDs }

    static func classify(
        name: String,
        vendorID: Int?,
        productID: Int?,
        usagePage: Int? = nil,
        usage: Int? = nil,
        hasLogitechHIDPP: Bool = false
    ) -> DeviceKind {
        if vendorID == sonyVendorID {
            if productID == dualSenseProductID { return .dualSense }
            if productID == dualSenseEdgeProductID { return .dualSenseEdge }
        }
        if vendorID == appleVendorID, let productID, appleTVRemoteProductIDs.contains(productID) {
            return .appleTVRemote
        }
        if vendorID == logitechVendorID, let productID {
            if MXMechanicalSupport.productIDs.contains(productID) {
                return MXMechanicalSupport.kind(productID: productID, product: name)
            }
            if LogitechMouseRegistry.knownProductIDs.contains(productID) {
                return LogitechMouseRegistry.kind(productID: productID, product: name)
            }
            if usagePage == 0x01, usage == 0x02, hasLogitechHIDPP {
                return .logitechMouse
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
        if isMXMechanicalName(name) { return MXMechanicalSupport.kind(from: name) }
        if isMXMasterName(name) { return mxKind(from: name) }
        return .unsupported
    }

    static func mxKind(from name: String) -> DeviceKind {
        LogitechMouseRegistry.kind(productID: 0, product: name)
    }

    static func isMXMasterName(_ name: String) -> Bool {
        name.lowercased().contains("mx master")
    }

    static func isMXMechanicalName(_ name: String) -> Bool {
        name.lowercased().contains("mx mechanical")
    }
}

/// One Logitech mouse or keyboard, whether it is on Bluetooth or a Bolt slot.
/// Easy-Switch can present the same unit on both radios; collapse those.
struct LogitechDeviceKey: Equatable {
    var name: String
    var kind: DeviceKind
    var address: String
    var unitID: UInt32?
    var wirelessProductID: Int?
    var connection: DeviceConnection
}

enum DeviceIdentity {
    static let hidFallback = "HID"
    static let placeholders: Set<String> = [
        "", "HID", "HID++", "Bluetooth", "USB", "Game Controller"
    ]

    static func isConcrete(_ address: String) -> Bool {
        !placeholders.contains(address) && !isBoltWPID(address)
    }

    static func isBoltWPID(_ address: String) -> Bool {
        address.uppercased().hasPrefix("WPID")
    }

    static func same(_ lhs: String, _ rhs: String) -> Bool {
        guard isConcrete(lhs), isConcrete(rhs) else { return false }
        if lhs.caseInsensitiveCompare(rhs) == .orderedSame { return true }
        return format(lhs).caseInsensitiveCompare(format(rhs)) == .orderedSame
    }

    static func namesMatch(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = rhs.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !left.isEmpty, !right.isEmpty else { return false }
        return left.caseInsensitiveCompare(right) == .orderedSame
    }

    static func compatibleLogitechKinds(_ lhs: DeviceKind, _ rhs: DeviceKind) -> Bool {
        if lhs == rhs { return true }
        if lhs == .logitechMouse, rhs.isMXMaster { return true }
        if rhs == .logitechMouse, lhs.isMXMaster { return true }
        if lhs.isMXMaster3Family, rhs.isMXMaster3Family { return true }
        if (lhs == .logitechMXMaster4 || lhs == .logitechMXMaster),
           (rhs == .logitechMXMaster4 || rhs == .logitechMXMaster) {
            return true
        }
        if lhs.isMXKeyboard, rhs.isMXKeyboard { return true }
        return false
    }

    static func sameLogitech(_ lhs: LogitechDeviceKey, _ rhs: LogitechDeviceKey) -> Bool {
        guard lhs.kind.isMXMaster || lhs.kind.isMXKeyboard else { return false }
        guard rhs.kind.isMXMaster || rhs.kind.isMXKeyboard else { return false }
        guard compatibleLogitechKinds(lhs.kind, rhs.kind) else { return false }
        if let leftUnit = nonzeroUnit(lhs.unitID), let rightUnit = nonzeroUnit(rhs.unitID) {
            return leftUnit == rightUnit
        }
        if let leftUnit = nonzeroUnit(lhs.unitID), unitMatchesAddress(leftUnit, rhs.address) {
            return true
        }
        if let rightUnit = nonzeroUnit(rhs.unitID), unitMatchesAddress(rightUnit, lhs.address) {
            return true
        }
        if looksLikeHardwareAddress(lhs.address), looksLikeHardwareAddress(rhs.address) {
            return same(lhs.address, rhs.address)
        }
        if same(lhs.address, rhs.address) { return true }
        // WPID identifies a model, not one physical unit. Cross-radio collapse
        // requires the HID++ unit ID (or a concrete matching address) above.
        return false
    }

    static func logitechNamesEquivalent(_ lhs: String, _ rhs: String) -> Bool {
        if namesMatch(lhs, rhs) { return true }
        let left = canonicalLogitechName(lhs)
        let right = canonicalLogitechName(rhs)
        return !left.isEmpty && left == right
    }

    static func canonicalLogitechName(_ name: String) -> String {
        var compact = name.lowercased().filter(\.isLetter)
        compact = compact.replacingOccurrences(of: "mchncl", with: "mechanical")
        if compact.hasSuffix("mechanicalm") {
            compact += "ini"
        }
        return compact
    }

    static func preferredLogitechName(_ lhs: String, _ rhs: String) -> String {
        let left = lhs.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = rhs.trimmingCharacters(in: .whitespacesAndNewlines)
        if left.isEmpty { return right }
        if right.isEmpty { return left }
        let leftTruncated = left.lowercased().contains("mchncl")
        let rightTruncated = right.lowercased().contains("mchncl")
        if leftTruncated, !rightTruncated { return right }
        if rightTruncated, !leftTruncated { return left }
        return left.count >= right.count ? left : right
    }

    static func unitToken(_ unit: UInt32) -> String {
        String(format: "%08X", unit)
    }

    private static func nonzeroUnit(_ unit: UInt32?) -> UInt32? {
        guard let unit, unit != 0 else { return nil }
        return unit
    }

    private static func unitMatchesAddress(_ unit: UInt32, _ address: String) -> Bool {
        let hex = address.filter(\.isHexDigit).uppercased()
        return hex == unitToken(unit)
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
            let isGenericLogitechEndpoint =
                record.vendorID == DeviceSupport.logitechVendorID
                && LogitechHIDPPDiscovery.collections.contains {
                    $0.usagePage == record.usagePage && $0.usage == record.usage
                }
                && !DeviceSupport.mxMasterProductIDs.contains(record.productID)
                && !DeviceSupport.mxKeyboardProductIDs.contains(record.productID)
            if isGenericLogitechEndpoint { continue }
            let kind = DeviceSupport.classify(
                name: record.product,
                vendorID: record.vendorID,
                productID: record.productID,
                usagePage: record.usagePage,
                usage: record.usage,
                hasLogitechHIDPP: hid.logitechHIDPPProductIDs.contains(record.productID)
            )
            let name = record.product.isEmpty
                ? (kind.isSupported ? kind.title : "Unknown device")
                : record.product
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
                    detail: kind.isSupported ? kind.title : "Not supported yet",
                    isConnected: true,
                    unitID: nil,
                    wirelessProductID: (kind.isMXMaster || kind.isMXKeyboard) ? record.productID : nil,
                    connection: .bluetooth
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
    var usagePage: Int
    var usage: Int
}

private struct HIDNameIndex {
    var records: [HIDRecord]
    var logitechHIDPPProductIDs: Set<Int>

    static func load() -> HIDNameIndex {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        var matching: [[String: Any]] = [
            [kIOHIDVendorIDKey as String: DeviceSupport.sonyVendorID],
            [
                kIOHIDDeviceUsagePageKey as String: 1,
                kIOHIDDeviceUsageKey as String: 5
            ],
            [
                kIOHIDDeviceUsagePageKey as String: 1,
                kIOHIDDeviceUsageKey as String: 2
            ]
        ]
        for productID in DeviceSupport.appleTVRemoteProductIDs {
            matching.append([
                kIOHIDVendorIDKey as String: DeviceSupport.appleVendorID,
                kIOHIDProductIDKey as String: productID
            ])
        }
        for productID in DeviceSupport.mxMasterProductIDs.union(DeviceSupport.mxKeyboardProductIDs) {
            matching.append([
                kIOHIDVendorIDKey as String: DeviceSupport.logitechVendorID,
                kIOHIDProductIDKey as String: productID
            ])
        }
        matching.append(contentsOf: LogitechHIDPPDiscovery.hidManagerMatches())
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }

        var records: [HIDRecord] = []
        var logitechHIDPPProductIDs = Set<Int>()
        if let copied = IOHIDManagerCopyDevices(manager) {
            for case let device as IOHIDDevice in (copied as NSSet) {
                let productID = intProperty(kIOHIDProductIDKey as String, device: device)
                if LogitechHIDPPDiscovery.receiverProductIDs.contains(productID) { continue }
                if LogitechHIDPPDiscovery.collection(for: device) != nil {
                    logitechHIDPPProductIDs.insert(productID)
                }
                let page = intProperty(kIOHIDPrimaryUsagePageKey as String, device: device)
                let usage = intProperty(kIOHIDPrimaryUsageKey as String, device: device)
                if page == 1 && (usage == 6 || usage == 7) { continue }
                let product = stringProperty(kIOHIDProductKey as String, device: device) ?? ""
                let vendorID = intProperty(kIOHIDVendorIDKey as String, device: device)
                records.append(
                    HIDRecord(
                        product: product,
                        vendorID: vendorID,
                        productID: productID,
                        address: DeviceIdentity.fromHID(device),
                        usagePage: page,
                        usage: usage
                    )
                )
            }
        }
        return HIDNameIndex(
            records: records,
            logitechHIDPPProductIDs: logitechHIDPPProductIDs
        )
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
