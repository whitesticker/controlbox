import AppKit
import ControlBoxCore
import Observation
import SwiftUI

@Observable
@MainActor
final class ArrangementCatalog {
    var live = DisplayArrangement.snapshot()
    var store = ArrangementStore.empty
    var applyMessage: String?
    var applyFailed = false

    private static let defaultsKey = "controlbox.displayArrangements.v1"

    init() {
        store = Self.load()
        refresh()
        syncHotkey()
    }

    func refresh() {
        live = DisplayArrangement.snapshot()
        let before = store
        DisplayArrangement.reconcile(&store, live: live)
        if store != before {
            persist()
        }
    }

    var combos: [DisplayCombo] {
        store.combos.sorted { lhs, rhs in
            if lhs.id == live.comboID { return true }
            if rhs.id == live.comboID { return false }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    func presets(for comboID: String) -> [ArrangementPreset] {
        store.presets
            .filter { $0.comboID == comboID }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func canApply(_ preset: ArrangementPreset) -> Bool {
        DisplayArrangement.canApply(preset, live: live)
    }

    func matchesLive(_ preset: ArrangementPreset) -> Bool {
        DisplayArrangement.matchesLive(preset, live: live)
    }

    func applyBlockedReason(_ preset: ArrangementPreset) -> String? {
        if canApply(preset) { return nil }
        if DisplayArrangement.aligned(preset, to: live) == nil {
            let title = store.combos.first { $0.id == preset.comboID }?.title ?? "those displays"
            return "Connect \(title) to apply."
        }
        if preset.includesBuiltIn, !live.includesBuiltIn {
            return "Open the lid to apply this arrangement."
        }
        if !preset.includesBuiltIn, live.includesBuiltIn {
            return "Close the lid to apply this arrangement."
        }
        return "This arrangement does not match the displays that are connected now."
    }

    func saveCurrent() {
        refresh()
        let name = nextName(for: live.comboID)
        let preset = ArrangementPreset(
            name: name,
            comboID: live.comboID,
            includesBuiltIn: live.includesBuiltIn,
            screens: live.screens
        )
        DisplayArrangement.upsertCombo(live.combo, into: &store)
        store.presets.append(preset)
        persist()
        applyMessage = "Saved “\(name)”."
        applyFailed = false
    }

    func saveEditor(session: ArrangementEditorSession) {
        let screens = DisplayLayoutMath.normalized(session.screens)
        let includesBuiltIn = screens.contains(where: \.isBuiltIn)
        let combo = DisplayCombo(
            externals: screens.filter { !$0.isBuiltIn }.map {
                NamedDisplayIdentity(key: $0.identity, name: $0.name)
            }
        )
        DisplayArrangement.upsertCombo(combo, into: &store)
        let name = session.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = name.isEmpty ? nextName(for: combo.id) : name
        if let index = store.presets.firstIndex(where: { $0.id == session.presetID }) {
            store.presets[index].name = resolvedName
            store.presets[index].comboID = combo.id
            store.presets[index].includesBuiltIn = includesBuiltIn
            store.presets[index].screens = screens
        } else {
            store.presets.append(
                ArrangementPreset(
                    id: session.presetID,
                    name: resolvedName,
                    comboID: combo.id,
                    includesBuiltIn: includesBuiltIn,
                    screens: screens
                )
            )
        }
        persist()
        applyMessage = "Saved “\(resolvedName)”."
        applyFailed = false
        refresh()
    }

    func rename(_ preset: ArrangementPreset, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = store.presets.firstIndex(where: { $0.id == preset.id }) else { return }
        store.presets[index].name = trimmed
        persist()
    }

    func delete(_ preset: ArrangementPreset) {
        store.presets.removeAll { $0.id == preset.id }
        DisplayArrangement.pruneEmptyCombos(&store)
        persist()
    }

    func apply(_ preset: ArrangementPreset, hud: Bool = false) {
        applyMessage = nil
        switch DisplayArrangement.apply(preset) {
        case .applied:
            applyFailed = false
            applyMessage = nil
            if hud, let index = applicablePresets.firstIndex(where: { $0.id == preset.id }) {
                ArrangementHUD.show(
                    preset: preset,
                    index: index + 1,
                    count: applicablePresets.count
                )
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.refresh()
            }
        case .comboMismatch:
            applyFailed = true
            applyMessage = applyBlockedReason(preset)
        case .builtInMismatch:
            applyFailed = true
            applyMessage = applyBlockedReason(preset)
        case .missingDisplay(let name):
            applyFailed = true
            applyMessage = "\(name) is not connected."
        case .failed(let message):
            applyFailed = true
            applyMessage = message
        }
    }

    var applicablePresets: [ArrangementPreset] {
        store.presets
            .filter { canApply($0) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    var shortcutEnabled: Bool {
        get { store.resolvedShortcutEnabled }
        set {
            store.shortcutEnabled = newValue
            persist()
            syncHotkey()
        }
    }

    var shortcutFlags: UInt64 {
        get { store.resolvedShortcutFlags }
        set {
            store.shortcutFlags = newValue
            persist()
            syncHotkey()
        }
    }

    func handleHotkey(_ action: ArrangementHotkeyAction) {
        live = DisplayArrangement.snapshot()
        let list = applicablePresets
        guard !list.isEmpty else {
            ArrangementHUD.showUnavailable()
            return
        }
        switch action {
        case .index(let number):
            guard list.indices.contains(number - 1) else { return }
            apply(list[number - 1], hud: true)
        case .next:
            applyShuffled(in: list, delta: 1)
        case .previous:
            applyShuffled(in: list, delta: -1)
        }
    }

    private func applyShuffled(in list: [ArrangementPreset], delta: Int) {
        var index = shuffleIndex(in: list, delta: delta)
        for _ in 0..<list.count {
            apply(list[index], hud: true)
            if !applyFailed { return }
            index = (index + delta + list.count) % list.count
        }
    }

    private func shuffleIndex(in list: [ArrangementPreset], delta: Int) -> Int {
        let current = list.firstIndex { matchesLive($0) } ?? 0
        return (current + delta + list.count) % list.count
    }

    private func syncHotkey() {
        ArrangementHotkey.configure(
            enabled: store.resolvedShortcutEnabled,
            flags: CGEventFlags(rawValue: store.resolvedShortcutFlags)
        ) { [weak self] action in
            DispatchQueue.main.async {
                self?.handleHotkey(action)
            }
        }
    }

    func editorSession(for preset: ArrangementPreset) -> ArrangementEditorSession {
        ArrangementEditorSession(
            presetID: preset.id,
            name: preset.name,
            screens: screensForEditor(preset.screens),
            isNew: false
        )
    }

    func newEditorSession() -> ArrangementEditorSession {
        ArrangementEditorSession(
            presetID: UUID().uuidString,
            name: nextName(for: live.comboID),
            screens: live.screens,
            isNew: true
        )
    }

    private func screensForEditor(_ screens: [ArrangedScreen]) -> [ArrangedScreen] {
        screens.map { screen in
            guard let liveScreen = live.screens.first(where: { $0.identity == screen.identity }) else {
                return screen
            }
            var next = screen
            next.width = liveScreen.width
            next.height = liveScreen.height
            next.name = liveScreen.name
            return next
        }
    }

    private func nextName(for comboID: String) -> String {
        let count = store.presets.filter { $0.comboID == comboID }.count
        return count == 0 ? "Arrangement" : "Arrangement \(count + 1)"
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(store) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    private static func load() -> ArrangementStore {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let store = try? decoder.decode(ArrangementStore.self, from: data) else {
            return .empty
        }
        return store
    }
}

struct ArrangementEditorSession: Identifiable {
    var presetID: String
    var name: String
    var screens: [ArrangedScreen]
    var isNew: Bool
    var id: String { presetID }
}
