import Foundation
import GameController

/// DualSense / DualSense Edge. Game Controller attach + snapshot.
/// Adds Sony touchpad and a shared HID battery reader on top of `GamepadSession`.
@MainActor
final class DualSenseSession: GamepadSession {
    var hidBattery: DualSenseHIDBatteryReader?
    var hidAddress: String?

    init() {
        super.init(familyID: "dualsense", kinds: [.dualSense, .dualSenseEdge])
    }

    override func accepts(_ controller: GCController) -> Bool {
        controller.extendedGamepad is GCDualSenseGamepad
    }

    override func readExtras(
        controller: GCController,
        pad: GCExtendedGamepad,
        into next: inout GamepadSnapshot,
        wantMotion: Bool
    ) {
        guard let pad = pad as? GCDualSenseGamepad else { return }
        next.touchpad = GamepadTouchpadState(
            click: pad.touchpadButton.isPressed,
            finger1: finger(from: pad.touchpadPrimary),
            finger2: finger(from: pad.touchpadSecondary)
        )
    }

    override func applyBattery(to next: inout GamepadSnapshot, controller: GCController) {
        if let reading = hidBattery?.reading(forAddress: hidAddress) {
            next.batteryAvailable = true
            next.capabilities.battery = true
            next.batteryPercent = reading.percent
            next.batteryCharging = reading.isCharging
            next.batteryFull = reading.isFull
            if reading.isFull {
                next.batteryStateDescription = "Full"
            } else if reading.isCharging {
                next.batteryStateDescription = "Charging"
            } else {
                next.batteryStateDescription = "Discharging"
            }
            return
        }
        super.applyBattery(to: &next, controller: controller)
    }
}
