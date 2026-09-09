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
    var showDockNames = true
    var hasScreenRecording = false

    private var shouldSuppress: () -> Bool = { false }
    private static let defaultsKey = "controlbox.dockPreview.v1"

    init() {
        load()
        refreshScreenRecording()
        if !showDockNames {
            applyDockNames(false)
            persist()
        }
        if enabled {
            start()
        }
        if switcherEnabled {
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
        if on {
            startSwitcher()
        } else {
            AppSwitcherPreview.stop()
            AppSwitcherPreviewOverlay.shared.hide()
        }
    }

    func setShowDockNames(_ on: Bool) {
        guard on != showDockNames else { return }
        showDockNames = on
        applyDockNames(on)
        persist()
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
        AppSwitcherPreview.configure(enabled: true) { hover in
            if let hover {
                DockPreview.dismiss()
                AppSwitcherPreviewOverlay.shared.show(hover)
            } else {
                AppSwitcherPreviewOverlay.shared.hide()
            }
        }
    }

    private func applyDockNames(_ show: Bool) {
        if show {
            DockFileLabel.restore(labelBackup)
            labelBackup = []
        } else {
            labelBackup = DockFileLabel.hide(existing: labelBackup)
        }
    }

    private func persist() {
        let store = Store(
            enabled: enabled,
            switcherEnabled: switcherEnabled,
            showDelay: showDelay,
            cardScale: cardScale,
            switcherCardScale: switcherCardScale,
            showDockNames: showDockNames,
            labelBackup: labelBackup
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
        showDockNames = store.showDockNames ?? true
        switcherEnabled = store.switcherEnabled ?? false
        switcherCardScale = min(
            max(store.switcherCardScale ?? DockPreview.defaultCardScale, DockPreview.minCardScale),
            DockPreview.maxSwitcherCardScale
        )
        labelBackup = store.labelBackup ?? []
        DockPreviewOverlay.shared.cardScale = cardScale
        AppSwitcherPreviewOverlay.shared.cardScale = switcherCardScale
    }

    private var labelBackup: [DockFileLabel.BackupItem] = []

    private struct Store: Codable {
        var enabled: Bool
        var switcherEnabled: Bool?
        var showDelay: TimeInterval
        var cardScale: CGFloat?
        var switcherCardScale: CGFloat?
        var showDockNames: Bool?
        var labelBackup: [DockFileLabel.BackupItem]?
    }
}
