import AppKit
import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

/// Hold modifiers and move the pointer to drag, resize, or throw the
/// window under the cursor. Organize is a recorded shortcut on
/// `WindowOrganizeHotkey` that tiles windows on the pointer’s screen.
/// Windows are found via the window server so Firefox / Electron still
/// match when Accessibility hit-testing is empty.
public enum WindowGrab {
    public static func configure(
        enabled: Bool,
        moveEnabled: Bool,
        resizeEnabled: Bool,
        throwEnabled: Bool,
        moveFlags: CGEventFlags,
        resizeFlags: CGEventFlags,
        throwFlags: CGEventFlags
    ) {
        Controller.shared.configure(
            enabled: enabled,
            moveEnabled: moveEnabled,
            resizeEnabled: resizeEnabled,
            throwEnabled: throwEnabled,
            moveFlags: moveFlags,
            resizeFlags: resizeFlags,
            throwFlags: throwFlags
        )
    }

    public static func stop() {
        configure(
            enabled: false,
            moveEnabled: false,
            resizeEnabled: false,
            throwEnabled: false,
            moveFlags: [],
            resizeFlags: [],
            throwFlags: []
        )
    }

    public static func organizeAtPointer() {
        Controller.shared.organizeAtPointer()
    }

    public static var isBusy: Bool {
        Controller.shared.isBusy
    }

    public static func grabChordHeld(_ flags: CGEventFlags) -> Bool {
        Controller.shared.grabChordHeld(flags)
    }
}

private final class Controller: @unchecked Sendable {
    static let shared = Controller()

    private let systemWide = AXUIElementCreateSystemWide()
    private let lock = NSLock()
    private var enabled = false
    private var moveEnabled = false
    private var resizeEnabled = false
    private var throwEnabled = false
    private var moveFlags: CGEventFlags = .maskControl
    private var resizeFlags: CGEventFlags = [.maskControl, .maskShift]
    private var throwFlags: CGEventFlags = [.maskControl, .maskAlternate]
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var lastPoint = CGPoint.zero
    private var lastFlags: CGEventFlags = []
    private var lastType: CGEventType = .mouseMoved
    private var hasPoint = false
    private var session: Session?
    private var throwSession: ThrowSession?
    private var pendingPoint: CGPoint?
    private var writing = false
    private var tickTimer: Timer?
    private var lastOrganizeIDs = Set<CGWindowID>()
    private var organizeRotation = 0

    private struct Session {
        var window: AXUIElement
        var windowID: CGWindowID
        var startFrame: CGRect
        var startPoint: CGPoint
        var moving: Bool
    }

    private struct ThrowSession {
        var window: AXUIElement
        var zone: ThrowZone
        var visible: CGRect
    }

    init() {
        AXUIElementSetMessagingTimeout(systemWide, 0.2)
    }

    var isBusy: Bool {
        lock.lock()
        defer { lock.unlock() }
        return session != nil || throwSession != nil
    }

    func grabChordHeld(_ flags: CGEventFlags) -> Bool {
        lock.lock()
        let on = enabled
        let move = moveEnabled ? moveFlags : []
        let resize = resizeEnabled ? resizeFlags : []
        let throwHeld = throwEnabled ? throwFlags : []
        lock.unlock()
        guard on else { return false }
        let current = ModifierChords.live(flags)
        if !move.isEmpty, current == ModifierChords.normalized(move) { return true }
        if !resize.isEmpty, current == ModifierChords.normalized(resize) { return true }
        if !throwHeld.isEmpty, current == ModifierChords.normalized(throwHeld) { return true }
        return false
    }

    func configure(
        enabled: Bool,
        moveEnabled: Bool,
        resizeEnabled: Bool,
        throwEnabled: Bool,
        moveFlags: CGEventFlags,
        resizeFlags: CGEventFlags,
        throwFlags: CGEventFlags
    ) {
        lock.lock()
        self.enabled = enabled && (moveEnabled || resizeEnabled || throwEnabled)
        self.moveEnabled = moveEnabled
        self.resizeEnabled = resizeEnabled
        self.throwEnabled = throwEnabled
        self.moveFlags = moveFlags
        self.resizeFlags = resizeFlags
        self.throwFlags = throwFlags
        let shouldRun = self.enabled
        lock.unlock()
        if shouldRun {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        if port != nil { return }
        let mask = CGEventMask(1 << CGEventType.mouseMoved.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseDragged.rawValue)
            | CGEventMask(1 << CGEventType.rightMouseDragged.rawValue)
            | CGEventMask(1 << CGEventType.otherMouseDragged.rawValue)
            | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
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
        startTick()
    }

    private func stop() {
        endGrabSession()
        endThrow()
        stopTick()
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        port = nil
        source = nil
        hasPoint = false
    }

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput, let port {
            CGEvent.tapEnable(tap: port, enable: true)
            return
        }
        // Stash only. Accessibility from inside a session tap beachballs
        // the app (and can stall all input) when another window is the target.
        lastPoint = event.location
        lastFlags = event.flags
        lastType = type
        hasPoint = true
        pendingPoint = event.location
    }

