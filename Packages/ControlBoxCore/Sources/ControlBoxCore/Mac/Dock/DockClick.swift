import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Dock icon click, layered on the native click (listen-only). One plain
/// click is state-driven: app already in front with a visible window → the
/// front action (minimize / hide); no visible window on any current Space →
/// switch that display to the window's Space. Everything else stays native.
/// Clicks with any modifier held are left alone.
public enum DockClick {
    public static func configure(
        switchEnabled: Bool,
        frontAction: DockClickFrontAction,
        ignoredBundleIDs: [String] = []
    ) {
        Controller.shared.configure(
            switchEnabled: switchEnabled,
            frontAction: frontAction,
            ignoredBundleIDs: ignoredBundleIDs
        )
    }

    public static func stop() {
        WindowSpaces.cancel()
        configure(switchEnabled: false, frontAction: .none)
    }
}

private final class Controller: @unchecked Sendable {
    static let shared = Controller()

    private let lock = NSLock()
    private var switchEnabled = false
    private var frontAction: DockClickFrontAction = .none
    private var ignoredBundleIDs = Set<String>()
    private var port: CFMachPort?
    private var source: CFRunLoopSource?

    private var downPoint: CGPoint?
    private var downFlags: CGEventFlags = []
    /// Frontmost app at mouse-down. Dock activates the clicked app on the same
    /// click, so reading this at mouse-up would make every click look "in front".
    private var downFrontPID: pid_t = 0
    private var upPoint: CGPoint?
    private var scheduled = false

    func configure(
        switchEnabled: Bool,
        frontAction: DockClickFrontAction,
        ignoredBundleIDs: [String]
    ) {
        lock.lock()
        self.switchEnabled = switchEnabled
        self.frontAction = frontAction
        self.ignoredBundleIDs = Set(ignoredBundleIDs)
        let shouldRun = switchEnabled || frontAction != .none
        lock.unlock()
        if shouldRun {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        if port != nil { return }
        let mask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseUp.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, info in
                guard let info else { return Unmanaged.passUnretained(event) }
                let controller = Unmanaged<Controller>.fromOpaque(info).takeUnretainedValue()
                controller.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: userInfo
        ) else { return }
        let loopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), loopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        port = tap
        source = loopSource
    }

    private func stop() {
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        port = nil
        source = nil
        downPoint = nil
        upPoint = nil
        downFrontPID = 0
        scheduled = false
        ignoredBundleIDs = []
    }

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput, let port {
            CGEvent.tapEnable(tap: port, enable: true)
            return
        }
        if type == .leftMouseDown {
            downPoint = event.location
            downFlags = event.flags
            downFrontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
            upPoint = nil
        } else if type == .leftMouseUp {
            upPoint = event.location
        } else {
            return
        }
        guard !scheduled else { return }
        scheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.flush()
        }
    }

    private func flush() {
        scheduled = false
        lock.lock()
        let switching = switchEnabled
        let front = frontAction
        let ignored = ignoredBundleIDs
        lock.unlock()
        guard switching || front != .none, let down = downPoint, let up = upPoint else { return }
        let frontPID = downFrontPID
        downPoint = nil
        upPoint = nil
        // Modified clicks (Command-click reveals in Finder, Option-click hides
        // others, and so on) stay native.
        guard ModifierChords.live(downFlags).isEmpty else { return }
        guard hypot(up.x - down.x, up.y - down.y) < 10 else { return }
        if DockMenu.isVisible() { return }
        let cocoa = WindowLayout.cocoaFrame(
            from: CGRect(origin: down, size: CGSize(width: 1, height: 1))
        ).origin
        guard DockGeometry.isNearDock(cocoa) else { return }
        if DockGeometry.isAutoHidden(), !DockGeometry.isBarVisible() { return }
        guard let dest = WindowLayout.screen(containingQuartz: down) else { return }
        Task { @MainActor in
            guard let app = DockPreview.runningApp(atQuartz: down, requireHit: true) else { return }
            if app.bundleIdentifier == "com.apple.dock" { return }
            if let bid = app.bundleIdentifier, ignored.contains(bid) { return }
            guard AXIsProcessTrusted() else { return }
            self.performClick(
                app: app,
                dest: dest,
                wasFront: frontPID != 0 && self.relatedPIDs(for: app).contains(frontPID),
                switching: switching,
                front: front
            )
        }
    }

    @MainActor
    private func performClick(
        app: NSRunningApplication,
        dest: NSScreen,
        wasFront: Bool,
        switching: Bool,
        front: DockClickFrontAction
    ) {
        // Hidden (⌘H): native unhides. Stay out.
        if app.isHidden { return }

        let pids = relatedPIDs(for: app)
        let windows = DockPreviewWindows.list(app: app)
        let zOrder = Self.windowZOrder()
        let onThis = windows.filter { isVisible(on: dest, $0) }
        let elsewhere = windows.filter { isVisibleElsewhere(than: dest, $0) }
        let visibleAnywhere = onThis + elsewhere

        // No window list at all (AX missed it, e.g. some fullscreen apps):
        // switching by pid is the only thing we can add.
        if windows.isEmpty {
            if switching, !wasFront {
                _ = WindowSpaces.reveal(windowID: 0, pid: app.processIdentifier, pids: pids, bounds: .null)
            }
            return
        }

        // In front with a visible window: native does nothing visible. Front action.
        if wasFront, let top = mostRecent(visibleAnywhere, zOrder: zOrder) {
            if isFullscreenWindow(top) { return }
            switch front {
            case .none:
                return
            case .minimize:
                DockPreview.minimize(top)
            case .hide:
                app.hide()
            }
            DockPreview.dismiss()
            return
        }

        // Visible somewhere but not in front: native raises / activates.
        if !visibleAnywhere.isEmpty { return }

        // Nothing visible on any current Space. If a non-minimized window exists it
        // lives on another Space (or a fullscreen Space): switch there. If every
        // window is minimized, native restores the last one.
        guard switching else { return }
        let offSpace = windows.filter { !$0.isMinimized }
        var target = mostRecent(offSpace, zOrder: zOrder)
        if let current = target, !isFullscreenWindow(current),
           let fullscreen = mostRecent(offSpace.filter { isFullscreenWindow($0) }, zOrder: zOrder) {
            target = fullscreen
        }
        guard let window = target else { return }
        if isFullscreenWindow(window), displayContains(dest, window.bounds), window.isOnScreen {
            return
        }
        _ = WindowSpaces.reveal(
            windowID: window.windowID,
            pid: window.pid,
            pids: pids,
            bounds: window.bounds
        )
        DockPreview.dismiss()
    }

    private func isFullscreenWindow(_ window: DockPreviewWindow) -> Bool {
        DockWindowState.isFullscreen(window)
    }

    private func isVisible(on screen: NSScreen, _ window: DockPreviewWindow) -> Bool {
        DockWindowState.isVisible(on: screen, window)
    }

    private func isVisibleElsewhere(than screen: NSScreen, _ window: DockPreviewWindow) -> Bool {
        !window.isMinimized && window.isOnScreen && !displayContains(screen, window.bounds)
    }

    private func displayContains(_ screen: NSScreen, _ bounds: CGRect) -> Bool {
        DockWindowState.displayContains(screen, bounds)
    }

    private func mostRecent(
        _ windows: [DockPreviewWindow],
        zOrder: [CGWindowID: Int]
    ) -> DockPreviewWindow? {
        DockWindowState.mostRecent(windows, zOrder: zOrder)
    }

    private func relatedPIDs(for app: NSRunningApplication) -> Set<pid_t> {
        DockWindowState.relatedPIDs(for: app)
    }

    private static func windowZOrder() -> [CGWindowID: Int] {
        DockWindowState.windowZOrder()
    }
}

