import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

public enum DockPreviewEdge: Sendable {
    case bottom
    case top
    case left
    case right
}

public struct DockPreviewWindow: Identifiable, Equatable, Sendable {
    public var windowID: CGWindowID
    public var pid: pid_t
    public var title: String
    public var bounds: CGRect
    public var isMinimized: Bool
    public var isOnScreen: Bool

    public var id: String { "\(pid)-\(windowID)-\(title)" }
}

public struct DockPreviewHover {
    public var bundleID: String
    public var appName: String
    public var appIcon: NSImage
    public var iconFrame: CGRect
    public var edge: DockPreviewEdge
    public var windows: [DockPreviewWindow]
}

@MainActor
public enum DockPreview {
    public static let overlayTitle = "Control Box Dock Preview"
    public static let defaultShowDelay: TimeInterval = 0.25
    public static let defaultCardScale: CGFloat = 1.3
    public static let minCardScale: CGFloat = 0.8
    public static let maxCardScale: CGFloat = 2.0

    public static func configure(
        enabled: Bool,
        showDelay: TimeInterval,
        shouldSuppress: @escaping () -> Bool,
        onChange: @escaping (DockPreviewHover?) -> Void
    ) {
        if Thread.isMainThread {
            Controller.shared.configure(
                enabled: enabled,
                showDelay: showDelay,
                shouldSuppress: shouldSuppress,
                onChange: onChange
            )
        } else {
            DispatchQueue.main.async {
                Controller.shared.configure(
                    enabled: enabled,
                    showDelay: showDelay,
                    shouldSuppress: shouldSuppress,
                    onChange: onChange
                )
            }
        }
    }

    public static func stop() {
        configure(
            enabled: false,
            showDelay: defaultShowDelay,
            shouldSuppress: { false },
            onChange: { _ in }
        )
    }

    public static func setKeepAliveRect(_ rect: CGRect) {
        setKeepAliveRect(rect, panelFrame: .zero)
    }

    public static func setKeepAliveRect(_ rect: CGRect, panelFrame: CGRect) {
        if Thread.isMainThread {
            Controller.shared.keepAliveRect = rect
            Controller.shared.panelFrame = panelFrame
        } else {
            DispatchQueue.main.async {
                Controller.shared.keepAliveRect = rect
                Controller.shared.panelFrame = panelFrame
            }
        }
    }

    public static var dockStrip: CGRect {
        DockGeometry.strip(containing: NSEvent.mouseLocation)
    }

    public static func dockStrip(containing point: CGPoint) -> CGRect {
        DockGeometry.strip(containing: point)
    }

    public static func hideAnimationDuration() -> TimeInterval {
        DockGeometry.hideAnimationDuration()
    }

    /// How far the revealed Dock sticks out from the screen edge. Uses the icon
    /// AX frame when it looks real; otherwise tilesize so a hidden/instant Dock
    /// does not pin the panel to the display edge.
    public static func dockClearance(icon: CGRect, edge: DockPreviewEdge) -> CGFloat {
        DockGeometry.revealedClearance(icon: icon, edge: edge)
    }

    public static func dismiss() {
        if Thread.isMainThread {
            Controller.shared.dismissImmediately()
        } else {
            DispatchQueue.main.async {
                Controller.shared.dismissImmediately()
            }
        }
    }

    public static func focus(_ window: DockPreviewWindow) {
        DockPreviewFocus.raise(window)
        dismiss()
    }

    public static func close(_ window: DockPreviewWindow) {
        if Thread.isMainThread {
            Controller.shared.closeWindow(window)
        } else {
            DispatchQueue.main.async {
                Controller.shared.closeWindow(window)
            }
        }
    }

    public static func quit(_ window: DockPreviewWindow) {
        DockPreviewFocus.quit(window)
        dismiss()
    }

    public static func minimize(_ window: DockPreviewWindow) {
        if Thread.isMainThread {
            Controller.shared.minimizeWindow(window)
        } else {
            DispatchQueue.main.async {
                Controller.shared.minimizeWindow(window)
            }
        }
    }

    public static func restore(_ window: DockPreviewWindow) {
        if Thread.isMainThread {
            Controller.shared.restoreWindow(window)
        } else {
            DispatchQueue.main.async {
                Controller.shared.restoreWindow(window)
            }
        }
    }

