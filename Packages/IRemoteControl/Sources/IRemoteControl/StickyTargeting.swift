import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Highlights the Accessibility control under the pointer and activates that
/// control on click, so small targets behave more like Apple TV focus.
public enum StickyTargeting {
    public static func sync(active: Bool) {
        if Thread.isMainThread {
            Controller.shared.sync(active: active)
        } else {
            DispatchQueue.main.async {
                Controller.shared.sync(active: active)
            }
        }
    }

    public static func hide() {
        sync(active: false)
    }

    /// Returns true when the click was delivered to the highlighted control.
    public static func handleMouse(right: Bool, down: Bool) -> Bool {
        if Thread.isMainThread {
            return Controller.shared.handleMouse(right: right, down: down)
        }
        var handled = false
        DispatchQueue.main.sync {
            handled = Controller.shared.handleMouse(right: right, down: down)
        }
        return handled
    }
}

private final class Controller {
    static let shared = Controller()

    private let systemWide = AXUIElementCreateSystemWide()
    private var overlay: OverlayWindow?
    private var target: AXUIElement?
    private var lastFrame = CGRect.null
    private var lastRefresh = Date.distantPast
    private var consumedPress = false

    init() {
        AXUIElementSetMessagingTimeout(systemWide, 0.08)
    }

    func sync(active: Bool) {
        guard active else {
            hideOverlay()
            return
        }
        refresh(force: false)
    }

    func handleMouse(right: Bool, down: Bool) -> Bool {
        refresh(force: true)
        if down {
            consumedPress = false
            guard let target, let frame = axFrame(target) else { return false }
            guard frame.insetBy(dx: -6, dy: -6).contains(pointerLocation()) else { return false }
            if activate(target, right: right) {
                consumedPress = true
                return true
            }
            return false
        }
        if consumedPress {
            consumedPress = false
            return true
        }
        return false
    }

    private func refresh(force: Bool) {
        let now = Date()
        if !force, now.timeIntervalSince(lastRefresh) < 0.05 {
            return
        }
        lastRefresh = now

        let location = pointerLocation()
        guard let leaf = element(at: location), let resolved = resolveTarget(from: leaf) else {
            hideOverlay()
            return
        }
        guard let frame = axFrame(resolved), frame.insetBy(dx: -6, dy: -6).contains(location) else {
            hideOverlay()
            return
        }

        target = resolved
        showOverlay(axFrame: frame)
    }

    private func pointerLocation() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    private func element(at point: CGPoint) -> AXUIElement? {
        var found: AXUIElement?
        let status = AXUIElementCopyElementAtPosition(
            systemWide,
            Float(point.x),
            Float(point.y),
            &found
        )
        guard status == .success else { return nil }
        return found
    }

    private func resolveTarget(from leaf: AXUIElement) -> AXUIElement? {
        var current: AXUIElement? = leaf
        var depth = 0
        while let element = current, depth < 14 {
            let role = role(of: element)
            if role == kAXApplicationRole as String || role == kAXWindowRole as String {
                return nil
            }
            if isInteractive(element, role: role), let frame = axFrame(element), isReasonable(frame) {
                return element
            }
            current = parent(of: element)
            depth += 1
        }
        return nil
    }

    private func isInteractive(_ element: AXUIElement, role: String) -> Bool {
        if actions(of: element).contains(where: {
            $0 == kAXPressAction as String || $0 == kAXShowMenuAction as String
        }) {
            return true
        }
        return Self.interactiveRoles.contains(role)
    }

    private func isReasonable(_ frame: CGRect) -> Bool {
        guard frame.width >= 8, frame.height >= 8 else { return false }
        let screen = NSScreen.screens.map(\.frame).reduce(CGRect.null, { $0.union($1) })
        guard !screen.isNull else { return true }
        return frame.width < screen.width * 0.55 && frame.height < screen.height * 0.55
    }

