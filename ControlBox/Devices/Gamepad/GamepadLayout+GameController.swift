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