    private func handleGrab(mode: PointerMode, point: CGPoint) {
        if let session, session.moving != (mode == .move) {
            retarget(session, moving: mode == .move, point: point)
        }
        if session == nil {
            guard let hit = hit(at: point) else { return }
            session = Session(
                window: hit.window,
                windowID: hit.windowID,
                startFrame: hit.bounds,
                startPoint: point,
                moving: mode == .move
            )
            AXUIElementSetMessagingTimeout(hit.window, 0.2)
            NSCursor.setHiddenUntilMouseMoves(false)
            if mode == .move {
                NSCursor.closedHand.set()
            } else {
                NSCursor.crosshair.set()
            }
        }
        if mode == .move, let session {
            WindowShake.noteGrab(
                window: session.window,
                windowID: session.windowID,
                bounds: session.startFrame,
                point: point
            )
        }
        pendingPoint = point
    }

    private func handleThrow(at point: CGPoint) {
        let visible = WindowLayout.visibleFrame(containingQuartz: point)
        if var current = throwSession {
            let zone = WindowLayout.zone(at: point, in: visible, previous: current.zone)
            WindowThrowOverlay.show(quartzVisible: visible, zone: zone)
            if zone != current.zone || visible != current.visible {
                applyFrame(WindowLayout.frame(for: zone, in: visible), to: current.window)
                current.zone = zone
                current.visible = visible
                throwSession = current
            }
            return
        }
        guard let hit = hit(at: point), !isFullscreen(hit.window) else { return }
        let zone = WindowLayout.zone(at: point, in: visible, previous: nil)
        throwSession = ThrowSession(window: hit.window, zone: zone, visible: visible)
        AXUIElementSetMessagingTimeout(hit.window, 0.2)
        WindowThrowOverlay.show(quartzVisible: visible, zone: zone)
        applyFrame(WindowLayout.frame(for: zone, in: visible), to: hit.window)
    }

    func organizeAtPointer() {
        let point = CGEvent(source: nil)?.location ?? lastPoint
        organizeWindows(at: point)
    }

    private func organizeWindows(at point: CGPoint) {
        let visible = WindowLayout.visibleFrame(containingQuartz: point)
        let windows = listedWindows(in: visible)
        guard !windows.isEmpty else { return }
        let ids = Set(windows.map(\.windowID).filter { $0 != 0 })
        if !ids.isEmpty, ids == lastOrganizeIDs {
            organizeRotation = (organizeRotation + 1) % windows.count
        } else {
            lastOrganizeIDs = ids
            organizeRotation = 0
        }
        let frames = WindowLayout.grid(count: windows.count, in: visible)
        let rotated: [Hit]
        if organizeRotation == 0 {
            rotated = windows
        } else {
            rotated = Array(windows[organizeRotation...] + windows[..<organizeRotation])
        }
        for (index, hit) in rotated.enumerated() where index < frames.count {
            applyFrame(frames[index], to: hit.window)
        }
    }

    private func listedWindows(in visible: CGRect) -> [Hit] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var hits: [Hit] = []
        var seen = Set<CGWindowID>()
        for entry in info {
            let layer = entry[kCGWindowLayer as String] as? Int ?? 0
            guard layer == 0 else { continue }
            let alpha = entry[kCGWindowAlpha as String] as? Double ?? 1
            guard alpha > 0.05 else { continue }
            let owner = entry[kCGWindowOwnerName as String] as? String ?? ""
            if Self.ignoredOwners.contains(owner) { continue }
            let name = entry[kCGWindowName as String] as? String ?? ""
            if name == WindowThrowOverlay.windowTitle { continue }
            guard let pid = entry[kCGWindowOwnerPID as String] as? pid_t, pid > 0 else { continue }
            guard let bounds = cgBounds(entry[kCGWindowBounds as String] as? [String: Any]) else { continue }
            guard bounds.width >= 80, bounds.height >= 40 else { continue }
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            guard visible.insetBy(dx: -2, dy: -2).contains(center) else { continue }
            let windowID = CGWindowID((entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0)
            if windowID != 0, seen.contains(windowID) { continue }
            guard let window = axWindow(pid: pid, bounds: bounds) else { continue }
            if isMinimized(window) || isFullscreen(window) { continue }
            if windowID != 0 { seen.insert(windowID) }
            hits.append(Hit(window: window, windowID: windowID, bounds: bounds))
        }
        return hits
    }

