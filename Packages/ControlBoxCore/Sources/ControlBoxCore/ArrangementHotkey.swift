import CoreGraphics
import Foundation

public enum ArrangementHotkeyAction: Equatable, Sendable {
    case index(Int)
    case next
    case previous
}

public enum ArrangementHotkey {
    public static func configure(
        enabled: Bool,
        flags: CGEventFlags,
        handler: ((ArrangementHotkeyAction) -> Void)?
    ) {
        Controller.shared.configure(enabled: enabled, flags: flags, handler: handler)
    }

    public static func stop() {
        configure(enabled: false, flags: [], handler: nil)
    }

    public static func isLayoutKey(_ key: UInt16) -> Bool {
        Controller.action(for: key) != nil
    }
}

private final class Controller: @unchecked Sendable {
    static let shared = Controller()

    private let lock = NSLock()
    private var enabled = false
    private var flags: CGEventFlags = []
    private var handler: ((ArrangementHotkeyAction) -> Void)?
    private var port: CFMachPort?
    private var source: CFRunLoopSource?

    func configure(
        enabled: Bool,
        flags: CGEventFlags,
        handler: ((ArrangementHotkeyAction) -> Void)?
    ) {
        lock.lock()
        self.flags = ModifierChords.normalized(flags)
        self.handler = handler
        self.enabled = enabled && ModifierChords.count(self.flags) >= 3 && handler != nil
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
        let handler = self.handler
        lock.unlock()

        guard enabled, let handler else { return Unmanaged.passUnretained(event) }
        if ShortcutCapture.isActive {
            return Unmanaged.passUnretained(event)
        }
        let bits = ModifierChords.live(event.flags)
        guard bits == need, !need.isEmpty else { return Unmanaged.passUnretained(event) }

        let key = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        guard let action = Self.action(for: key) else { return Unmanaged.passUnretained(event) }

        if type == .keyDown {
            let repeats = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if !repeats || action == .next || action == .previous {
                handler(action)
            }
        }
        return nil
    }

    static func action(for key: UInt16) -> ArrangementHotkeyAction? {
        if let number = numberKeys[key] {
            return .index(number)
        }
        switch key {
        case 123, 126: return .previous
        case 124, 125: return .next
        default: return nil
        }
    }

    static let numberKeys: [UInt16: Int] = [
        18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9, 29: 10,
        83: 1, 84: 2, 85: 3, 86: 4, 87: 5, 88: 6, 89: 7, 91: 8, 92: 9, 82: 10
    ]
}
