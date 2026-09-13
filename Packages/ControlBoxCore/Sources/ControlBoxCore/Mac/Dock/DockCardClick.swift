import AppKit
import CoreGraphics
import Foundation

/// Click on a Dock preview card. The target window is known, so this is a
/// smaller tree than `DockClick`:
///
/// - minimized → restore + raise (native card behavior)
/// - fullscreen: its Space is current on its display → activate; else Switch to Space
/// - visible: app in front and this is its top window → front action; else raise
/// - on another Space → Switch to Space, else fall back to the AX raise
///
/// App switcher cards do not come here; they keep the plain focus.
public enum DockCardClick {
    private static let lock = NSLock()
    private static var switchEnabled = false
    private static var frontAction: DockClickFrontAction = .none

    public static func configure(switchEnabled: Bool, frontAction: DockClickFrontAction) {
        lock.lock()
        Self.switchEnabled = switchEnabled
        Self.frontAction = frontAction
        lock.unlock()
    }

    /// Runs on the main queue. `frontPID` is the app that was frontmost when the
    /// card was clicked (the panel is non-activating); nil reads it now.
    public static func perform(_ window: DockPreviewWindow, frontPID: pid_t? = nil) {
        let work = { @MainActor in
            run(window, frontPID: frontPID ?? NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0)
        }
        if Thread.isMainThread {
            MainActor.assumeIsolated(work)
        } else {
            DispatchQueue.main.async {
                MainActor.assumeIsolated(work)
            }
        }
    }

    @MainActor
    private static func run(_ window: DockPreviewWindow, frontPID: pid_t) {
        lock.lock()
        let switching = switchEnabled
        let front = frontAction
        lock.unlock()

        guard let app = NSRunningApplication(processIdentifier: window.pid) else {
            DockPreview.focus(window)
            return
        }
        let pids = DockWindowState.relatedPIDs(for: app)
        let wasFront = frontPID != 0 && pids.contains(frontPID)

        if window.isMinimized {
            DockPreview.focus(window)
            return
        }

        let fullscreen = DockWindowState.isFullscreen(window)
        let visible = DockWindowState.isVisibleAnywhere(window)

        if fullscreen {
            if visible {
                app.activate(options: [.activateIgnoringOtherApps])
                DockPreview.dismiss()
                return
            }
            if switching {
                reveal(window, pids: pids)
                return
            }
            DockPreview.focus(window)
            return
        }

        if visible {
            if wasFront, front != .none, isTopWindow(window, of: app) {
                switch front {
                case .minimize:
                    DockPreview.minimize(window)
                case .hide:
                    app.hide()
                case .none:
                    break
                }
                DockPreview.dismiss()
                return
            }
            DockPreview.focus(window)
            return
        }

        // Another Space.
        if switching {
            reveal(window, pids: pids)
            return
        }
        DockPreview.focus(window)
    }

    @MainActor
    private static func reveal(_ window: DockPreviewWindow, pids: Set<pid_t>) {
        DockPreview.dismiss()
        _ = WindowSpaces.reveal(
            windowID: window.windowID,
            pid: window.pid,
            pids: pids,
            bounds: window.bounds
        )
    }

    @MainActor
    private static func isTopWindow(_ window: DockPreviewWindow, of app: NSRunningApplication) -> Bool {
        let zOrder = DockWindowState.windowZOrder()
        let visible = DockPreviewWindows.list(app: app).filter { DockWindowState.isVisibleAnywhere($0) }
        guard let top = DockWindowState.mostRecent(visible, zOrder: zOrder) else { return true }
        return top.windowID == window.windowID
    }
}
