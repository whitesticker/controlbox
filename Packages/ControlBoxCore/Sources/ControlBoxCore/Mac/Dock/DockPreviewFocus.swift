import AppKit
import ApplicationServices
import Foundation

enum DockPreviewFocus {
    static func close(_ window: DockPreviewWindow) {
        press(window, kAXCloseButtonAttribute as CFString)
    }

    private static func press(_ window: DockPreviewWindow, _ attribute: CFString) {
        let work = {
            guard let element = DockPreviewWindows.axWindow(for: window) else { return }
            var button: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute, &button) == .success,
                  let button,
                  CFGetTypeID(button) == AXUIElementGetTypeID()
            else { return }
            AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    static func minimize(_ window: DockPreviewWindow) {
        let work = {
            guard let element = DockPreviewWindows.axWindow(for: window) else { return }
            AXUIElementSetAttributeValue(
                element,
                kAXMinimizedAttribute as CFString,
                kCFBooleanTrue
            )
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    static func restore(_ window: DockPreviewWindow) {
        let work = {
            if let element = DockPreviewWindows.axWindow(for: window) {
                AXUIElementSetAttributeValue(
                    element,
                    kAXMinimizedAttribute as CFString,
                    kCFBooleanFalse
                )
                AXUIElementPerformAction(element, kAXRaiseAction as CFString)
            }
            if let app = NSRunningApplication(processIdentifier: window.pid) {
                app.activate(options: [.activateIgnoringOtherApps])
            }
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    static func quit(_ window: DockPreviewWindow) {
        let work = {
            _ = NSRunningApplication(processIdentifier: window.pid)?.terminate()
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    static func raise(_ window: DockPreviewWindow) {
        let work = {
            if let element = DockPreviewWindows.axWindow(for: window) {
                if DockAX.bool(element, kAXMinimizedAttribute as CFString) {
                    AXUIElementSetAttributeValue(
                        element,
                        kAXMinimizedAttribute as CFString,
                        kCFBooleanFalse
                    )
                }
                AXUIElementPerformAction(element, kAXRaiseAction as CFString)
            }
            if let app = NSRunningApplication(processIdentifier: window.pid) {
                app.activate(options: [.activateIgnoringOtherApps])
            }
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    static func isFullscreen(_ window: DockPreviewWindow) -> Bool {
        guard let element = DockPreviewWindows.axWindow(for: window) else { return false }
        return DockAX.bool(element, "AXFullScreen" as CFString)
    }

    static func exitFullscreen(_ window: DockPreviewWindow) {
        let work = {
            guard let element = DockPreviewWindows.axWindow(for: window) else { return }
            AXUIElementSetAttributeValue(
                element,
                "AXFullScreen" as CFString,
                kCFBooleanFalse
            )
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    static func setFrame(_ window: DockPreviewWindow, _ frame: CGRect) {
        let work = {
            guard let element = DockPreviewWindows.axWindow(for: window) else { return }
            if DockAX.bool(element, "AXFullScreen" as CFString) { return }
            DockAX.setFrame(element, frame)
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    /// Quartz visible frame of the destination display. Keeps size, then clamps.
    static func place(_ window: DockPreviewWindow, on visible: CGRect) {
        let work = {
            guard let element = DockPreviewWindows.axWindow(for: window) else { return }
            if DockAX.bool(element, "AXFullScreen" as CFString) { return }
            var size = window.bounds.size
            if size.width > visible.width { size.width = visible.width }
            if size.height > visible.height { size.height = visible.height }
            var origin = window.bounds.origin
            let maxX = visible.maxX - size.width
            let maxY = visible.maxY - size.height
            origin.x = size.width >= visible.width ? visible.minX : min(max(origin.x, visible.minX), maxX)
            origin.y = size.height >= visible.height ? visible.minY : min(max(origin.y, visible.minY), maxY)
            DockAX.setFrame(element, CGRect(origin: origin, size: size))
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
}