    private func applyFrame(_ frame: CGRect, to window: AXUIElement) {
        var size = frame.size
        var origin = frame.origin
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        NSAnimationContext.current.allowsImplicitAnimation = false
        _ = setSize(window, &size)
        _ = setPoint(window, kAXPositionAttribute as CFString, &origin)
        size = frame.size
        origin = frame.origin
        _ = setSize(window, &size)
        _ = setPoint(window, kAXPositionAttribute as CFString, &origin)
        NSAnimationContext.endGrouping()
    }

    private func retarget(_ current: Session, moving: Bool, point: CGPoint) {
        let frame = visualFrame(for: current.window) ?? axFrame(current.window) ?? current.startFrame
        session = Session(
            window: current.window,
            windowID: current.windowID,
            startFrame: frame,
            startPoint: point,
            moving: moving
        )
        if moving {
            NSCursor.closedHand.set()
        } else {
            NSCursor.crosshair.set()
        }
    }

    private func startTick() {
        if tickTimer != nil { return }
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer.tolerance = 0.002
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func stopTick() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func tick() {
        guard hasPoint, !writing else { return }
        writing = true
        processPointer()
        if let point = pendingPoint, session != nil {
            write(at: point)
        }
        writing = false
    }

    private func processPointer() {
        lock.lock()
        let active = enabled
        let moveOn = moveEnabled
        let resizeOn = resizeEnabled
        let throwOn = throwEnabled
        let move = moveFlags
        let resize = resizeFlags
        let throwNeed = throwFlags
        lock.unlock()
        guard active else { return }
        if ShortcutCapture.isActive {
            endGrabSession()
            endThrow()
            return
        }

        let mode = Self.pointerMode(
            flags: lastFlags,
            moveEnabled: moveOn,
            resizeEnabled: resizeOn,
            throwEnabled: throwOn,
            moveFlags: move,
            resizeFlags: resize,
            throwFlags: throwNeed
        )
        guard let mode else {
            endGrabSession()
            endThrow()
            return
        }

        if lastType == .flagsChanged {
            if let session, session.moving != (mode == .move) {
                endGrabSession()
            }
            if throwSession != nil, mode != .throw {
                endThrow()
            }
            if session != nil, mode == .throw {
                endGrabSession()
            }
            return
        }

        switch mode {
        case .move, .resize:
            endThrow()
            handleGrab(mode: mode, point: lastPoint)
        case .throw:
            endGrabSession()
            handleThrow(at: lastPoint)
        }
    }

    private func write(at point: CGPoint) {
        guard let session else { return }
        let dx = point.x - session.startPoint.x
        let dy = point.y - session.startPoint.y
        if session.moving {
            let origin = CGPoint(
                x: session.startFrame.origin.x + dx,
                y: session.startFrame.origin.y + dy
            )
            var pid: pid_t = 0
            AXUIElementGetPid(session.window, &pid)
            // SLSMoveWindow uses this process's window-server connection, so it
            // only actually moves Control Box. A 0 return on another app's
            // window is a no-op and used to skip the Accessibility fallback.
            if pid == getpid(), WindowServer.move(session.windowID, to: origin) {
                return
            }
            var axOrigin = origin
            _ = setPoint(session.window, kAXPositionAttribute as CFString, &axOrigin)
            return
        }
        var size = CGSize(
            width: max(160, session.startFrame.width + dx),
            height: max(80, session.startFrame.height + dy)
        )
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        NSAnimationContext.current.allowsImplicitAnimation = false
        _ = setSize(session.window, &size)
        NSAnimationContext.endGrouping()
    }

    private func endGrabSession() {
        if session != nil {
            NSCursor.arrow.set()
            WindowShake.endGrab()
        }
        session = nil
        pendingPoint = nil
    }

    private func endThrow() {
        if throwSession != nil {
            WindowThrowOverlay.hide()
        }
        throwSession = nil
    }

    private enum PointerMode { case move, resize, `throw` }

    private static func pointerMode(
        flags: CGEventFlags,
        moveEnabled: Bool,
        resizeEnabled: Bool,
        throwEnabled: Bool,
        moveFlags: CGEventFlags,
        resizeFlags: CGEventFlags,
        throwFlags: CGEventFlags
    ) -> PointerMode? {
        let bits = ModifierChords.live(flags)
        let throwNeed = ModifierChords.normalized(throwFlags)
        let resizeNeed = ModifierChords.normalized(resizeFlags)
        let moveNeed = ModifierChords.normalized(moveFlags)
        if throwEnabled, !throwNeed.isEmpty, bits == throwNeed {
            return .throw
        }
        if resizeEnabled, !resizeNeed.isEmpty, bits == resizeNeed {
            return .resize
        }
        if moveEnabled, !moveNeed.isEmpty, bits == moveNeed {
            return .move
        }
        return nil
    }

    private func visualFrame(for window: AXUIElement) -> CGRect? {
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        let ax = axFrame(window)
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard pid > 0,
              let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return ax
        }
        var best: CGRect?
        var bestArea: CGFloat = 0
        for entry in info {
            guard (entry[kCGWindowOwnerPID as String] as? pid_t) == pid else { continue }
            guard (entry[kCGWindowLayer as String] as? Int) ?? 0 == 0 else { continue }
            guard let bounds = cgBounds(entry[kCGWindowBounds as String] as? [String: Any]) else { continue }
            let area: CGFloat
            if let ax {
                area = bounds.intersection(ax).width * bounds.intersection(ax).height
            } else {
                area = bounds.width * bounds.height
            }
            if area > bestArea {
                bestArea = area
                best = bounds
            }
        }
        return best ?? ax
    }

