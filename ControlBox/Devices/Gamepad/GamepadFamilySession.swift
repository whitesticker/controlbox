import Foundation
import GameController
import ControlBoxCore

/// Pool of attached `GCController`s. One session per pad so several DualSenses
/// and several Xbox pads can stay live at once. Player 1–4 LEDs are assigned
/// while connected; GameController has no stable serial.
@MainActor
final class GamepadFamilySession: DeviceFamilySession {
    let familyID = "gamepad"
    let kinds: Set<DeviceKind> = [.dualSense, .dualSenseEdge, .gamepad]

    private let hidBattery = DualSenseHIDBatteryReader()
    private var slots: [LiveSlot] = []

    private struct LiveSlot {
        let objectID: ObjectIdentifier
        let session: GamepadSession
        var catalogID: String
        var hidAddress: String?
        var boundRecordID: String?
        var playerNumber: Int
        var nameOrdinal: Int
    }

    func start() {
        hidBattery.start()
        GCController.shouldMonitorBackgroundEvents = true
        GCController.startWirelessControllerDiscovery(completionHandler: nil)
    }

    func stop() {
        slots.forEach { $0.session.detach() }
        slots.removeAll()
        hidBattery.stop()
        GCController.stopWirelessControllerDiscovery()
    }

    func handleDisconnect(_ controller: GCController) {
        let id = ObjectIdentifier(controller)
        if let index = slots.firstIndex(where: { $0.objectID == id }) {
            slots[index].session.detach()
            slots.remove(at: index)
        }
    }

    func pulse(forRecordID recordID: String) {
        slots.first { $0.boundRecordID == recordID }?.session.pulse()
    }

    func snapshot(forRecordID recordID: String) -> GamepadSnapshot {
        slots.first { $0.boundRecordID == recordID }?.session.snapshot ?? GamepadSnapshot()
    }

    func sync(remembered records: [DeviceRecord], hid: [GamepadHIDPad]) {
        let controllers = GCController.controllers().filter { $0.extendedGamepad != nil }
        let live = GamepadIdentity.livePads(controllers: controllers, hid: hid)
        let liveIDs = Set(controllers.map { ObjectIdentifier($0) })

        for slot in slots where !liveIDs.contains(slot.objectID) {
            slot.session.detach()
        }
        slots.removeAll { !liveIDs.contains($0.objectID) }

        for (index, controller) in controllers.enumerated() {
            let objectID = ObjectIdentifier(controller)
            let pad = live[index]
            if let existing = slots.firstIndex(where: { $0.objectID == objectID }) {
                slots[existing].catalogID = pad.catalogID
                slots[existing].hidAddress = pad.hidAddress
                slots[existing].nameOrdinal = pad.nameOrdinal
                if let dual = slots[existing].session as? DualSenseSession {
                    dual.hidAddress = pad.hidAddress
                }
                continue
            }
            let session: GamepadSession
            if pad.kind == .dualSense || pad.kind == .dualSenseEdge {
                let dual = DualSenseSession()
                dual.hidBattery = hidBattery
                dual.hidAddress = pad.hidAddress
                session = dual
            } else {
                session = GamepadSession()
            }
            session.attach(controller)
            slots.append(
                LiveSlot(
                    objectID: objectID,
                    session: session,
                    catalogID: pad.catalogID,
                    hidAddress: pad.hidAddress,
                    boundRecordID: nil,
                    playerNumber: 0,
                    nameOrdinal: pad.nameOrdinal
                )
            )
        }

        bindRecords(records)
        assignPlayerNumbers(records)
    }

    func pollAll() -> [(recordID: String, session: GamepadSession)] {
        slots.compactMap { slot in
            guard let recordID = slot.boundRecordID else { return nil }
            return (recordID, slot.session)
        }
    }

    func playerNumber(forRecordID recordID: String) -> Int? {
        slots.first { $0.boundRecordID == recordID }?.playerNumber
    }

    func persistPlayerAssignments(into records: inout [DeviceRecord]) {
        for slot in slots {
            guard let recordID = slot.boundRecordID, slot.playerNumber >= 1 else { continue }
            guard let index = records.firstIndex(where: { $0.id == recordID }) else { continue }
            records[index].gamepadPlayerIndex = slot.playerNumber
        }
    }

    private func bindRecords(_ records: [DeviceRecord]) {
        var claimed = Set<String>()
        for index in slots.indices {
            slots[index].boundRecordID = nil
        }
        for index in slots.indices {
            let slot = slots[index]
            guard let record = matchRecord(for: slot, records: records, claimed: claimed) else { continue }
            slots[index].boundRecordID = record.id
            claimed.insert(record.id)
        }
    }

    private func matchRecord(
        for slot: LiveSlot,
        records: [DeviceRecord],
        claimed: Set<String>
    ) -> DeviceRecord? {
        let available = records.filter { record in
            record.remembered && slot.session.kinds.contains(record.kind) && !claimed.contains(record.id)
        }
        if let exact = available.first(where: { $0.id == slot.catalogID }) {
            return exact
        }
        if let hid = slot.hidAddress, DeviceIdentity.isConcrete(hid),
           let match = available.first(where: { DeviceIdentity.same($0.address, hid) }) {
            return match
        }
        if let match = available.first(where: { $0.address == "slot:\(slot.catalogID)" }) {
            return match
        }
        let nameMatches = available.filter { namesMatch($0.name, slot.session.vendorName) }
        if slot.nameOrdinal >= 1, slot.nameOrdinal <= nameMatches.count {
            return nameMatches[slot.nameOrdinal - 1]
        }
        return nameMatches.first
    }

    private func assignPlayerNumbers(_ records: [DeviceRecord]) {
        var used = Set<Int>()
        for index in slots.indices {
            let slot = slots[index]
            if let recordID = slot.boundRecordID,
               let preferred = records.first(where: { $0.id == recordID })?.gamepadPlayerIndex,
               preferred >= 1, preferred <= 4, !used.contains(preferred) {
                applyPlayerNumber(preferred, to: index)
                used.insert(preferred)
                continue
            }
            slots[index].playerNumber = 0
        }
        for index in slots.indices where slots[index].playerNumber == 0 {
            if let number = (1...4).first(where: { !used.contains($0) }) {
                applyPlayerNumber(number, to: index)
                used.insert(number)
            } else if let controller = slots[index].session.controller {
                controller.playerIndex = GCControllerPlayerIndex(rawValue: -1) ?? .index1
                slots[index].playerNumber = index + 1
            }
        }
    }

    private func applyPlayerNumber(_ number: Int, to index: Int) {
        slots[index].playerNumber = number
        if let controller = slots[index].session.controller,
           let led = GCControllerPlayerIndex(rawValue: number - 1) {
            controller.playerIndex = led
        }
    }

    private func namesMatch(_ lhs: String, _ rhs: String?) -> Bool {
        DeviceIdentity.namesMatch(lhs, rhs ?? "")
    }
}
