import CoreGraphics
import Foundation

public enum WindowOrganizeHotkey {
    public static func configure(
        enabled: Bool,
        flags: CGEventFlags,
        virtualKey: UInt16,
        handler: (() -> Void)?
    ) {
        Controller.shared.configure(
            enabled: enabled,
            flags: flags,
            virtualKey: virtualKey,
            handler: handler
        )
    }

    public static func stop() {
        configure(enabled: false, flags: [], virtualKey: 0, handler: nil)
    }
}

private final class Controller: @unchecked Sendable {
    static let shared = Controller()

    private let lock = NSLock()
    private var enabled = false
    private var flags: CGEventFlags = []
    private var virtualKey: UInt16 = 0
    private var handler: (() -> Void)?
    private var port: CFMachPort?
    private var source: CFRunLoopSource?

    func configure(
        enabled: Bool,
        flags: CGEventFlags,
        virtualKey: UInt16,
        handler: (() -> Void)?
    ) {
        lock.lock()
        self.flags = ModifierChords.normalized(flags)
        self.virtualKey = virtualKey
        self.handler = handler
        self.enabled = enabled
            && !self.flags.isEmpty
            && handler != nil
        let shouldRun = self.enabled
        lock.unlock()
        if shouldRun {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        if let port {
            CGEvent.tapEnable(tap: port, enable: true)
            if CGEvent.tapIsEnabled(tap: port) { return }
            stop()
        }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, info in
                guard let info else { return Unmanaged.passUnretained(event) }
                let controller = Unmanaged<Controller>.fromOpaque(info).takeUnretainedValue()
                return controller.handle(type: type, event: event)
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
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        lock.lock()
        let enabled = self.enabled
        let need = self.flags
        let keyNeed = self.virtualKey
        let handler = self.handler
        lock.unlock()

        guard enabled, let handler, !need.isEmpty else {
            return Unmanaged.passUnretained(event)
        }
        if ShortcutCapture.isActive {
            return Unmanaged.passUnretained(event)
        }
        let bits = ModifierChords.normalized(event.flags)
        guard bits == need else { return Unmanaged.passUnretained(event) }
        let key = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        guard key == keyNeed else { return Unmanaged.passUnretained(event) }

        if type == .keyDown {
            let repeats = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if !repeats {
                handler()
            }
        }
        return nil
    }
}