    public static func thumbnails(
        for windows: [DockPreviewWindow],
        maxPixelWidth: CGFloat
    ) async -> [CGWindowID: NSImage] {
        await DockPreviewCapture.stills(for: windows, maxPixelWidth: maxPixelWidth)
    }

    public static var hasScreenRecordingAccess: Bool {
        CGPreflightScreenCaptureAccess()
    }

    public static func requestScreenRecordingAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    public static func openScreenRecordingSettings() {
        let prefixes = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?",
            "x-apple.systempreferences:com.apple.preference.security?"
        ]
        for prefix in prefixes {
            if let url = URL(string: prefix + "Privacy_ScreenCapture"),
               NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}

@MainActor
private final class Controller {
    static let shared = Controller()

    var keepAliveRect = CGRect.zero
    var panelFrame = CGRect.zero

    private var enabled = false
    private var showDelay = DockPreview.defaultShowDelay
    private var shouldSuppress: () -> Bool = { false }
    private var onChange: (DockPreviewHover?) -> Void = { _ in }

    private var localMove: Any?
    private var globalLeft: Any?
    private var globalRight: Any?
    private var tapPort: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var debounce: DispatchWorkItem?
    private var dismissWork: DispatchWorkItem?
    private var hovered: DockPreviewHover?
    private var pendingID: String?
    private var lastIcon: (id: String, frame: CGRect, app: NSRunningApplication)?
    private var revealRetry: DispatchWorkItem?
    private var axObserver: AXObserver?
    private var screenObserver: NSObjectProtocol?
    private var resolveQueued = false
    private var tileCache: [DockIcon] = []
    private var lastAXRefresh = Date.distantPast
    private var runningSnapshot: [NSRunningApplication] = []
    private var menuHold = false
    private var menuHoldAt = Date.distantPast

    func configure(
        enabled: Bool,
        showDelay: TimeInterval,
        shouldSuppress: @escaping () -> Bool,
        onChange: @escaping (DockPreviewHover?) -> Void
    ) {
        self.showDelay = min(max(showDelay, 0.08), 1.2)
        self.shouldSuppress = shouldSuppress
        self.onChange = onChange
        let wasEnabled = self.enabled
        self.enabled = enabled
        if enabled {
            startMonitors()
        } else if wasEnabled {
            stopMonitors()
            cancelRevealRetry()
            clearHover()
        }
    }

    func dismissImmediately() {
        debounce?.cancel()
        debounce = nil
        pendingID = nil
        cancelRevealRetry()
        clearHover()
    }