    private func activate(_ element: AXUIElement, right: Bool) -> Bool {
        let names = actions(of: element)
        if right {
            guard names.contains(kAXShowMenuAction as String) else { return false }
            return AXUIElementPerformAction(element, kAXShowMenuAction as CFString) == .success
        }
        if names.contains(kAXPressAction as String)
            || Self.interactiveRoles.contains(role(of: element)) {
            return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
        }
        return false
    }

    private func parent(of element: AXUIElement) -> AXUIElement? {
        guard let value = copyAttribute(element, kAXParentAttribute as CFString),
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private func role(of element: AXUIElement) -> String {
        copyAttribute(element, kAXRoleAttribute as CFString) as? String ?? ""
    }

    private func actions(of element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success, let names else { return [] }
        return (names as NSArray).compactMap { $0 as? String }
    }

    private func axFrame(_ element: AXUIElement) -> CGRect? {
        guard let position = copyAXValue(element, kAXPositionAttribute as CFString, .cgPoint, CGPoint.zero),
              let size = copyAXValue(element, kAXSizeAttribute as CFString, .cgSize, CGSize.zero) else {
            return nil
        }
        return CGRect(origin: position, size: size)
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

    private func copyAttribute(_ element: AXUIElement, _ attribute: CFString) -> AnyObject? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value
    }

    private func showOverlay(axFrame: CGRect) {
        if lastFrame.equalTo(axFrame), overlay?.isVisible == true { return }
        lastFrame = axFrame
        let cocoa = cocoaRect(fromAX: axFrame).insetBy(dx: -5, dy: -5)
        if overlay == nil {
            overlay = OverlayWindow()
        }
        overlay?.show(cocoa)
    }

    private func hideOverlay() {
        target = nil
        lastFrame = .null
        overlay?.hide()
    }

    private func cocoaRect(fromAX ax: CGRect) -> CGRect {
        let height = NSScreen.screens.first { $0.frame.origin == .zero }?.frame.height
            ?? NSScreen.main?.frame.height
            ?? 0
        return CGRect(x: ax.minX, y: height - ax.maxY, width: ax.width, height: ax.height)
    }

    private static let interactiveRoles: Set<String> = [
        kAXButtonRole as String,
        kAXCheckBoxRole as String,
        kAXRadioButtonRole as String,
        kAXPopUpButtonRole as String,
        kAXMenuButtonRole as String,
        kAXMenuItemRole as String,
        "AXLink",
        kAXComboBoxRole as String,
        kAXSliderRole as String,
        kAXIncrementorRole as String,
        "AXDecrementor",
        kAXTabGroupRole as String,
        kAXCellRole as String,
        kAXRowRole as String,
        kAXColorWellRole as String,
        kAXDisclosureTriangleRole as String,
        "AXToolbarButton",
        "AXSortButton",
        "AXSwitch",
        "AXDockItem",
        "AXApplicationDockItem",
        "AXCloseButton",
        "AXMinimizeButton",
        "AXZoomButton",
        "AXFullScreenButton",
        kAXMenuBarItemRole as String
    ]
}

private final class OverlayWindow {
    private let panel: NSPanel
    private let ring: OverlayView

    var isVisible: Bool { panel.isVisible }

    init() {
        ring = OverlayView(frame: .zero)
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = ring
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .transient,
            .stationary
        ]
        panel.isExcludedFromWindowsMenu = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.setAccessibilityElement(false)
        ring.setAccessibilityElement(false)
    }

    func show(_ cocoaRect: CGRect) {
        panel.setFrame(cocoaRect, display: true)
        ring.needsDisplay = true
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

private final class OverlayView: NSView {
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let inset = bounds.insetBy(dx: 3, dy: 3)
        let path = NSBezierPath(roundedRect: inset, xRadius: 8, yRadius: 8)
        NSColor.keyboardFocusIndicatorColor.withAlphaComponent(0.14).setFill()
        path.fill()
        path.lineWidth = 3
        NSColor.keyboardFocusIndicatorColor.setStroke()
        path.stroke()
    }
}
