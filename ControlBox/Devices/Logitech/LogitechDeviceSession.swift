import Foundation
import ControlBoxCore

@MainActor
protocol LogitechMouseDevice: AnyObject {
    var current: MXMasterSnapshot { get }
    var injectEnabled: Bool { get set }
    var wheelsEnabled: Bool { get set }

    func pollGesturePointer()
    func consumePendingGesture() -> DeviceButton?
    func consumePendingScroll()
    func setManaged(_ managed: Bool)
    func setGestureOwners(_ buttons: Set<DeviceButton>)
    func setCapturedButtons(_ buttons: Set<DeviceButton>)
    func applySensorDPI(_ dpi: Int)
    func applyPointerSpeed(_ speed: Double)
    func applySmartShift(mode: MXRatchetMode, sensitivity: Int)
    func applyThumbWheelInvert(_ invert: Bool)
    func applySmoothScrolling(_ enabled: Bool)
    func applyScrollDirection(_ natural: Bool)
    func reloadEasySwitchHosts()
    func setFriendlyName(_ name: String)
}

extension LogitechMouseReader: LogitechMouseDevice {}

@MainActor
protocol LogitechKeyboardDevice: AnyObject {
    var snapshot: MXKeyboardSnapshot { get }

    func setBacklightEnabled(_ enabled: Bool)
    func setBacklightEffect(_ effect: MXKeyboardBacklightEffect)
    func setBatterySaving(_ enabled: Bool)
    func reloadEasySwitchHosts()
    func setFriendlyName(_ name: String)
}

extension MXKeyboardSession: LogitechKeyboardDevice {}

/// Logitech device-family boundary. The host sees one lifecycle and delegates
/// receiver routing here; model readers keep their isolated HID managers.
///
/// Add Logitech protocol families here rather than adding another reader,
/// Bolt branch, or lifecycle call to `DualSenseMonitor`.
@MainActor
final class LogitechDeviceSession: DeviceFamilySession {
    let familyID = "logitech"
    private let keyboardSession = MXKeyboardSession()
    private let hidppMouseReaders: [LogitechMouseReader]
    private var boltCatalog: LogiBoltCatalog?

    init() {
        hidppMouseReaders = (1...10).map { _ in LogitechMouseReader() }
        for reader in hidppMouseReaders {
            reader.onIdentityChanged = { [weak self] in
                guard let self, let catalog = self.boltCatalog else { return }
                self.syncBolt(using: catalog)
            }
        }
    }

    var kinds: Set<DeviceKind> {
        Set([
            .logitechMXMaster,
            .logitechMXMaster3,
            .logitechMXMaster3S,
            .logitechMXMaster4,
            .logitechMouse
        ]).union(keyboardSession.kinds)
    }

    var mouseReaders: [any LogitechMouseDevice] {
        hidppMouseReaders
    }

    var keyboard: any LogitechKeyboardDevice {
        keyboardSession
    }

    func start() {
        hidppMouseReaders.forEach { $0.start() }
        keyboardSession.start()
    }

    func stop() {
        hidppMouseReaders.forEach { $0.stop() }
        keyboardSession.stop()
    }

    func mouseReader(for key: LogitechDeviceKey) -> (any LogitechMouseDevice)? {
        if let exact = hidppMouseReaders.first(where: { reader in
            let current = reader.current
            return current.connected
                && DeviceIdentity.sameLogitech(current.logitechKey, key)
        }) {
            return exact
        }
        if key.kind == .logitechMouse,
           DeviceIdentity.isConcrete(key.address) || key.unitID != nil {
            return nil
        }
        let sameModel = hidppMouseReaders.filter { reader in
            let current = reader.current.logitechKey
            return reader.current.connected
                && current.connection == key.connection
                && current.wirelessProductID == key.wirelessProductID
                && DeviceIdentity.logitechNamesEquivalent(current.name, key.name)
        }
        return sameModel.count == 1 ? sameModel[0] : nil
    }