    private func startMonitors() {
        if tapPort != nil || localMove != nil { return }
        localMove = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.handleMouseMove()
            return event
        }
        globalLeft = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            DispatchQueue.main.async { self?.handleOutsideClick() }
        }
        globalRight = NSEvent.addGlobalMonitorForEvents(matching: .rightMouseDown) { [weak self] _ in
            DispatchQueue.main.async { self?.handleRightMouse() }
        }
        startTap()
        startDockObserver()
        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.lastAXRefresh = .distantPast
                self?.handleMouseMove()
            }
        }
    }

    private func startTap() {
        if tapPort != nil { return }
        let mask = CGEventMask(1 << CGEventType.mouseMoved.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseDragged.rawValue)
            | CGEventMask(1 << CGEventType.rightMouseDragged.rawValue)
            | CGEventMask(1 << CGEventType.otherMouseDragged.rawValue)
            | CGEventMask(1 << CGEventType.rightMouseDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, _ in
                DispatchQueue.main.async {
                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        Controller.shared.reenableTap()
                    } else if type == .rightMouseDown {
                        Controller.shared.handleRightMouse()
                    } else {
                        Controller.shared.handleMouseMove()
                    }
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: nil
        ) else { return }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        tapPort = tap
        tapSource = source
    }

    fileprivate func reenableTap() {
        if let tapPort {
            CGEvent.tapEnable(tap: tapPort, enable: true)
        }
    }

    private func stopMonitors() {
        if let tapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes)
        }
        if let tapPort {
            CGEvent.tapEnable(tap: tapPort, enable: false)
            CFMachPortInvalidate(tapPort)
        }
        tapPort = nil
        tapSource = nil
        if let localMove { NSEvent.removeMonitor(localMove) }
        if let globalLeft { NSEvent.removeMonitor(globalLeft) }
        if let globalRight { NSEvent.removeMonitor(globalRight) }
        localMove = nil
        globalLeft = nil
        globalRight = nil
        stopDockObserver()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        screenObserver = nil
    }

    private func startDockObserver() {
        stopDockObserver()
        guard let pid = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock")
            .first?.processIdentifier
        else { return }
        var observer: AXObserver?
        let status = AXObserverCreate(pid, { _, _, _, _ in
            DispatchQueue.main.async {
                Controller.shared.lastAXRefresh = .distantPast
                Controller.shared.handleMouseMove()
            }
        }, &observer)
        guard status == .success, let observer else { return }
        let dock = AXUIElementCreateApplication(pid)
        AXObserverAddNotification(observer, dock, kAXSelectedChildrenChangedNotification as CFString, nil)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        axObserver = observer
    }

    private func stopDockObserver() {
        if let axObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(axObserver), .commonModes)
        }
        axObserver = nil
    }

    private func handleOutsideClick() {
        let point = NSEvent.mouseLocation
        if panelFrame.contains(point) {
            return
        }
        dismissImmediately()
    }

    fileprivate func handleRightMouse() {
        menuHold = true
        menuHoldAt = Date()
        dismissImmediately()
    }

    func closeWindow(_ window: DockPreviewWindow) {
        DockPreviewFocus.close(window)
        guard var hover = hovered else { return }
        hover.windows.removeAll { $0.id == window.id }
        if hover.windows.isEmpty {
            clearHover()
            return
        }
        hovered = hover
        onChange(hover)
    }

    func minimizeWindow(_ window: DockPreviewWindow) {
        DockPreviewFocus.minimize(window)
        guard var hover = hovered else { return }
        guard let index = hover.windows.firstIndex(where: { $0.id == window.id }) else { return }
        hover.windows[index].isMinimized = true
        hover.windows[index].isOnScreen = false
        hovered = hover
        onChange(hover)
    }

    func restoreWindow(_ window: DockPreviewWindow) {
        DockPreviewFocus.restore(window)
        guard var hover = hovered else { return }
        guard let index = hover.windows.firstIndex(where: { $0.id == window.id }) else { return }
        hover.windows[index].isMinimized = false
        hover.windows[index].isOnScreen = true
        hovered = hover
        onChange(hover)
    }

    private func handleMouseMove() {
        guard enabled else { return }
        guard !resolveQueued else { return }
        resolveQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.resolveQueued = false
            self.resolveHover(fromMove: true)
        }
    }

    private func resolveHover(fromMove: Bool) {
        guard enabled else { return }
        let cocoa = NSEvent.mouseLocation
        if shouldSuppress() || WindowGrab.isBusy || WindowGrab.grabChordHeld(Self.cgFlags(NSEvent.modifierFlags)) {
            dismissImmediately()
            return
        }
        if menuHold {
            let waitingForMenu = Date().timeIntervalSince(menuHoldAt) < 0.2
            if waitingForMenu || DockMenu.isVisible() {
                if hovered != nil {
                    dismissImmediately()
                }
                return
            }
            menuHold = false
        }

        if hovered != nil, panelFrame.contains(cocoa) || keepAliveRect.contains(cocoa) {
            dismissWork?.cancel()
            dismissWork = nil
            cancelRevealRetry()
            return
        }

        let onDock = isNearDock(cocoa)
        if !onDock, panelFrame.contains(cocoa) {
            dismissWork?.cancel()
            dismissWork = nil
            cancelRevealRetry()
            return
        }
        if !onDock, keepAliveRect.contains(cocoa) {
            dismissWork?.cancel()
            dismissWork = nil
            return
        }

        let showing = hovered != nil
        if showing, !onDock, !isNearKeepAlive(cocoa) {
            dismissImmediately()
            return
        }
        if !onDock {
            cancelRevealRetry()
            if pendingID != nil {
                debounce?.cancel()
                pendingID = nil
            }
            if showing {
                scheduleDismiss()
            }
            return
        }

        guard let item = dockIcon(at: cocoa) else {
            if showing {
                scheduleDismiss()
            } else {
                scheduleRevealRetry()
            }
            return
        }

        cancelRevealRetry()
        dismissWork?.cancel()
        dismissWork = nil

        let id = item.app.bundleIdentifier ?? item.app.localizedName ?? "\(item.app.processIdentifier)"
        if id == hovered?.bundleID {
            if let current = hovered, iconFrameMoved(current.iconFrame, item.frame) {
                var next = current
                next.iconFrame = item.frame
                next.edge = item.edge
                hovered = next
                onChange(next)
            }
            return
        }
        if id == pendingID, !showing {
            return
        }

        pendingID = id
        debounce?.cancel()
        let delay: TimeInterval
        if showing {
            delay = 0
        } else if isDockAutoHidden() {
            delay = max(showDelay, 0.28)
        } else {
            delay = fromMove ? showDelay : 0
        }
        if delay <= 0 {
            reveal(item, id: id)
            return
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lastAXRefresh = .distantPast
            if let fresh = self.dockIcon(at: NSEvent.mouseLocation),
               (fresh.app.bundleIdentifier ?? fresh.app.localizedName ?? "\(fresh.app.processIdentifier)") == id {
                self.reveal(fresh, id: id)
            } else {
                self.reveal(item, id: id)
            }
        }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func scheduleRevealRetry() {
        guard revealRetry == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.revealRetry = nil
            self.resolveHover(fromMove: false)
        }
        revealRetry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: work)
    }

    private func cancelRevealRetry() {
        revealRetry?.cancel()
        revealRetry = nil
    }

    private func iconFrameMoved(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.midX - b.midX) > 4 || abs(a.midY - b.midY) > 4
            || abs(a.width - b.width) > 6 || abs(a.height - b.height) > 6
    }

    private func reveal(_ item: DockIcon, id: String) {
        guard enabled, pendingID == id else { return }
        pendingID = nil
        let windows = DockPreviewWindows.list(app: item.app)
        if windows.isEmpty {
            if hovered != nil {
                clearHover()
            }
            return
        }
        let hover = DockPreviewHover(
            bundleID: id,
            appName: item.app.localizedName ?? id,
            appIcon: item.app.icon ?? NSWorkspace.shared.icon(forFile: item.app.bundleURL?.path ?? ""),
            iconFrame: item.frame,
            edge: item.edge,
            windows: windows
        )
        hovered = hover
        onChange(hover)
    }

    private func scheduleDismiss() {
        guard hovered != nil || pendingID != nil else { return }
        guard dismissWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.clearHover()
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func clearHover() {
        debounce?.cancel()
        debounce = nil
        pendingID = nil
        cancelRevealRetry()
        dismissWork?.cancel()
        dismissWork = nil
        keepAliveRect = .zero
        panelFrame = .zero
        guard hovered != nil else { return }
        hovered = nil
        onChange(nil)
    }

    private struct DockIcon {
        var app: NSRunningApplication
        var frame: CGRect
        var edge: DockPreviewEdge
    }

    private func dockIcon(at cocoaPoint: NSPoint) -> DockIcon? {
        if let hit = hitInCache(cocoaPoint) {
            remember(hit)
            return hit
        }
        if Date().timeIntervalSince(lastAXRefresh) < 0.12 {
            return rememberIfNeeded(nearestTile(tileCache, to: cocoaPoint))
        }
        refreshTileCache(at: cocoaPoint)
        if let hit = hitInCache(cocoaPoint) {
            remember(hit)
            return hit
        }
        return rememberIfNeeded(nearestTile(tileCache, to: cocoaPoint))
    }

    private func hitInCache(_ point: NSPoint) -> DockIcon? {
        tileCache.first { $0.frame.insetBy(dx: -8, dy: -8).contains(point) }
    }

    private func remember(_ icon: DockIcon) {
        let id = icon.app.bundleIdentifier ?? icon.app.localizedName ?? "\(icon.app.processIdentifier)"
        lastIcon = (id, icon.frame, icon.app)
    }

    private func rememberIfNeeded(_ icon: DockIcon?) -> DockIcon? {
        if let icon { remember(icon) }
        return icon
    }

    private func refreshTileCache(at cocoaPoint: NSPoint) {
        lastAXRefresh = Date()
        guard let pid = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock")
            .first?.processIdentifier
        else {
            tileCache = []
            return
        }
        runningSnapshot = NSWorkspace.shared.runningApplications
        let dock = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(dock, 0.08)
        let quartzPoint = CGEvent(source: nil)?.location ?? WindowLayout.quartzFrame(
            from: CGRect(origin: cocoaPoint, size: CGSize(width: 1, height: 1))
        ).origin
        let edge = DockGeometry.edge(containing: cocoaPoint)
        var tiles: [DockIcon] = []
        collectTiles(in: dock, depth: 0, cocoaPoint: cocoaPoint, quartzPoint: quartzPoint, edge: edge, into: &tiles)
        tileCache = tiles
        runningSnapshot = []
    }

    private func collectTiles(
        in element: AXUIElement,
        depth: Int,
        cocoaPoint: NSPoint,
        quartzPoint: CGPoint,
        edge: DockPreviewEdge,
        into tiles: inout [DockIcon]
    ) {
        guard depth < 8 else { return }
        if let icon = tile(at: element, cocoaPoint: cocoaPoint, quartzPoint: quartzPoint, edge: edge, requireHit: false) {
            tiles.append(icon)
        }
        for child in DockAX.children(of: element) ?? [] {
            collectTiles(
                in: child,
                depth: depth + 1,
                cocoaPoint: cocoaPoint,
                quartzPoint: quartzPoint,
                edge: edge,
                into: &tiles
            )
        }
    }

    private func nearestTile(_ tiles: [DockIcon], to point: NSPoint) -> DockIcon? {
        let nearest = tiles.min { a, b in
            hypot(a.frame.midX - point.x, a.frame.midY - point.y)
                < hypot(b.frame.midX - point.x, b.frame.midY - point.y)
        }
        guard let nearest else { return nil }
        let distance = hypot(nearest.frame.midX - point.x, nearest.frame.midY - point.y)
        return distance < 140 ? nearest : nil
    }

    private func tile(
        at item: AXUIElement,
        cocoaPoint: NSPoint,
        quartzPoint: CGPoint,
        edge: DockPreviewEdge,
        requireHit: Bool = true
    ) -> DockIcon? {
        guard isApplicationTile(item) else { return nil }
        let cocoa: CGRect
        if requireHit {
            guard let hit = DockAX.hitFrame(of: item, cocoaPoint: cocoaPoint, quartzPoint: quartzPoint) else {
                return nil
            }
            cocoa = hit
        } else {
            cocoa = DockAX.cocoaFrame(of: item)
            guard cocoa.width > 4, cocoa.height > 4 else { return nil }
        }
        guard let app = runningApp(for: item) else { return nil }
        let id = app.bundleIdentifier ?? app.localizedName ?? "\(app.processIdentifier)"
        lastIcon = (id, cocoa, app)
        return DockIcon(app: app, frame: cocoa, edge: edge)
    }

    private func isApplicationTile(_ item: AXUIElement) -> Bool {
        let role = DockAX.string(item, kAXRoleAttribute as CFString)
        let sub = DockAX.string(item, kAXSubroleAttribute as CFString)
        if role == "AXApplication" || role == "AXList" || role == "AXGroup" { return false }
        if role == "AXApplicationDockItem" || sub == "AXApplicationDockItem" { return true }
        if role == "AXDockItem" || sub == "AXDockItem" {
            return DockAX.url(item) != nil || !DockAX.string(item, kAXTitleAttribute as CFString).isEmpty
        }
        return false
    }

    private func runningApp(for item: AXUIElement) -> NSRunningApplication? {
        let running = runningSnapshot.isEmpty ? NSWorkspace.shared.runningApplications : runningSnapshot
        if let url = DockAX.url(item) {
            let bid = Bundle(url: url)?.bundleIdentifier
            if let bid, let match = running.first(where: { $0.bundleIdentifier == bid }) {
                return match
            }
            if let match = running.first(where: {
                $0.bundleURL?.standardizedFileURL == url.standardizedFileURL
            }) {
                return match
            }
        }
        let title = DockAX.string(item, kAXTitleAttribute as CFString)
        if !title.isEmpty {
            if let match = running.first(where: { ($0.localizedName ?? "").caseInsensitiveCompare(title) == .orderedSame }) {
                return match
            }
            return running.first {
                let name = $0.localizedName ?? ""
                return !name.isEmpty && (title.hasPrefix(name) || name.hasPrefix(title))
            }
        }
        return nil
    }

    private func isNearDock(_ point: NSPoint) -> Bool {
        DockGeometry.isNearDock(point)
    }

    private func isNearKeepAlive(_ point: NSPoint) -> Bool {
        guard keepAliveRect != .zero else { return false }
        return keepAliveRect.insetBy(dx: -30, dy: -30).contains(point)
    }

    private func isDockAutoHidden() -> Bool {
        DockGeometry.isAutoHidden()
    }

    private static func cgFlags(_ flags: NSEvent.ModifierFlags) -> CGEventFlags {
        var next = CGEventFlags(rawValue: 0)
        if flags.contains(.control) { next.insert(.maskControl) }
        if flags.contains(.shift) { next.insert(.maskShift) }
        if flags.contains(.option) { next.insert(.maskAlternate) }
        if flags.contains(.command) { next.insert(.maskCommand) }
        return next
    }
}

