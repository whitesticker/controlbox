import Foundation
import GameController

/// DualSense / DualSense Edge. Game Controller attach + snapshot.
/// Adds Sony touchpad and HID battery on top of `GamepadSession`.
@MainActor
final class DualSenseSession: GamepadSession {
    private let hidBattery = DualSenseHIDBatteryReader()

    init() {
        super.init(familyID: "dualsense", kinds: [.dualSense, .dualSenseEdge])
    }

    override func start() {
        hidBattery.start()
        super.start()
    }

    override func stop() {
        hidBattery.stop()
        super.stop()
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
        if let percent = hidBattery.percent {
            next.batteryAvailable = true
            next.capabilities.battery = true
            next.batteryPercent = percent
            next.batteryCharging = hidBattery.isCharging
            next.batteryFull = hidBattery.isFull
            if hidBattery.isFull {
                next.batteryStateDescription = "Full"
            } else if hidBattery.isCharging {
                next.batteryStateDescription = "Charging"
            } else {
                next.batteryStateDescription = "Discharging"
            }
            return
        }
        super.applyBattery(to: &next, controller: controller)
    }
}
