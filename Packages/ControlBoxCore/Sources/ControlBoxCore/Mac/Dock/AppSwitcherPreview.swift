import AppKit
import CoreGraphics
import Foundation

/// Window cards for the highlighted app while Command-Tab is up.
/// Tracks Tab from a listen-only tap (keyboard or DualSense). No idle poll.
public enum AppSwitcherPreview {
    public static let overlayTitle = "Control Box App Switcher Preview"

    public static func configure(
        enabled: Bool,
        onChange: @escaping (AppSwitcherPreviewHover?) -> Void
    ) {
        Controller.shared.configure(enabled: enabled, onChange: onChange)
    }

    public static func stop() {
        configure(enabled: false, onChange: { _ in })
    }

    public static func dismissSwitcher() {
        AppSwitcher.cancel()
    }

    public static var isBusy: Bool {
        Controller.shared.isBusy
    }
}

public struct AppSwitcherPreviewHover {
    public var bundleID: String
    public var appName: String
    public var appIcon: NSImage
    public var windows: [DockPreviewWindow]
    public var switcherFrame: CGRect
}

private final class Controller: @unchecked Sendable {
    static let shared = Controller()

    private let lock = NSLock()
    private var enabled = false
    private var onChange: (AppSwitcherPreviewHover?) -> Void = { _ in }
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var workspaceObserver: NSObjectProtocol?

    private var commandDown = false
    private var shiftDown = false
    private var session = false
    private var index = 0
    private var mru: [pid_t] = []
    private var scheduled = false
    private var pendingTab: Bool?
    private var pendingCommand: Bool?
    private var pendingEscape = false

    var isBusy: Bool {
        lock.lock()
        defer { lock.unlock() }
        return session
    }

    func configure(enabled: Bool, onChange: @escaping (AppSwitcherPreviewHover?) -> Void) {
        lock.lock()
        self.enabled = enabled
        self.onChange = onChange
        let shouldRun = enabled
        lock.unlock()
        if shouldRun {
            start()
        } else {
            endSession()
            stop()
        }
    }

    private func start() {
        seedMRU()
        startWorkspace()
        startTap()
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
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
        workspaceObserver = nil
        scheduled = false
        pendingTab = nil
        pendingCommand = nil
        pendingEscape = false
    }

    private func startWorkspace() {
        if workspaceObserver != nil { return }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            self?.noteActivate(app)
        }
    }

    private func startTap() {
        if port != nil { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
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
    }

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput, let port {
            CGEvent.tapEnable(tap: port, enable: true)
            return
        }
        let flags = event.flags
        if type == .flagsChanged {
            pendingCommand = flags.contains(.maskCommand)
            shiftDown = flags.contains(.maskShift)
        } else if type == .keyDown {
            let key = event.getIntegerValueField(.keyboardEventKeycode)
            if key == 48, flags.contains(.maskCommand) {
                pendingTab = flags.contains(.maskShift)
                shiftDown = flags.contains(.maskShift)
            } else if key == 53 {
                pendingEscape = true
            }
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
        guard on else { return }

        if let command = pendingCommand {
            pendingCommand = nil
            commandDown = command
            if !command {
                endSession()
                return
            }
        }
        if pendingEscape {
            pendingEscape = false
            endSession()
            return
        }
        if let back = pendingTab {
            pendingTab = nil
            step(back: back)
        }
    }

    private func step(back: Bool) {
        let apps = liveApps()
        guard apps.count > 1 else {
            endSession()
            return
        }
        if !session {
            session = true
            index = back ? apps.count - 1 : 1
        } else if back {
            index = (index - 1 + apps.count) % apps.count
        } else {
            index = (index + 1) % apps.count
        }
        publish(apps[index])
    }

    private func publish(_ app: NSRunningApplication) {
        let windows = DockPreviewWindows.list(app: app)
        let id = app.bundleIdentifier ?? app.localizedName ?? "\(app.processIdentifier)"
        if windows.isEmpty {
            onChange(nil)
            return
        }
        onChange(
            AppSwitcherPreviewHover(
                bundleID: id,
                appName: app.localizedName ?? id,
                appIcon: app.icon ?? NSImage(size: NSSize(width: 64, height: 64)),
                windows: windows,
                switcherFrame: Self.switcherFrame() ?? .zero
            )
        )
    }

    private func endSession() {
        let was = session
        session = false
        index = 0
        if was {
            onChange(nil)
        }
    }

    private func seedMRU() {
        let running = regularApps()
        mru = running.map(\.processIdentifier)
        if let front = running.first(where: \.isActive)?.processIdentifier {
            mru.removeAll { $0 == front }
            mru.insert(front, at: 0)
        }
    }

    private func noteActivate(_ app: NSRunningApplication) {
        guard app.activationPolicy == .regular, !app.isTerminated else { return }
        mru.removeAll { $0 == app.processIdentifier }
        mru.insert(app.processIdentifier, at: 0)
    }

    private func liveApps() -> [NSRunningApplication] {
        let running = Dictionary(
            uniqueKeysWithValues: regularApps().map { ($0.processIdentifier, $0) }
        )
        var seen = Set<pid_t>()
        var next: [NSRunningApplication] = []
        for pid in mru {
            if let app = running[pid], seen.insert(pid).inserted {
                next.append(app)
            }
        }
        for (pid, app) in running where seen.insert(pid).inserted {
            next.append(app)
        }
        return next
    }

    private func regularApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated
        }
    }

    /// Native Command-Tab strip: a wide Dock window, not the edge strip.
    private static func switcherFrame() -> CGRect? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        var best: CGRect?
        var bestScore: CGFloat = 0
        for entry in info {
            let owner = entry[kCGWindowOwnerName as String] as? String ?? ""
            guard owner == "Dock" else { continue }
            let layer = entry[kCGWindowLayer as String] as? Int ?? 0
            guard layer > 0 else { continue }
            guard let bounds = cgBounds(entry[kCGWindowBounds as String] as? [String: Any]) else {
                continue
            }
            guard bounds.width >= 180, bounds.height >= 48, bounds.height <= 320 else { continue }
            if isDockStrip(bounds) { continue }
            let score = bounds.width * bounds.height
            if score > bestScore {
                bestScore = score
                best = bounds
            }
        }
        return best.map { WindowLayout.cocoaFrame(from: $0) }
    }

    private static func isDockStrip(_ quartz: CGRect) -> Bool {
        let cocoa = WindowLayout.cocoaFrame(from: quartz)
        let mid = CGPoint(x: cocoa.midX, y: cocoa.midY)
        return DockGeometry.isNearDock(mid) && (quartz.height < 90 || quartz.width < 90)
    }

    private static func cgBounds(_ dict: [String: Any]?) -> CGRect? {
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
}
