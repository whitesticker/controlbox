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

    func attachBolt(
        _ link: LogiBoltHIDPPLink,
        name: String,
        kind: DeviceKind,
        address: String,
        unitID: UInt32,
        wpid: Int
    ) -> Bool {
        reader.attachBolt(link, name: name, kind: kind, address: address, unitID: unitID, wpid: wpid)
    }

    func detachBolt() {
        reader.detachBolt()
    }

    var usesBluetoothHIDPP: Bool { reader.usesBluetoothHIDPP }

    var usesBoltHIDPP: Bool { reader.usesBoltHIDPP }

    var boltSlotID: String? { reader.boltSlotID }

    func setBacklightEnabled(_ enabled: Bool) {
        reader.setBacklightEnabled(enabled)
    }

    func setBacklightEffect(_ effect: MXKeyboardBacklightEffect) {
        reader.setBacklightEffect(effect)
    }

    func setBatterySaving(_ enabled: Bool) {
        reader.setBatterySaving(enabled)
    }

    func reloadEasySwitchHosts() {
        reader.reloadEasySwitchHosts()
    }

    func setFriendlyName(_ name: String) {
        reader.setFriendlyName(name)
    }
}
