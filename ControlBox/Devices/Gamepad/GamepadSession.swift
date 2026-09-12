import Foundation
import GameController
import ControlBoxCore

/// Generic `GCExtendedGamepad` attach + snapshot.
/// DualSense subclasses this for touchpad and HID battery.
/// The host owns records, engines, and "Control this Mac".
@MainActor
class GamepadSession: DeviceFamilySession {
    let familyID: String
    let kinds: Set<DeviceKind>

    private(set) var snapshot = GamepadSnapshot()
    private(set) var controller: GCController?
    private let haptics = GamepadHaptics()
    private var previousButtons: [String: Bool] = [:]

    var vendorName: String? { controller?.vendorName }
    var isAttached: Bool { controller != nil }

    init(familyID: String = "gamepad", kinds: Set<DeviceKind> = [.gamepad]) {
        self.familyID = familyID
        self.kinds = kinds
    }

    func start() {
        GCController.shouldMonitorBackgroundEvents = true
        GCController.startWirelessControllerDiscovery(completionHandler: nil)
    }

    func stop() {
        detach()
        GCController.stopWirelessControllerDiscovery()
    }

    func pulse() {
        haptics.pulse()
    }

    func attachPreferred(named preferredName: String?) {
        let matches = GCController.controllers().filter(accepts)
        guard !matches.isEmpty else {
            detach()
            return
        }
        let match = matches.first { controller in
            (controller.vendorName ?? "") == preferredName
        } ?? matches.first
        attachIfNeeded(match)
    }

    func handleDisconnect(_ disconnected: GCController) {
        if controller == disconnected {
            detach()
        }
    }

    func detach() {
        guard controller != nil else { return }
        controller = nil
        didDetach()
        snapshot = GamepadSnapshot()
        previousButtons = [:]
    }

    func poll(hapticEnabled: Bool, wantMotion: Bool) {
        guard let controller else {
            if snapshot.connected {
                snapshot = GamepadSnapshot()
            }
            return
        }

        var next = GamepadSnapshot()
        next.connected = true
        next.name = controller.vendorName ?? "Game Controller"
        next.product = controller.productCategory
        next.playerIndex = controller.playerIndex.rawValue
        next.layout = GamepadLayout.from(controller: controller)
        next.capabilities = GamepadCapabilities.from(controller: controller)
        next.hasMotion = controller.motion != nil
        applyBattery(to: &next, controller: controller)

        if let pad = controller.extendedGamepad {
            next.cross = pad.buttonA.isPressed
            next.circle = pad.buttonB.isPressed
            next.square = pad.buttonX.isPressed
            next.triangle = pad.buttonY.isPressed
            next.dpadUp = pad.dpad.up.isPressed
            next.dpadDown = pad.dpad.down.isPressed
            next.dpadLeft = pad.dpad.left.isPressed
            next.dpadRight = pad.dpad.right.isPressed
            next.l1 = pad.leftShoulder.isPressed
            next.r1 = pad.rightShoulder.isPressed
            next.l3 = isPressed(pad.leftThumbstickButton)
            next.r3 = isPressed(pad.rightThumbstickButton)
            next.create = isPressed(pad.buttonOptions)
            next.options = pad.buttonMenu.isPressed
            next.l2 = pad.leftTrigger.value
            next.r2 = pad.rightTrigger.value
            next.leftStick = SIMD2(pad.leftThumbstick.xAxis.value, pad.leftThumbstick.yAxis.value)
            next.rightStick = SIMD2(pad.rightThumbstick.xAxis.value, pad.rightThumbstick.yAxis.value)
            if let home = pad.buttonHome {
                next.ps = home.isPressed
            } else if let home = controller.physicalInputProfile.buttons[GCInputButtonHome] {
                next.ps = home.isPressed
            }
            readExtras(controller: controller, pad: pad, into: &next, wantMotion: wantMotion)
        }

        if let motion = controller.motion {
            if motion.sensorsActive != wantMotion {
                motion.sensorsActive = wantMotion
            }
            if wantMotion {
                next.gravity = Vec3(x: motion.gravity.x, y: motion.gravity.y, z: motion.gravity.z)
                next.userAcceleration = Vec3(
                    x: motion.userAcceleration.x,
                    y: motion.userAcceleration.y,
                    z: motion.userAcceleration.z
                )
                next.rotationRate = Vec3(
                    x: motion.rotationRate.x,
                    y: motion.rotationRate.y,
                    z: motion.rotationRate.z
                )
            }
        }

        next.events = updatedEvents(from: next)
        if hapticEnabled, next.hadButtonDown(from: snapshot) {
            haptics.pulse()
        }
        snapshot = next
    }