    private struct Hit {
        var window: AXUIElement
        var windowID: CGWindowID
        var bounds: CGRect
    }

    private func hit(at point: CGPoint) -> Hit? {
        if let listed = frontWindow(at: point), let matched = axWindow(pid: listed.pid, bounds: listed.bounds) {
            return Hit(window: matched, windowID: listed.windowID, bounds: listed.bounds)
        }
        if let window = windowFromHitTest(point), let frame = axFrame(window) ?? visualFrame(for: window) {
            return Hit(window: window, windowID: 0, bounds: frame)
        }
        return nil
    }

    private struct ListedWindow {
        var pid: pid_t
        var windowID: CGWindowID
        var bounds: CGRect
    }

    private func frontWindow(at point: CGPoint) -> ListedWindow? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for entry in info {
            let layer = entry[kCGWindowLayer as String] as? Int ?? 0
            guard layer == 0 else { continue }
            let alpha = entry[kCGWindowAlpha as String] as? Double ?? 1
            guard alpha > 0.05 else { continue }
            let owner = entry[kCGWindowOwnerName as String] as? String ?? ""
            if Self.ignoredOwners.contains(owner) { continue }
            let name = entry[kCGWindowName as String] as? String ?? ""
            if name == WindowThrowOverlay.windowTitle { continue }
            guard let pid = entry[kCGWindowOwnerPID as String] as? pid_t, pid > 0 else { continue }
            guard let bounds = cgBounds(entry[kCGWindowBounds as String] as? [String: Any]) else { continue }
            guard bounds.width >= 80, bounds.height >= 40 else { continue }
            if bounds.insetBy(dx: -2, dy: -2).contains(point) {
                let windowID = CGWindowID((entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0)
                return ListedWindow(pid: pid, windowID: windowID, bounds: bounds)
            }
        }
        return nil
    }

    private func cgBounds(_ dict: [String: Any]?) -> CGRect? {
        guard let dict else { return nil }
        func number(_ key: String) -> CGFloat? {
            if let value = dict[key] as? NSNumber { return CGFloat(truncating: value) }
            return nil
        }
        guard let x = number("X"), let y = number("Y"),
              let w = number("Width"), let h = number("Height") else {
            return nil
        }
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private func axWindow(pid: pid_t, bounds: CGRect) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        var windows = copyArray(app, kAXWindowsAttribute as CFString) ?? []
        if let focused = copyElement(app, kAXFocusedWindowAttribute as CFString) {
            if !windows.contains(where: { CFEqual($0, focused) }) {
                windows.insert(focused, at: 0)
            }
        }
        if let main = copyElement(app, kAXMainWindowAttribute as CFString) {
            if !windows.contains(where: { CFEqual($0, main) }) {
                windows.append(main)
            }
        }
        var best: AXUIElement?
        var bestArea: CGFloat = 0
        for window in windows {
            guard let frame = axFrame(window) else { continue }
            let area = frame.intersection(bounds).width * frame.intersection(bounds).height
            if area > bestArea {
                bestArea = area
                best = window
            }
        }
        if bestArea > 40 { return best }
        return windows.first
    }

