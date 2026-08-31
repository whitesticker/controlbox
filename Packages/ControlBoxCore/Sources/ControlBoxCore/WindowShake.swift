import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Shake a window left and right to hide every other visible window
/// (Windows Aero Shake). A second shake restores them.
///
/// Native title-bar drags and Window Grab move both count. The event tap
/// only stashes pointer state; Accessibility runs on the main queue.
public enum WindowShakeScope: String, Codable, Equatable, Sendable, CaseIterable {
    case thisDisplay
    case allDisplays
}

public enum WindowShake {
    public static func configure(enabled: Bool, scope: WindowShakeScope) {
        Controller.shared.configure(enabled: enabled, scope: scope)
    }

    public static func stop() {
        configure(enabled: false, scope: .thisDisplay)
    }

    /// Window Grab move is already a window drag — feed those points here.
    public static func noteGrab(
        window: AXUIElement,
        windowID: CGWindowID,
        bounds: CGRect,
        point: CGPoint
    ) {
        Controller.shared.noteGrab(
            window: window,
            windowID: windowID,
            bounds: bounds,
            point: point
        )
    }

    public static func endGrab() {
        Controller.shared.endGrab()
    }

    /// True while a title-bar or grab drag is being watched for a shake.
    public static var isBusy: Bool {
        Controller.shared.isBusy
    }
}

private final class Controller: @unchecked Sendable {
    static let shared = Controller()

    private let systemWide = AXUIElementCreateSystemWide()
    private let lock = NSLock()
    private var enabled = false
    private var scope: WindowShakeScope = .thisDisplay
    private var port: CFMachPort?
    private var source: CFRunLoopSource?

    private var pendingDown: CGPoint?
    private var pendingMove: CGPoint?
    private var pendingUp = false
    private var scheduled = false

    private var grabActive = false
    private var drag: Drag?
    private var firedThisDrag = false
    private var hidden: [Hidden] = []

    private struct Drag {
        var window: AXUIElement
        var windowID: CGWindowID
        var startBounds: CGRect
        var startPoint: CGPoint
        var windowMoving: Bool
        var lastX: CGFloat
        var direction: Int
        var reversals: Int
        var reversalX: CGFloat
        var firstReversalAt: CFTimeInterval
    }

    private struct Hidden {
        var window: AXUIElement
        var windowID: CGWindowID
    }

    private struct Listed {
        var window: AXUIElement
        var windowID: CGWindowID
        var bounds: CGRect
        var pid: pid_t
    }

    init() {
        AXUIElementSetMessagingTimeout(systemWide, 0.2)
    }

    var isBusy: Bool {
        lock.lock()
        defer { lock.unlock() }
        return drag != nil
    }

    func configure(enabled: Bool, scope: WindowShakeScope) {
        lock.lock()
        self.enabled = enabled
        self.scope = scope
        let shouldRun = enabled
        lock.unlock()
        if shouldRun {
            start()
        } else {
            restoreHidden()
            stop()
        }
    }

    func noteGrab(window: AXUIElement, windowID: CGWindowID, bounds: CGRect, point: CGPoint) {
        lock.lock()
        let on = enabled
        lock.unlock()
        guard on else { return }
        grabActive = true
        let frame = bounds != .zero ? bounds : (self.bounds(of: windowID) ?? .zero)
        if drag == nil {
            beginDrag(window: window, windowID: windowID, bounds: frame, moving: true, at: point)
        }
        advanceShake(at: point)
    }

    func endGrab() {
        guard grabActive else { return }
        grabActive = false
        endDrag()
    }

