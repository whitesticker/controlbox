import Foundation

/// MX Mechanical / Mini family. HID++ settings only — do not divert keys.
@MainActor
final class MXKeyboardSession: DeviceFamilySession {
    let familyID = "mx-keyboard"
    let kinds: Set<DeviceKind> = [.logitechMXMechanical, .logitechMXMechanicalMini]

    private let reader = MXKeyboardReader()

    var snapshot: MXKeyboardSnapshot { reader.current }

    func start() {
        reader.start()
    }

    func stop() {
        reader.stop()
    }

    func setBacklightEnabled(_ enabled: Bool) {
        reader.setBacklightEnabled(enabled)
    }

    func setBacklightEffect(_ effect: MXKeyboardBacklightEffect) {
        reader.setBacklightEffect(effect)
    }

    func setBatterySaving(_ enabled: Bool) {
        reader.setBatterySaving(enabled)
    }
}
