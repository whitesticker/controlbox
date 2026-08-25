import Foundation
import GameController

/// DualSense / DualSense Edge. Game Controller attach + snapshot only.
/// The host owns records, engines, and "Control this Mac".
@MainActor
final class DualSenseSession: DeviceFamilySession {
    let familyID = "dualsense"
    let kinds: Set<DeviceKind> = [.dualSense, .dualSenseEdge]

    private(set) var snapshot = DualSenseSnapshot()
    private var controller: GCController?
    private var previousButtons: [String: Bool] = [:]
    private let haptics = DualSenseHaptics()
    private let hidBattery = DualSenseHIDBatteryReader()

    var vendorName: String? { controller?.vendorName }
    var isAttached: Bool { controller != nil }

    func start() {
        hidBattery.start()
        GCController.shouldMonitorBackgroundEvents = true
        GCController.startWirelessControllerDiscovery(completionHandler: nil)
    }

    func stop() {
        hidBattery.stop()
        haptics.detach()
        controller = nil
        snapshot = DualSenseSnapshot()
        previousButtons = [:]
        GCController.stopWirelessControllerDiscovery()
    }

    func pulse() {
        haptics.pulse()
    }

    func attachPreferred(named preferredName: String?) {
        let dualSenses = GCController.controllers().filter { $0.extendedGamepad is GCDualSenseGamepad }
        guard !dualSenses.isEmpty else {
            detach()
            return
        }
        let match = dualSenses.first { controller in
            (controller.vendorName ?? "") == preferredName
        } ?? dualSenses.first
        attachIfNeeded(match)
    }

    func handleDisconnect(_ disconnected: GCController) {
        if controller == disconnected {
            detach()
        }
    }

    func detach() {
        if controller != nil {
            controller = nil
            haptics.detach()
            snapshot = DualSenseSnapshot()
            previousButtons = [:]
        }
    }

    func poll(hapticEnabled: Bool, wantMotion: Bool) {
        guard let controller else {
            if snapshot.connected {
                snapshot = DualSenseSnapshot()
            }
            return
        }

        var next = DualSenseSnapshot()
        next.connected = true
        next.name = controller.vendorName ?? "Game Controller"
        next.product = controller.productCategory
        next.playerIndex = controller.playerIndex.rawValue
        next.hasMotion = controller.motion != nil
        applyBattery(to: &next, controller: controller)

        if let pad = controller.extendedGamepad as? GCDualSenseGamepad {
            next.isDualSense = true
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
            next.options = isPressed(pad.buttonMenu)
            next.touchpadClick = pad.touchpadButton.isPressed
            next.l2 = pad.leftTrigger.value
            next.r2 = pad.rightTrigger.value
            next.leftStick = SIMD2(pad.leftThumbstick.xAxis.value, pad.leftThumbstick.yAxis.value)
            next.rightStick = SIMD2(pad.rightThumbstick.xAxis.value, pad.rightThumbstick.yAxis.value)
            next.touch1 = finger(from: pad.touchpadPrimary)
            next.touch2 = finger(from: pad.touchpadSecondary)
        } else if let pad = controller.extendedGamepad {
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
            next.l2 = pad.leftTrigger.value
            next.r2 = pad.rightTrigger.value
            next.leftStick = SIMD2(pad.leftThumbstick.xAxis.value, pad.leftThumbstick.yAxis.value)
            next.rightStick = SIMD2(pad.rightThumbstick.xAxis.value, pad.rightThumbstick.yAxis.value)
        }

        if let home = controller.physicalInputProfile.buttons[GCInputButtonHome] {
            next.ps = home.isPressed
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

    private func attachIfNeeded(_ incoming: GCController?) {
        guard let incoming, incoming.extendedGamepad is GCDualSenseGamepad else { return }
        if let current = controller, current == incoming { return }
        controller = incoming
        incoming.handlerQueue = .main
        incoming.motion?.sensorsActive = false
        previousButtons = [:]
        haptics.attach(incoming)
    }

    private func applyBattery(to next: inout DualSenseSnapshot, controller: GCController) {
        if let percent = hidBattery.percent {
            next.batteryAvailable = true
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

        guard let battery = controller.battery, battery.batteryState != .unknown else { return }
        next.batteryAvailable = true
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

    private func isPressed(_ button: GCControllerButtonInput?) -> Bool {
        button?.isPressed ?? false
    }

    private func finger(from pad: GCControllerDirectionPad) -> TouchFinger {
        let x = pad.xAxis.value
        let y = pad.yAxis.value
        let digital = pad.up.isPressed || pad.down.isPressed || pad.left.isPressed || pad.right.isPressed
        let analog = abs(x) > 0.001 || abs(y) > 0.001
        return TouchFinger(x: x, y: y, active: digital || analog)
    }

    private func updatedEvents(from next: DualSenseSnapshot) -> [InputLogEvent] {
        let current: [(String, Bool)] = [
            ("Cross", next.cross),
            ("Circle", next.circle),
            ("Square", next.square),
            ("Triangle", next.triangle),
            ("D-pad Up", next.dpadUp),
            ("D-pad Down", next.dpadDown),
            ("D-pad Left", next.dpadLeft),
            ("D-pad Right", next.dpadRight),
            ("L1", next.l1),
            ("R1", next.r1),
            ("L2", next.l2 > 0.15),
            ("R2", next.r2 > 0.15),
            ("L3", next.l3),
            ("R3", next.r3),
            ("Create", next.create),
            ("Options", next.options),
            ("PS", next.ps),
            ("Touchpad click", next.touchpadClick),
            ("Touch 1", next.touch1.active),
            ("Touch 2", next.touch2.active)
        ]

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