enum DockGeometry {
    static func preferredEdge() -> DockPreviewEdge {
        switch storedOrientation() {
        case "left": return .left
        case "right": return .right
        case "top": return .top
        case "bottom": return .bottom
        default: return inferredEdge()
        }
    }

    static func edge(containing point: NSPoint) -> DockPreviewEdge {
        if let match = strips().first(where: { $0.frame.insetBy(dx: -20, dy: -20).contains(point) }) {
            return match.edge
        }
        return preferredEdge()
    }

    static func isAutoHidden() -> Bool {
        if let value = CFPreferencesCopyAppValue("autohide" as CFString, "com.apple.dock" as CFString) as? Bool {
            return value
        }
        return UserDefaults(suiteName: "com.apple.dock")?.bool(forKey: "autohide") ?? false
    }

    /// Stock Dock hide/show is ~0.25s. `autohide-time-modifier` scales it (0 = instant).
    static func hideAnimationDuration() -> TimeInterval {
        let raw = CFPreferencesCopyAppValue("autohide-time-modifier" as CFString, "com.apple.dock" as CFString)
        let modifier: Double
        if let number = raw as? NSNumber {
            modifier = number.doubleValue
        } else if let value = raw as? Double {
            modifier = value
        } else {
            modifier = 1
        }
        return min(max(0.25 * max(modifier, 0), 0.04), 0.8)
    }

