import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Click a Dock icon while that app already has a visible window to
/// minimize that window. Listen-only — native Dock clicks still fire.
public enum DockClickMinimize {
    public static func configure(enabled: Bool) {
        Controller.shared.configure(enabled: enabled)
    }

    public static func stop() {
        configure(enabled: false)
    }
}

private final class Controller: @unchecked Sendable {
    static let shared = Controller()

    private let lock = NSLock()
    private var enabled = false
    private var port: CFMachPort?
    private var source: CFRunLoopSource?

    private var downPoint: CGPoint?
    private var downFlags: CGEventFlags = []
    private var downFrontPID: pid_t = 0
    private var upPoint: CGPoint?
    private var scheduled = false

    func configure(enabled: Bool) {
        lock.lock()
        self.enabled = enabled
        let shouldRun = enabled
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
        scheduled = false
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
        let on = enabled
        lock.unlock()
        guard on, let down = downPoint, let up = upPoint else { return }
        downPoint = nil
        upPoint = nil
        guard ModifierChords.normalized(downFlags).isEmpty else { return }
        guard hypot(up.x - down.x, up.y - down.y) < 10 else { return }
        if DockMenu.isVisible() { return }
        let cocoa = WindowLayout.cocoaFrame(
            from: CGRect(origin: down, size: CGSize(width: 1, height: 1))
        ).origin
        guard DockGeometry.isNearDock(cocoa) else { return }
        let frontPID = downFrontPID
        Task { @MainActor in
            guard let app = DockPreview.runningApp(atQuartz: down) else { return }
            if app.bundleIdentifier == "com.apple.dock" { return }
            let pids = self.relatedPIDs(for: app)
            guard pids.contains(frontPID) else { return }
            let windows = self.visibleWindows(of: app)
            guard let window = windows.first else { return }
            DockPreview.minimize(window)
            DockPreview.dismiss()
        }
    }

    private func relatedPIDs(for app: NSRunningApplication) -> Set<pid_t> {
        var pids: Set<pid_t> = [app.processIdentifier]
        let bid = app.bundleIdentifier ?? ""
        for running in NSWorkspace.shared.runningApplications {
            if running.processIdentifier == app.processIdentifier { continue }
            guard let other = running.bundleIdentifier, !bid.isEmpty else { continue }
            if other == bid { pids.insert(running.processIdentifier) }
        }
        return pids
    }

    private func visibleWindows(of app: NSRunningApplication) -> [DockPreviewWindow] {
        DockPreviewWindows.list(app: app).filter { $0.isOnScreen && !$0.isMinimized }
    }
}
