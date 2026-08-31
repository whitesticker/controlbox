import ControlBoxCore
import CoreGraphics
import Foundation
import Observation

@Observable
@MainActor
final class CapsLockCatalog {
    var enabled = false
    var isHeld = false
    var flags: UInt64 = CapsLockModifier.defaultMappedFlags.rawValue

    private static let defaultsKey = "controlbox.capsLock.v1"

    init() {
        load()
        if enabled {
            start()
        }
    }

    func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        persist()
        if on {
            start()
        } else {
            stop()
        }
    }

    func setFlags(_ value: UInt64) {
        let next = ModifierChords.normalized(value)
        guard ModifierChords.count(next) >= 1 else { return }
        guard next.rawValue != flags else { return }
        flags = next.rawValue
        CapsLockModifier.mappedFlags = next
        persist()
    }

    func invalidate() {
        stop()
    }

    private func start() {
        CapsLockModifier.mappedFlags = ModifierChords.normalized(flags)
        CapsLockModifier.onHoldChange = { [weak self] held in
            Task { @MainActor in
                self?.isHeld = held
            }
        }
        CapsLockModifier.start()
        isHeld = CapsLockModifier.isHeld
    }

    private func stop() {
        CapsLockModifier.onHoldChange = nil
        CapsLockModifier.stop()
        CapsLockModifier.mappedFlags = []
        isHeld = false
    }

    private func persist() {
        let store = Store(enabled: enabled, flags: flags)
        if let data = try? JSONEncoder().encode(store) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let store = try? JSONDecoder().decode(Store.self, from: data) else { return }
        enabled = store.enabled
        let next = ModifierChords.normalized(store.flags ?? CapsLockModifier.defaultMappedFlags.rawValue)
        flags = ModifierChords.count(next) >= 1
            ? next.rawValue
            : CapsLockModifier.defaultMappedFlags.rawValue
    }

    private struct Store: Codable {
        var enabled: Bool
        var flags: UInt64?
    }
}