    func syncBolt(using catalog: LogiBoltCatalog) {
        boltCatalog = catalog
        if catalog.isTalkSuspended {
            hidppMouseReaders.forEach { $0.detachBolt() }
            keyboardSession.detachBolt()
            return
        }

        let online = catalog.receivers
            .flatMap(\.devices)
            .filter { $0.online && $0.deviceKind.isSupported }
        let bluetoothKeys = hidppMouseReaders.compactMap { reader -> LogitechDeviceKey? in
            reader.usesBluetoothHIDPP && reader.current.connected
                ? reader.current.logitechKey
                : nil
        }
        let boltCandidates = online.filter { device in
            !bluetoothKeys.contains {
                DeviceIdentity.sameLogitech($0, device.logitechKey)
            }
        }
        var claimedBoltSlots = Set(hidppMouseReaders.compactMap(\.boltSlotID))
        for reader in hidppMouseReaders {
            let currentID = reader.boltSlotID
            let candidates = boltCandidates
                .filter { $0.deviceKind.isMXMaster }
                .filter { device in
                    let id = "\(device.receiverID)-\(device.slot)"
                    return id == currentID || !claimedBoltSlots.contains(id)
                }
            syncBoltMouse(
                reader,
                candidates: candidates,
                catalog: catalog
            )
            if let id = reader.boltSlotID {
                claimedBoltSlots.insert(id)
            }
        }
        syncBoltKeyboard(
            candidates: online.filter(\.deviceKind.isMXKeyboard),
            catalog: catalog
        )
    }

    private func syncBoltMouse(
        _ reader: LogitechMouseReader,
        candidates: [LogiBoltPairedDevice],
        catalog: LogiBoltCatalog
    ) {
        if reader.usesBluetoothHIDPP {
            reader.detachBolt()
            return
        }
        guard let device = preferredBoltDevice(candidates, currentID: reader.boltSlotID) else {
            reader.detachBolt()
            return
        }
        let slotID = "\(device.receiverID)-\(device.slot)"
        if reader.boltSlotID == slotID, reader.current.connected { return }
        guard let link = catalog.talkLink(receiverID: device.receiverID, slot: device.slot) else {
            reader.detachBolt()
            return
        }
        if !reader.attachBolt(
            link,
            name: device.displayName,
            kind: device.deviceKind,
            address: device.identityAddress,
            unitID: device.unitID,
            wpid: device.wpid
        ) {
            catalog.releaseTalkLink(link)
        }
    }

    private func syncBoltKeyboard(
        candidates: [LogiBoltPairedDevice],
        catalog: LogiBoltCatalog
    ) {
        if keyboardSession.usesBluetoothHIDPP {
            keyboardSession.detachBolt()
            return
        }
        guard let device = preferredBoltDevice(candidates, currentID: keyboardSession.boltSlotID) else {
            keyboardSession.detachBolt()
            return
        }
        let slotID = "\(device.receiverID)-\(device.slot)"
        if keyboardSession.boltSlotID == slotID, keyboardSession.snapshot.connected { return }
        guard let link = catalog.talkLink(receiverID: device.receiverID, slot: device.slot) else {
            keyboardSession.detachBolt()
            return
        }
        if !keyboardSession.attachBolt(
            link,
            name: device.displayName,
            kind: device.deviceKind,
            address: device.identityAddress,
            unitID: device.unitID,
            wpid: device.wpid
        ) {
            catalog.releaseTalkLink(link)
        }
    }

    private func preferredBoltDevice(
        _ candidates: [LogiBoltPairedDevice],
        currentID: String?
    ) -> LogiBoltPairedDevice? {
        if let currentID,
           let current = candidates.first(where: {
               "\($0.receiverID)-\($0.slot)" == currentID
           }) {
            return current
        }
        return candidates.sorted { lhs, rhs in
            if lhs.receiverID != rhs.receiverID {
                return lhs.receiverID < rhs.receiverID
            }
            return lhs.slot < rhs.slot
        }.first
    }
}
