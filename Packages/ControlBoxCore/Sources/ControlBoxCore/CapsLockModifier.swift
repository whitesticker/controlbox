import AppKit
import CoreGraphics
import Foundation
import IOKit.hid

/// Caps Lock as a hold key that synthesizes a chosen modifier chord for
/// Control Box only. Swallows keycode 57 so the key does not toggle caps.
public enum CapsLockModifier {
    public static let keyCode: Int64 = 57
    public static let defaultMappedFlags: CGEventFlags = .maskControl

    public static var isHeld: Bool {
        Controller.shared.isHeld
    }

    public static var mappedFlags: CGEventFlags {
        get { Controller.shared.mappedFlags }
        set { Controller.shared.mappedFlags = ModifierChords.normalized(newValue) }
    }

    public static var onHoldChange: ((Bool) -> Void)? {
        get { Controller.shared.onHoldChange }
        set { Controller.shared.onHoldChange = newValue }
    }

    public static func start() {
        Controller.shared.start()
    }

    public static func stop() {
        Controller.shared.stop()
    }
}

private final class Controller: @unchecked Sendable {
    static let shared = Controller()

    private let lock = NSLock()
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var hid: IOHIDManager?
    private var held = false
    private var hidReportsHold = false
    private var lastFlags: CGEventFlags = []
    private var passUntil = Date.distantPast
    var mappedFlags: CGEventFlags = CapsLockModifier.defaultMappedFlags
    var onHoldChange: ((Bool) -> Void)?

    var isHeld: Bool {
        lock.lock()
        defer { lock.unlock() }
        return held
    }

    func start() {
        startHID()
        if let port {
            CGEvent.tapEnable(tap: port, enable: true)
            if CGEvent.tapIsEnabled(tap: port) {
                clearSystemLockIfNeeded()
                return
            }
            stopTap()
        }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
            | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
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
        clearSystemLockIfNeeded()
    }

    func stop() {
        stopHID()
        stopTap()
        setHeld(false)
        lock.lock()
        hidReportsHold = false
        passUntil = .distantPast
        lastFlags = []
        lock.unlock()
    }

    private func startHID() {
        if hid != nil { return }
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatchingMultiple(mgr, [[
            kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Keyboard
        ]] as CFArray)
        let info = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(mgr, { context, _, _, value in
            guard let context else { return }
            Unmanaged<Controller>.fromOpaque(context).takeUnretainedValue().handleHID(value)
        }, info)
        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        guard IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            return
        }
        hid = mgr
    }

    private func stopHID() {
        guard let hid else { return }
        IOHIDManagerUnscheduleFromRunLoop(hid, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(hid, IOOptionBits(kIOHIDOptionsTypeNone))
        self.hid = nil
    }

    private func handleHID(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        guard IOHIDElementGetUsagePage(element) == UInt32(kHIDPage_KeyboardOrKeypad),
              IOHIDElementGetUsage(element) == 0x39 else { return }
        lock.lock()
        hidReportsHold = true
        lock.unlock()
        setHeld(IOHIDValueGetIntegerValue(value) != 0)
    }

    private func stopTap() {
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

        let key = event.getIntegerValueField(.keyboardEventKeycode)
        lock.lock()
        let passing = Date() < passUntil
        let hidOwnsHold = hidReportsHold
        let previousFlags = lastFlags
        if type == .flagsChanged {
            lastFlags = event.flags
        }
        lock.unlock()
        if passing, isCapsEvent(type: type, key: key, flags: event.flags, previous: previousFlags) {
            return Unmanaged.passUnretained(event)
        }

        guard isCapsEvent(type: type, key: key, flags: event.flags, previous: previousFlags) else {
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown {
            if !hidOwnsHold, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                setHeld(true)
            }
            return nil
        }
        if type == .keyUp {
            if !hidOwnsHold {
                setHeld(false)
            }
            return nil
        }
        if type == .flagsChanged {
            if !hidOwnsHold {
                setHeld(!isHeld)
            }
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    private func isCapsEvent(
        type: CGEventType,
        key: Int64,
        flags: CGEventFlags,
        previous: CGEventFlags
    ) -> Bool {
        if key == CapsLockModifier.keyCode { return true }
        guard type == .flagsChanged else { return false }
        let withoutAlpha = flags.subtracting(.maskAlphaShift)
        let previousWithout = previous.subtracting(.maskAlphaShift)
        return withoutAlpha == previousWithout
            && flags.contains(.maskAlphaShift) != previous.contains(.maskAlphaShift)
    }

    private func setHeld(_ next: Bool) {
        lock.lock()
        let changed = held != next
        held = next
        let handler = onHoldChange
        lock.unlock()
        guard changed else { return }
        DispatchQueue.main.async {
            handler?(next)
        }
    }

    private func clearSystemLockIfNeeded() {
        guard NSEvent.modifierFlags.contains(.capsLock) else { return }
        lock.lock()
        passUntil = Date().addingTimeInterval(0.15)
        lock.unlock()
        let source = CGEventSource(stateID: .hidSystemState)
        if let down = CGEvent(keyboardEventSource: source, virtualKey: 57, keyDown: true) {
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: source, virtualKey: 57, keyDown: false) {
            up.post(tap: .cghidEventTap)
        }
    }
}