    private func start() {
        if port != nil { return }
        let mask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseDragged.rawValue)
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
        endDrag()
        grabActive = false
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        port = nil
        source = nil
        pendingDown = nil
        pendingMove = nil
        pendingUp = false
        scheduled = false
    }

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput, let port {
            CGEvent.tapEnable(tap: port, enable: true)
            return
        }
        let point = event.location
        switch type {
        case .leftMouseDown:
            pendingDown = point
            pendingUp = false
        case .leftMouseDragged:
            pendingMove = point
        case .leftMouseUp:
            pendingMove = point
            pendingUp = true
        default:
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
        let on = enabled
        lock.unlock()
        let down = pendingDown
        let move = pendingMove
        let up = pendingUp
        pendingDown = nil
        pendingMove = nil
        pendingUp = false
        guard on else { return }
        if grabActive { return }

        if let down {
            firedThisDrag = false
            if let hit = hit(at: down) {
                beginDrag(
                    window: hit.window,
                    windowID: hit.windowID,
                    bounds: hit.bounds,
                    moving: false,
                    at: down
                )
            } else {
                endDrag()
            }
        }
        if let move, var current = drag {
            if !current.windowMoving, hasMoved(current, pointer: move) {
                current.windowMoving = true
                drag = current
            }
            if current.windowMoving {
                advanceShake(at: move)
            }
        }
        if up {
            endDrag()
        }
    }

    private func beginDrag(
        window: AXUIElement,
        windowID: CGWindowID,
        bounds: CGRect,
        moving: Bool,
        at point: CGPoint
    ) {
        AXUIElementSetMessagingTimeout(window, 0.2)
        drag = Drag(
            window: window,
            windowID: windowID,
            startBounds: bounds,
            startPoint: point,
            windowMoving: moving,
            lastX: point.x,
            direction: 0,
            reversals: 0,
            reversalX: point.x,
            firstReversalAt: 0
        )
        firedThisDrag = false
    }

    private func endDrag() {
        drag = nil
        firedThisDrag = false
    }

    private func advanceShake(at point: CGPoint) {
        guard var current = drag, !firedThisDrag else { return }
        let dx = point.x - current.lastX
        if abs(dx) < 6 {
            return
        }
        let next = dx > 0 ? 1 : -1
        if current.direction != 0, next != current.direction {
            let travel = abs(point.x - current.reversalX)
            if travel >= 48 {
                let now = ProcessInfo.processInfo.systemUptime
                if current.reversals == 0 {
                    current.firstReversalAt = now
                } else if now - current.firstReversalAt > 1.5 {
                    current.reversals = 0
                    current.firstReversalAt = now
                }
                current.reversals += 1
                current.reversalX = point.x
                if current.reversals >= 3 {
                    drag = current
                    firedThisDrag = true
                    fire(from: current)
                    return
                }
            }
        }
        current.direction = next
        current.lastX = point.x
        drag = current
    }

    private func fire(from drag: Drag) {
        if !hidden.isEmpty {
            restoreHidden()
            return
        }
        hideOthers(of: drag)
    }

    private func hideOthers(of drag: Drag) {
        lock.lock()
        let scope = self.scope
        lock.unlock()
        let shakenCenter = CGPoint(x: drag.startBounds.midX, y: drag.startBounds.midY)
        let display = WindowLayout.visibleFrame(containingQuartz: shakenCenter)
        var next: [Hidden] = []
        for listed in onScreenWindows() {
            if listed.windowID != 0, listed.windowID == drag.windowID { continue }
            if CFEqual(listed.window, drag.window) { continue }
            if isMinimized(listed.window) || isFullscreen(listed.window) { continue }
            if scope == .thisDisplay {
                let center = CGPoint(x: listed.bounds.midX, y: listed.bounds.midY)
                guard display.insetBy(dx: -2, dy: -2).contains(center) else { continue }
            }
            AXUIElementSetMessagingTimeout(listed.window, 0.2)
            AXUIElementSetAttributeValue(
                listed.window,
                kAXMinimizedAttribute as CFString,
                kCFBooleanTrue
            )
            next.append(Hidden(window: listed.window, windowID: listed.windowID))
        }
        hidden = next
    }

    private func restoreHidden() {
        let items = hidden
        hidden = []
        for item in items {
            if item.windowID != 0, let live = axWindow(id: item.windowID) {
                AXUIElementSetMessagingTimeout(live, 0.2)
                if isMinimized(live) {
                    AXUIElementSetAttributeValue(
                        live,
                        kAXMinimizedAttribute as CFString,
                        kCFBooleanFalse
                    )
                }
                continue
            }
            AXUIElementSetMessagingTimeout(item.window, 0.2)
            if isMinimized(item.window) {
                AXUIElementSetAttributeValue(
                    item.window,
                    kAXMinimizedAttribute as CFString,
                    kCFBooleanFalse
                )
            }
        }
    }

    private func hasMoved(_ drag: Drag, pointer: CGPoint) -> Bool {
        let pointerTravel = hypot(pointer.x - drag.startPoint.x, pointer.y - drag.startPoint.y)
        if pointerTravel >= 16 { return true }
        guard let now = bounds(of: drag.windowID) else { return false }
        let dx = now.origin.x - drag.startBounds.origin.x
        let dy = now.origin.y - drag.startBounds.origin.y
        return hypot(dx, dy) >= 8
    }

    private func bounds(of windowID: CGWindowID) -> CGRect? {
        guard windowID != 0 else { return nil }
        let options: CGWindowListOption = [.optionIncludingWindow, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, windowID) as? [[String: Any]],
              let entry = info.first(where: {
                  CGWindowID(($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0) == windowID
              })
        else { return nil }
        return cgBounds(entry[kCGWindowBounds as String] as? [String: Any])
    }

    private func axWindow(id windowID: CGWindowID) -> AXUIElement? {
        guard windowID != 0,
              let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
              let entry = info.first,
              let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
              let bounds = cgBounds(entry[kCGWindowBounds as String] as? [String: Any])
        else { return nil }
        return axWindow(pid: pid, bounds: bounds)
    }

    private func onScreenWindows() -> [Listed] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var hits: [Listed] = []
        var seen = Set<CGWindowID>()
        for entry in info {
            guard (entry[kCGWindowLayer as String] as? Int) ?? 0 == 0 else { continue }
            let alpha = entry[kCGWindowAlpha as String] as? Double ?? 1
            guard alpha > 0.05 else { continue }
            let owner = entry[kCGWindowOwnerName as String] as? String ?? ""
            if Self.ignoredOwners.contains(owner) { continue }
            let name = entry[kCGWindowName as String] as? String ?? ""
            if Self.ignoredTitles.contains(name) { continue }
            guard let pid = entry[kCGWindowOwnerPID as String] as? pid_t, pid > 0 else { continue }
            guard let bounds = cgBounds(entry[kCGWindowBounds as String] as? [String: Any]) else { continue }
            guard bounds.width >= 80, bounds.height >= 40 else { continue }
            let windowID = CGWindowID((entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0)
            if windowID != 0, seen.contains(windowID) { continue }
            guard let window = axWindow(pid: pid, bounds: bounds) else { continue }
            if windowID != 0 { seen.insert(windowID) }
            hits.append(Listed(window: window, windowID: windowID, bounds: bounds, pid: pid))
        }
        return hits
    }

    private func hit(at point: CGPoint) -> Listed? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for entry in info {
            guard (entry[kCGWindowLayer as String] as? Int) ?? 0 == 0 else { continue }
            let alpha = entry[kCGWindowAlpha as String] as? Double ?? 1
            guard alpha > 0.05 else { continue }
            let owner = entry[kCGWindowOwnerName as String] as? String ?? ""
            if Self.ignoredOwners.contains(owner) { continue }
            let name = entry[kCGWindowName as String] as? String ?? ""
            if Self.ignoredTitles.contains(name) { continue }
            guard let pid = entry[kCGWindowOwnerPID as String] as? pid_t, pid > 0 else { continue }
            guard let bounds = cgBounds(entry[kCGWindowBounds as String] as? [String: Any]) else { continue }
            guard bounds.width >= 80, bounds.height >= 40 else { continue }
            guard bounds.insetBy(dx: -2, dy: -2).contains(point) else { continue }
            let windowID = CGWindowID((entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0)
            guard let window = axWindow(pid: pid, bounds: bounds) else { continue }
            if isMinimized(window) || isFullscreen(window) { return nil }
            return Listed(window: window, windowID: windowID, bounds: bounds, pid: pid)
        }
        return nil
    }

    private func axWindow(pid: pid_t, bounds: CGRect) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        var windows = copyArray(app, kAXWindowsAttribute as CFString) ?? []
        if let focused = copyElement(app, kAXFocusedWindowAttribute as CFString),
           !windows.contains(where: { CFEqual($0, focused) }) {
            windows.insert(focused, at: 0)
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

    private static let ignoredTitles: Set<String> = [
        WindowThrowOverlay.windowTitle,
        DockPreview.overlayTitle
    ]
}