    private func windowFromHitTest(_ point: CGPoint) -> AXUIElement? {
        var found: AXUIElement?
        let status = AXUIElementCopyElementAtPosition(
            systemWide,
            Float(point.x),
            Float(point.y),
            &found
        )
        guard status == .success, let found else { return nil }
        return windowAncestor(found)
    }

    private func windowAncestor(_ element: AXUIElement) -> AXUIElement? {
        var current: AXUIElement? = element
        var depth = 0
        while let node = current, depth < 16 {
            if role(of: node) == kAXWindowRole as String {
                return node
            }
            if role(of: node) == kAXApplicationRole as String {
                return nil
            }
            current = parent(of: node)
            depth += 1
        }
        return nil
    }

    private func setPoint(_ element: AXUIElement, _ attribute: CFString, _ point: inout CGPoint) -> Bool {
        guard let value = AXValueCreate(.cgPoint, &point) else { return false }
        return AXUIElementSetAttributeValue(element, attribute, value) == .success
    }

    private func setSize(_ element: AXUIElement, _ size: inout CGSize) -> Bool {
        guard let value = AXValueCreate(.cgSize, &size) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value) == .success
    }

    private func axFrame(_ element: AXUIElement) -> CGRect? {
        guard let position = copyAXValue(element, kAXPositionAttribute as CFString, .cgPoint, CGPoint.zero),
              let size = copyAXValue(element, kAXSizeAttribute as CFString, .cgSize, CGSize.zero) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func isFullscreen(_ element: AXUIElement) -> Bool {
        boolAttribute(element, "AXFullScreen" as CFString)
    }

    private func isMinimized(_ element: AXUIElement) -> Bool {
        boolAttribute(element, kAXMinimizedAttribute as CFString)
    }

    private func boolAttribute(_ element: AXUIElement, _ attribute: CFString) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let number = value as? NSNumber else {
            return false
        }
        return number.boolValue
    }

    private func copyElement(_ element: AXUIElement, _ attribute: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private func copyArray(_ element: AXUIElement, _ attribute: CFString) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let array = value as? [AXUIElement] else {
            return nil
        }
        return array
    }

    private func copyAXValue<T>(
        _ element: AXUIElement,
        _ attribute: CFString,
        _ type: AXValueType,
        _ placeholder: T
    ) -> T? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXValueGetTypeID() else {
            return nil
        }
        var value = placeholder
        guard AXValueGetValue(ref as! AXValue, type, &value) else { return nil }
        return value
    }

    private func parent(of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private func role(of element: AXUIElement) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success else {
            return ""
        }
        return value as? String ?? ""
    }

    private static let ignoredOwners: Set<String> = [
        "Window Server",
        "Dock",
        "Control Center",
        "Notification Centre",
        "Notification Center",
        "SystemUIServer",
        "Spotlight",
        "loginwindow",
        "Screenshot"
    ]
}

private enum WindowServer {
    static func move(_ windowID: CGWindowID, to origin: CGPoint) -> Bool {
        guard windowID != 0, let connection = connectionID(), let symbol = symbol("SLSMoveWindow")
                ?? symbol("CGSMoveWindow") else {
            return false
        }
        typealias Move = @convention(c) (Int32, UInt32, UnsafePointer<CGPoint>) -> Int32
        var point = origin
        return unsafeBitCast(symbol, to: Move.self)(connection, windowID, &point) == 0
    }

    private static func connectionID() -> Int32? {
        guard let symbol = symbol("SLSMainConnectionID") ?? symbol("CGSMainConnectionID") else {
            return nil
        }
        typealias Connect = @convention(c) () -> Int32
        return unsafeBitCast(symbol, to: Connect.self)()
    }

    private static func symbol(_ name: String) -> UnsafeMutableRawPointer? {
        if let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) {
            return symbol
        }
        let path = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
        let handle = dlopen(path, RTLD_NOLOAD | RTLD_NOW) ?? dlopen(path, RTLD_NOW)
        return handle.flatMap { dlsym($0, name) }
    }
}