    func accepts(_ controller: GCController) -> Bool {
        controller.extendedGamepad != nil && !(controller.extendedGamepad is GCDualSenseGamepad)
    }

    func readExtras(
        controller: GCController,
        pad: GCExtendedGamepad,
        into next: inout GamepadSnapshot,
        wantMotion: Bool
    ) {
        if let shock = pad as? GCDualShockGamepad {
            next.touchpad = GamepadTouchpadState(
                click: shock.touchpadButton.isPressed,
                finger1: finger(from: shock.touchpadPrimary),
                finger2: finger(from: shock.touchpadSecondary)
            )
        }
    }

    func applyBattery(to next: inout GamepadSnapshot, controller: GCController) {
        guard let battery = controller.battery, battery.batteryState != .unknown else { return }
        next.batteryAvailable = true
        next.capabilities.battery = true
        next.batteryPercent = Int((battery.batteryLevel * 100).rounded())
        switch battery.batteryState {
        case .charging:
            next.batteryCharging = true
            next.batteryStateDescription = "Charging"
        case .full:
            next.batteryFull = true
            next.batteryStateDescription = "Full"
        case .discharging:
            next.batteryStateDescription = "Discharging"
        default:
            next.batteryStateDescription = "Unknown"
        }
    }

    func extraEventRows(_ next: GamepadSnapshot) -> [(String, Bool)] {
        guard next.touchpad != nil else { return [] }
        return [
            ("Touchpad click", next.touchpadClick),
            ("Touch 1", next.touch1.active),
            ("Touch 2", next.touch2.active)
        ]
    }

    func didAttach(_ controller: GCController) {
        controller.handlerQueue = .main
        controller.motion?.sensorsActive = false
        haptics.attach(controller)
    }

    func didDetach() {
        haptics.detach()
    }

    func finger(from pad: GCControllerDirectionPad) -> TouchFinger {
        let x = pad.xAxis.value
        let y = pad.yAxis.value
        let digital = pad.up.isPressed || pad.down.isPressed || pad.left.isPressed || pad.right.isPressed
        let analog = abs(x) > 0.001 || abs(y) > 0.001
        return TouchFinger(x: x, y: y, active: digital || analog)
    }

    private func attachIfNeeded(_ incoming: GCController?) {
        guard let incoming, accepts(incoming) else { return }
        if let current = controller, current == incoming { return }
        controller = incoming
        previousButtons = [:]
        didAttach(incoming)
    }

    private func isPressed(_ button: GCControllerButtonInput?) -> Bool {
        button?.isPressed ?? false
    }

    private func updatedEvents(from next: GamepadSnapshot) -> [InputLogEvent] {
        let layout = next.layout
        var current: [(String, Bool)] = [
            (layout.label(for: .cross), next.cross),
            (layout.label(for: .circle), next.circle),
            (layout.label(for: .square), next.square),
            (layout.label(for: .triangle), next.triangle),
            (layout.label(for: .dpadUp), next.dpadUp),
            (layout.label(for: .dpadDown), next.dpadDown),
            (layout.label(for: .dpadLeft), next.dpadLeft),
            (layout.label(for: .dpadRight), next.dpadRight),
            (layout.label(for: .l1), next.l1),
            (layout.label(for: .r1), next.r1),
            (layout.label(for: .l2), next.l2 > 0.15),
            (layout.label(for: .r2), next.r2 > 0.15),
            (layout.label(for: .l3), next.l3),
            (layout.label(for: .r3), next.r3),
            (layout.label(for: .create), next.create),
            (layout.label(for: .options), next.options),
            (layout.label(for: .ps), next.ps)
        ]
        current.append(contentsOf: extraEventRows(next))

        var events = snapshot.events
        for (label, pressed) in current {
            if previousButtons[label] != pressed {
                events.insert(
                    InputLogEvent(id: UUID(), date: Date(), label: label, pressed: pressed),
                    at: 0
                )
            }
            previousButtons[label] = pressed
        }
        if events.count > 40 {
            events = Array(events.prefix(40))
        }
        return events
    }
}
