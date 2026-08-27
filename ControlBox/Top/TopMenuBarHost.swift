import AppKit
import Combine
import Foundation

/// Opens the System Monitor pane even if the main window is still being created.
enum TopNavigation {
    static var pendingOpen = false

    @MainActor
    static func openSystemMonitorPane() {
        pendingOpen = true
        WindowActions.openMain?("main")
        NotificationCenter.default.post(name: .controlBoxOpenSystemMonitor, object: nil)
        NSApp.activate()
    }
}

/// Owns the *top* menu bar extra. Control Box already has a gamecontroller
/// `MenuBarExtra`; this is a second `NSStatusItem` (live ↑/↓ network icon +
/// dashboard menu) that only exists while System Monitor is enabled.
@MainActor
final class TopMenuBarHost {
    static let shared = TopMenuBarHost()

    private var statusController: StatusItemController?
    private var prefsCancellable: AnyCancellable?

    private init() {}

    func start() {
        guard prefsCancellable == nil else { return }
        prefsCancellable = PreferencesStore.shared.$menuBarEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                self?.apply(enabled: enabled)
            }
        apply(enabled: PreferencesStore.shared.menuBarEnabled)
    }

    func stop() {
        prefsCancellable?.cancel()
        prefsCancellable = nil
        apply(enabled: false)
    }

    private func apply(enabled: Bool) {
        if enabled {
            guard statusController == nil else { return }
            statusController = StatusItemController(monitor: SystemMonitor.shared)
            SystemMonitor.shared.start()
        } else {
            statusController?.invalidate()
            statusController = nil
            SystemMonitor.shared.stop()
        }
    }
}
