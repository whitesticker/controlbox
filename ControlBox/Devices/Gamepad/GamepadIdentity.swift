import Foundation
import ControlBoxCore

enum GamepadIdentity {
    static func catalogID(name: String, ordinal: Int) -> String {
        GamepadCatalogID.make(name: name, ordinal: ordinal)
    }

    static func slotAddress(catalogID: String, hidAddress: String?) -> String {
        GamepadCatalogID.slotAddress(catalogID: catalogID, hidAddress: hidAddress)
    }

    static func uniqueHIDAddress(for kind: DeviceKind, hid: [GamepadHIDPad], gcCount: Int) -> String? {
        let addresses = hid.filter { $0.kind == kind }.compactMap { pad -> String? in
            DeviceIdentity.isConcrete(pad.address) ? DeviceIdentity.format(pad.address) : nil
        }
        return GamepadCatalogID.uniqueHIDAddress(addresses: addresses, gcCount: gcCount)
    }

    static func kind(forHID pad: GamepadHIDPad) -> DeviceKind? {
        if pad.vendorID == DeviceSupport.sonyVendorID {
            if pad.productID == DeviceSupport.dualSenseEdgeProductID { return .dualSenseEdge }
            if pad.productID == DeviceSupport.dualSenseProductID { return .dualSense }
        }
        if pad.vendorID == DeviceSupport.xboxVendorID, pad.usagePage == 1, pad.usage == 5 {
            return .gamepad
        }
        if pad.usagePage == 1, pad.usage == 5, pad.vendorID != DeviceSupport.logitechVendorID,
           pad.vendorID != DeviceSupport.appleVendorID, pad.vendorID != DeviceSupport.sonyVendorID {
            return .gamepad
        }
        return nil
    }

    static func normalizedName(_ name: String) -> String {
        GamepadCatalogID.normalizedName(name)
    }
}

struct GamepadHIDPad: Equatable {
    var name: String
    var address: String
    var vendorID: Int
    var productID: Int
    var usagePage: Int
    var usage: Int

    var kind: DeviceKind? { GamepadIdentity.kind(forHID: self) }
}

struct GamepadLivePad: Equatable {
    var catalogID: String
    var name: String
    var address: String
    var kind: DeviceKind
    var layout: GamepadLayout
    var capabilities: GamepadCapabilities
    var nameOrdinal: Int
    var hidAddress: String?
}