    static func isNearDock(_ point: NSPoint) -> Bool {
        strips().contains { $0.frame.insetBy(dx: -16, dy: -16).contains(point) }
    }

    static func revealedClearance(icon: CGRect, edge: DockPreviewEdge) -> CGFloat {
        let iconPoint = CGPoint(x: icon.midX, y: icon.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(iconPoint) }
            ?? NSScreen.screens.first { $0.frame.intersects(icon) }
            ?? NSScreen.main
        let full = screen?.frame ?? icon
        let fromIcon: CGFloat
        switch edge {
        case .bottom: fromIcon = icon.maxY - full.minY
        case .top: fromIcon = full.maxY - icon.minY
        case .left: fromIcon = icon.maxX - full.minX
        case .right: fromIcon = full.maxX - icon.minX
        }
        let minimum = tileSize() + 28
        if fromIcon >= tileSize() * 0.65 {
            return fromIcon
        }
        return max(fromIcon, minimum)
    }

    static func strip(containing point: NSPoint) -> CGRect {
        if let match = strips().first(where: { $0.frame.insetBy(dx: -20, dy: -20).contains(point) }) {
            return match.frame
        }
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) {
            return strip(on: screen, edge: preferredEdge())
        }
        return strips().first?.frame ?? .zero
    }

    private struct Strip {
        var edge: DockPreviewEdge
        var frame: CGRect
    }

    private static func strips() -> [Strip] {
        let preferred = preferredEdge()
        return NSScreen.screens.map { screen in
            let live = insets(screen).max(by: { $0.1 < $1.1 })
            let edge: DockPreviewEdge
            if let live, live.1 > 8 {
                edge = live.0
            } else {
                edge = preferred
            }
            return Strip(edge: edge, frame: strip(on: screen, edge: edge))
        }
    }

    private static func storedOrientation() -> String? {
        if let value = CFPreferencesCopyAppValue("orientation" as CFString, "com.apple.dock" as CFString) as? String {
            return value
        }
        return UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation")
    }

    private static func inferredEdge() -> DockPreviewEdge {
        var best: (DockPreviewEdge, CGFloat) = (.bottom, 0)
        for screen in NSScreen.screens {
            for (side, size) in insets(screen) where size > best.1 {
                best = (side, size)
            }
        }
        return best.0
    }

    private static func insets(_ screen: NSScreen) -> [(DockPreviewEdge, CGFloat)] {
        let full = screen.frame
        let visible = screen.visibleFrame
        let top = full.maxY - visible.maxY
        return [
            (.bottom, visible.minY - full.minY),
            (.left, visible.minX - full.minX),
            (.right, full.maxX - visible.maxX),
            (.top, top > 50 ? top : 0)
        ]
    }

    private static func tileSize() -> CGFloat {
        if let value = CFPreferencesCopyAppValue("tilesize" as CFString, "com.apple.dock" as CFString) as? Double {
            return CGFloat(value)
        }
        return 64
    }

    private static func strip(on screen: NSScreen, edge: DockPreviewEdge) -> CGRect {
        let full = screen.frame
        let visible = screen.visibleFrame
        let minimum = tileSize() + 20
        switch edge {
        case .bottom:
            let height = max(visible.minY - full.minY, minimum)
            return CGRect(x: full.minX, y: full.minY, width: full.width, height: height)
        case .top:
            let height = max(full.maxY - visible.maxY, minimum)
            return CGRect(x: full.minX, y: full.maxY - height, width: full.width, height: height)
        case .left:
            let width = max(visible.minX - full.minX, minimum)
            return CGRect(x: full.minX, y: full.minY, width: width, height: full.height)
        case .right:
            let width = max(full.maxX - visible.maxX, minimum)
            return CGRect(x: full.maxX - width, y: full.minY, width: width, height: full.height)
        }
    }
}

