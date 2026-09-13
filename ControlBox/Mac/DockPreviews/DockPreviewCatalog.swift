import AppKit
import ControlBoxCore
import Foundation
import Observation

@Observable
@MainActor
final class DockPreviewCatalog {
    var enabled = false
    var switcherEnabled = false
    var showDelay = DockPreview.defaultShowDelay
    var cardScale = DockPreview.defaultCardScale
    var switcherCardScale = DockPreview.defaultCardScale
    var cardSwitchToSpace = false
    var cardFrontAction: DockClickFrontAction = .none
    var switcherSelectSwitchToSpace = false
    var hasScreenRecording = false

    private var shouldSuppress: () -> Bool = { false }
    private static let defaultsKey = "controlbox.dockPreview.v1"

    init() {
        load()
        applyCardClick()
        refreshScreenRecording()
        if enabled {
            start()
        }
        if switcherEnabled || switcherSelectSwitchToSpace {
            startSwitcher()
        }
    }

    func attachSuppress(_ block: @escaping () -> Bool) {
        shouldSuppress = block
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
            DockPreview.stop()
            DockPreviewOverlay.shared.hide()
        }
    }

    func setShowDelay(_ value: TimeInterval) {
        let next = min(max(value, 0.08), 1.2)
        guard abs(next - showDelay) > 0.001 else { return }
        showDelay = next
        persist()
        if enabled {
            start()
        }
    }

    func setCardScale(_ value: CGFloat) {
        let next = min(max(value, DockPreview.minCardScale), DockPreview.maxCardScale)
        guard abs(next - cardScale) > 0.001 else { return }
        cardScale = next
        persist()
        DockPreviewOverlay.shared.cardScale = next
    }

    func setSwitcherCardScale(_ value: CGFloat) {
        let next = min(max(value, DockPreview.minCardScale), DockPreview.maxSwitcherCardScale)
        guard abs(next - switcherCardScale) > 0.001 else { return }
        switcherCardScale = next
        persist()
        AppSwitcherPreviewOverlay.shared.cardScale = next
    }

    func setSwitcherEnabled(_ on: Bool) {
        guard on != switcherEnabled else { return }
        switcherEnabled = on
        persist()
        applySwitcher()
    }

    func setSwitcherSelectSwitchToSpace(_ on: Bool) {
        guard on != switcherSelectSwitchToSpace else { return }
        switcherSelectSwitchToSpace = on
        persist()
        applySwitcher()
    }

    private func applySwitcher() {
        if switcherEnabled || switcherSelectSwitchToSpace {
            startSwitcher()
        } else {
            AppSwitcherPreview.stop()
        }
        if !switcherEnabled {
            AppSwitcherPreviewOverlay.shared.hide()
        }
    }

    func setCardSwitchToSpace(_ on: Bool) {
        guard on != cardSwitchToSpace else { return }
        cardSwitchToSpace = on
        persist()
        applyCardClick()
    }

    func setCardFrontAction(_ action: DockClickFrontAction) {
        guard action != cardFrontAction else { return }
        cardFrontAction = action
        persist()
        applyCardClick()
    }

    private func applyCardClick() {
        DockCardClick.configure(switchEnabled: cardSwitchToSpace, frontAction: cardFrontAction)
    }

    func refreshScreenRecording() {
        hasScreenRecording = DockPreview.hasScreenRecordingAccess
    }

    func requestScreenRecording() {
        hasScreenRecording = DockPreview.requestScreenRecordingAccess()
    }

    func openScreenRecordingSettings() {
        DockPreview.openScreenRecordingSettings()
    }

    private func start() {
        DockPreviewOverlay.shared.cardScale = cardScale
        DockPreview.configure(
            enabled: true,
            showDelay: showDelay,
            shouldSuppress: { [weak self] in
                self?.shouldSuppress() ?? false
            },
            onChange: { hover in
                if let hover {
                    DockPreviewOverlay.shared.show(hover)
                } else {
                    DockPreviewOverlay.shared.hide()
                }
            }
        )
    }

    private func startSwitcher() {
        AppSwitcherPreviewOverlay.shared.cardScale = switcherCardScale
        AppSwitcherPreview.configure(
            enabled: switcherEnabled,
            selectEnabled: switcherSelectSwitchToSpace
        ) { hover in
            if let hover {
                DockPreview.dismiss()
                AppSwitcherPreviewOverlay.shared.show(hover)
            } else {
                AppSwitcherPreviewOverlay.shared.hide()
            }
        }
    }

    private func persist() {
        let store = Store(
            enabled: enabled,
            switcherEnabled: switcherEnabled,
            showDelay: showDelay,
            cardScale: cardScale,
            switcherCardScale: switcherCardScale,
            cardSwitchToSpace: cardSwitchToSpace,
            cardFrontAction: cardFrontAction,
            switcherSelectSwitchToSpace: switcherSelectSwitchToSpace
        )
        if let data = try? JSONEncoder().encode(store) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let store = try? JSONDecoder().decode(Store.self, from: data) else { return }
        enabled = store.enabled
        showDelay = min(max(store.showDelay, 0.08), 1.2)
        cardScale = min(
            max(store.cardScale ?? DockPreview.defaultCardScale, DockPreview.minCardScale),
            DockPreview.maxCardScale
        )
        switcherEnabled = store.switcherEnabled ?? false
        switcherCardScale = min(
            max(store.switcherCardScale ?? DockPreview.defaultCardScale, DockPreview.minCardScale),
            DockPreview.maxSwitcherCardScale
        )
        cardSwitchToSpace = store.cardSwitchToSpace ?? false
        cardFrontAction = store.cardFrontAction ?? .none
        switcherSelectSwitchToSpace = store.switcherSelectSwitchToSpace ?? false
        if let backup = store.labelBackup, !backup.isEmpty {
            DockFileLabel.restore(backup)
            persist()
        }
        DockPreviewOverlay.shared.cardScale = cardScale
        AppSwitcherPreviewOverlay.shared.cardScale = switcherCardScale
    }

    private struct Store: Codable {
        var enabled: Bool
        var switcherEnabled: Bool?
        var showDelay: TimeInterval
        var cardScale: CGFloat?
        var switcherCardScale: CGFloat?
        var cardSwitchToSpace: Bool?
        var cardFrontAction: DockClickFrontAction?
        var switcherSelectSwitchToSpace: Bool?
        var showDockNames: Bool?
        var labelBackup: [DockFileLabel.BackupItem]?
    }
}