/// Window state shared by Dock-icon clicks and preview-card clicks.
enum DockWindowState {
    static func isFullscreen(_ window: DockPreviewWindow) -> Bool {
        if window.isMinimized { return false }
        if WindowSpaces.isFullscreen(window.windowID, pid: window.pid) { return true }
        if DockPreviewFocus.isFullscreen(window) { return true }
        for screen in NSScreen.screens {
            let frame = WindowLayout.quartzFrame(from: screen.frame)
            guard abs(window.bounds.width - frame.width) < 16,
                  abs(window.bounds.height - frame.height) < 16 else { continue }
            if displayContains(screen, window.bounds) { return true }
        }
        return false
    }

    static func isVisible(on screen: NSScreen, _ window: DockPreviewWindow) -> Bool {
        !window.isMinimized && window.isOnScreen && displayContains(screen, window.bounds)
    }

    /// On-screen on whichever display currently shows its Space.
    static func isVisibleAnywhere(_ window: DockPreviewWindow) -> Bool {
        !window.isMinimized && window.isOnScreen
    }

    static func displayContains(_ screen: NSScreen, _ bounds: CGRect) -> Bool {
        let frame = WindowLayout.quartzFrame(from: screen.frame).insetBy(dx: -2, dy: -2)
        return frame.contains(CGPoint(x: bounds.midX, y: bounds.midY))
    }

    static func screen(containing bounds: CGRect) -> NSScreen? {
        NSScreen.screens.first { displayContains($0, bounds) }
    }

    static func mostRecent(
        _ windows: [DockPreviewWindow],
        zOrder: [CGWindowID: Int]
    ) -> DockPreviewWindow? {
        windows.min { zIndex($0, zOrder) < zIndex($1, zOrder) }
    }

    static func zIndex(_ window: DockPreviewWindow, _ zOrder: [CGWindowID: Int]) -> Int {
        if window.windowID != 0, let index = zOrder[window.windowID] {
            return index
        }
        return Int.max
    }

    static func relatedPIDs(for app: NSRunningApplication) -> Set<pid_t> {
        var pids: Set<pid_t> = [app.processIdentifier]
        let bid = app.bundleIdentifier ?? ""
        for running in NSWorkspace.shared.runningApplications {
            if running.processIdentifier == app.processIdentifier { continue }
            guard let other = running.bundleIdentifier, !bid.isEmpty else { continue }
            if other == bid { pids.insert(running.processIdentifier) }
        }
        return pids
    }

    static func windowZOrder() -> [CGWindowID: Int] {
        let options: CGWindowListOption = [.excludeDesktopElements]
        let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        var order: [CGWindowID: Int] = [:]
        for (index, entry) in info.enumerated() {
            let id = CGWindowID((entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0)
            guard id != 0, order[id] == nil else { continue }
            order[id] = index
        }
        return order
    }
}