enum DockMenu {
    static func isVisible() -> Bool {
        let options: CGWindowListOption = [.optionOnScreenOnly]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        for entry in info {
            let layer = entry[kCGWindowLayer as String] as? Int ?? 0
            guard layer >= 101 else { continue }
            let owner = entry[kCGWindowOwnerName as String] as? String ?? ""
            if owner == DockPreview.overlayTitle { continue }
            let name = entry[kCGWindowName as String] as? String ?? ""
            if name == DockPreview.overlayTitle { continue }
            guard let bounds = entry[kCGWindowBounds as String] as? [String: Any] else { continue }
            func number(_ key: String) -> CGFloat? {
                if let value = bounds[key] as? NSNumber { return CGFloat(truncating: value) }
                return nil
            }
            guard let width = number("Width"), let height = number("Height"),
                  width > 60, height > 24 else { continue }
            if owner == "Dock" || layer == 101 {
                return true
            }
        }
        return false
    }
}

enum DockAX {
    static func children(of element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let array = value as? [AXUIElement] else {
            return nil
        }
        return array
    }

    static func string(_ element: AXUIElement, _ attribute: CFString) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return "" }
        return value as? String ?? ""
    }

    static func url(_ element: AXUIElement) -> URL? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXURL" as CFString, &value) == .success else {
            return nil
        }
        return value as? URL
    }

    static func parent(of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    static func cocoaFrame(of element: AXUIElement) -> CGRect {
        let raw = quartzFrame(of: element)
        guard raw.width > 1, raw.height > 1 else { return .zero }
        return WindowLayout.cocoaFrame(from: raw)
    }

    static func quartzFrame(of element: AXUIElement) -> CGRect {
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXFrame" as CFString, &value) == .success,
           let value,
           CFGetTypeID(value) == AXValueGetTypeID() {
            var frame = CGRect.zero
            AXValueGetValue(value as! AXValue, .cgRect, &frame)
            if frame.width > 1, frame.height > 1 {
                return frame
            }
        }
        return axFrame(element) ?? .zero
    }

    static func hitFrame(of element: AXUIElement, cocoaPoint: NSPoint, quartzPoint: CGPoint) -> CGRect? {
        let raw = quartzFrame(of: element)
        guard raw.width > 1, raw.height > 1 else { return nil }
        let padded = raw.insetBy(dx: -10, dy: -10)
        if padded.contains(quartzPoint) {
            return WindowLayout.cocoaFrame(from: raw)
        }
        if padded.contains(cocoaPoint) {
            return raw
        }
        return nil
    }

    static func axFrame(_ element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }

    static func bool(_ element: AXUIElement, _ attribute: CFString) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let number = value as? NSNumber else {
            return false
        }
        return number.boolValue
    }
}
