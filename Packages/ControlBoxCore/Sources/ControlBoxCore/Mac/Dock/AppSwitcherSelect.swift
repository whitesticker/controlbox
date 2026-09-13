import AppKit
import CoreGraphics
import Foundation

/// Command-Tab release on an app that has no window on any current Space:
/// slide that window's display (this or another) to its Space. Native
/// activation has already happened; if Apple moved the display itself,
/// `WindowSpaces` sees the Space is current and does nothing.
enum AppSwitcherSelect {
    static func perform(_ app: NSRunningApplication) {
        // Let the native switcher's activation land first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            MainActor.assumeIsolated {
                run(app)
            }
        }
    }

    @MainActor
    private static func run(_ app: NSRunningApplication) {
        if app.isTerminated || app.isHidden { return }
        let pids = DockWindowState.relatedPIDs(for: app)
        let windows = DockPreviewWindows.list(app: app)

        if windows.isEmpty {
            _ = WindowSpaces.reveal(windowID: 0, pid: app.processIdentifier, pids: pids, bounds: .null)
            return
        }
        // Something already showing on a current Space: native handles it.
        // CG on-screen can be stale for fullscreen windows; ask the Space list.
        let showing = windows.contains { window in
            guard DockWindowState.isVisibleAnywhere(window) else { return false }
            if let current = WindowSpaces.fullscreenSpaceIsCurrent(window.windowID) { return current }
            return true
        }
        if showing { return }

        let offSpace = windows.filter { !$0.isMinimized }
        let zOrder = DockWindowState.windowZOrder()
        var target = DockWindowState.mostRecent(offSpace, zOrder: zOrder)
        if let current = target, !DockWindowState.isFullscreen(current),
           let fullscreen = DockWindowState.mostRecent(
               offSpace.filter { DockWindowState.isFullscreen($0) },
               zOrder: zOrder
           ) {
            target = fullscreen
        }
        // All minimized: native restores the last one.
        guard let window = target else { return }
        _ = WindowSpaces.reveal(
            windowID: window.windowID,
            pid: window.pid,
            pids: pids,
            bounds: window.bounds
        )
    }
}
