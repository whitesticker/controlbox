import Foundation
import GameController
import ControlBoxCore

extension GamepadLayout {
    static func from(controller: GCController) -> GamepadLayout {
        let category = controller.productCategory
        if category == GCProductCategoryDualSense || category == GCProductCategoryDualShock4 {
            return .sony
        }
        if category == GCProductCategoryXboxOne {
            return .xbox
        }
        let name = (controller.vendorName ?? "").lowercased()
        if name.contains("nintendo")
            || name.contains("joy-con")
            || name.contains("joycon")
            || name.contains("pro controller")
            || name.contains("switch") {
            return .nintendo
        }
        return .generic
    }
}

extension GamepadCapabilities {
    static func from(controller: GCController) -> GamepadCapabilities {
        let pad = controller.extendedGamepad
        return GamepadCapabilities(
            touchpad: pad is GCDualSenseGamepad || pad is GCDualShockGamepad,
            motion: controller.motion != nil,
            haptics: controller.haptics != nil,
            battery: controller.battery != nil
        )
    }
}

extension GamepadIdentity {
    static func kind(of controller: GCController) -> DeviceKind {
        if controller.extendedGamepad is GCDualSenseGamepad {
            let name = (controller.vendorName ?? "").lowercased()
            return name.contains("edge") ? .dualSenseEdge : .dualSense
        }
        return .gamepad
    }

    static func livePads(controllers: [GCController], hid: [GamepadHIDPad]) -> [GamepadLivePad] {
        let pads = controllers.filter { $0.extendedGamepad != nil }
        var kindCounts: [DeviceKind: Int] = [:]
        for controller in pads {
            kindCounts[kind(of: controller), default: 0] += 1
        }
        var ordinals: [String: Int] = [:]
        return pads.map { controller in
            let padKind = kind(of: controller)
            let name = normalizedName(controller.vendorName ?? padKind.title)
            let ordinalKey = name.lowercased()
            ordinals[ordinalKey, default: 0] += 1
            let ordinal = ordinals[ordinalKey] ?? 1
            let hidAddress = uniqueHIDAddress(for: padKind, hid: hid, gcCount: kindCounts[padKind] ?? 0)
            let id = catalogID(name: name, ordinal: ordinal)
            return GamepadLivePad(
                catalogID: id,
                name: name,
                address: slotAddress(catalogID: id, hidAddress: hidAddress),
                kind: padKind,
                layout: GamepadLayout.from(controller: controller),
                capabilities: GamepadCapabilities.from(controller: controller),
                nameOrdinal: ordinal,
                hidAddress: hidAddress
            )
        }
    }
}
