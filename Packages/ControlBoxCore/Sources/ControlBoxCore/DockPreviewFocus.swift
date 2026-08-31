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
}
