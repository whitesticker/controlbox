import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum EventPoster {
    private static var fractionalCursor = CGPoint.zero
    private static var hasFractionalCursor = false

    static func isTrusted() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func promptForTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func key(_ virtualKey: UInt16, flags: CGEventFlags, down: Bool) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: down) else { return }
        if flags.rawValue == 0, let modifierFlags = ModifierKey.flags(for: virtualKey, down: down) {
            event.flags = modifierFlags
        } else {
            event.flags = flags
        }
        event.post(tap: .cghidEventTap)
    }

    static func mouseClick(right: Bool, down: Bool) {
        let location = CGEvent(source: nil)?.location ?? .zero
        if down {
            MouseClickState.noteDown(right: right, at: location)
        }
        let type: CGEventType
        let button: CGMouseButton
        if right {
            type = down ? .rightMouseDown : .rightMouseUp
            button = .right
        } else {
            type = down ? .leftMouseDown : .leftMouseUp
            button = .left
        }
        let source = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: type,
            mouseCursorPosition: location,
            mouseButton: button
        ) else { return }
        event.setIntegerValueField(.mouseEventClickState, value: MouseClickState.count)
        event.post(tap: .cghidEventTap)
    }

    static func wouldBeDoubleClick(right: Bool) -> Bool {
        MouseClickState.wouldBeDoubleClick(right: right, at: CGEvent(source: nil)?.location ?? .zero)
    }

    static func recordClick(right: Bool) {
        MouseClickState.noteDown(right: right, at: CGEvent(source: nil)?.location ?? .zero)
    }

    static func moveMouse(dx: Double, dy: Double) {
        guard abs(dx) > 0.0001 || abs(dy) > 0.0001 else { return }
        let reported = CGEvent(source: nil)?.location ?? .zero
        if !hasFractionalCursor || hypot(reported.x - fractionalCursor.x, reported.y - fractionalCursor.y) > 6 {
            fractionalCursor = reported
            hasFractionalCursor = true
        }
        fractionalCursor.x += CGFloat(dx)
        fractionalCursor.y += CGFloat(dy)
        fractionalCursor = clampToDisplays(fractionalCursor)
        let source = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: .mouseMoved,
            mouseCursorPosition: fractionalCursor,
            mouseButton: .left
        ) else { return }
        event.post(tap: .cghidEventTap)
    }

    static func scroll(deltaY: Double, deltaX: Double = 0, continuous: Bool = false) {
        guard abs(deltaY) > 0.0001 || abs(deltaX) > 0.0001 else { return }
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: 0,
            wheel2: 0,
            wheel3: 0
        ) else { return }

        let pixelY = -deltaY
        let pixelX = -deltaX
        if continuous {
            event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: pixelY)
            event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: pixelX)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: pixelY)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: pixelX)
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: Int64((pixelY / 10).rounded()))
            event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: Int64((pixelX / 10).rounded()))
        } else {
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: Int64((pixelY * 3).rounded()))
            event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: Int64((pixelX * 3).rounded()))
        }
        event.post(tap: .cghidEventTap)
    }

    static func media(_ key: Int32, down: Bool) {
        let data1 = Int((key << 16) | ((down ? 0x0A : 0x0B) << 8))
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xA00),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        )?.cgEvent else { return }
        event.post(tap: .cghidEventTap)
    }

    static func system(_ action: ControlAction) {
        SystemNavigation.perform(action)
    }

    private static func clampToDisplays(_ point: CGPoint) -> CGPoint {
        var bounds = CGRect.null
        for screen in NSScreen.screens {
            bounds = bounds.union(screen.frame)
        }
        guard !bounds.isNull else { return point }
        return CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX - 1),
            y: min(max(point.y, bounds.minY), bounds.maxY - 1)
        )
    }
}

enum MediaKey {
    static let soundUp: Int32 = 0
    static let soundDown: Int32 = 1
    static let mute: Int32 = 7
    static let play: Int32 = 16
    static let next: Int32 = 17
    static let previous: Int32 = 18
}

private enum MouseClickState {
    static var count: Int64 = 1
    private static var lastAt: TimeInterval = 0
    private static var lastPoint = CGPoint.zero
    private static var lastWasRight = false

    static func wouldBeDoubleClick(right: Bool, at point: CGPoint) -> Bool {
        guard lastAt > 0, right == lastWasRight else { return false }
        let interval = NSEvent.doubleClickInterval + 0.18
        guard ProcessInfo.processInfo.systemUptime - lastAt <= interval else { return false }
        return hypot(point.x - lastPoint.x, point.y - lastPoint.y) <= 10
    }

    static func noteDown(right: Bool, at point: CGPoint) {
        if wouldBeDoubleClick(right: right, at: point) {
            count += 1
        } else {
            count = 1
        }
        lastAt = ProcessInfo.processInfo.systemUptime
        lastPoint = point
        lastWasRight = right
    }
}

private enum ModifierKey {
    static let leftControl: UInt16 = 59
    static let rightControl: UInt16 = 62
    static let leftShift: UInt16 = 56
    static let rightShift: UInt16 = 60
    static let leftCommand: UInt16 = 55
    static let rightCommand: UInt16 = 54
    static let leftOption: UInt16 = 58
    static let rightOption: UInt16 = 61

    // Device-dependent bits from IOLLEvent.h so Karabiner and system remaps
    // can tell left modifiers from right.
    static let deviceLeftControl = CGEventFlags(rawValue: 0x00000001)
    static let deviceLeftShift = CGEventFlags(rawValue: 0x00000002)
    static let deviceRightShift = CGEventFlags(rawValue: 0x00000004)
    static let deviceLeftCommand = CGEventFlags(rawValue: 0x00000008)
    static let deviceRightCommand = CGEventFlags(rawValue: 0x00000010)
    static let deviceLeftOption = CGEventFlags(rawValue: 0x00000020)
    static let deviceRightOption = CGEventFlags(rawValue: 0x00000040)
    static let deviceRightControl = CGEventFlags(rawValue: 0x00002000)

    static func flags(for virtualKey: UInt16, down: Bool) -> CGEventFlags? {
        guard down else { return [] }
        switch virtualKey {
        case leftOption: return [.maskAlternate, deviceLeftOption]
        case rightOption: return [.maskAlternate, deviceRightOption]
        case leftCommand: return [.maskCommand, deviceLeftCommand]
        case rightCommand: return [.maskCommand, deviceRightCommand]
        case leftShift: return [.maskShift, deviceLeftShift]
        case rightShift: return [.maskShift, deviceRightShift]
        case leftControl: return [.maskControl, deviceLeftControl]
        case rightControl: return [.maskControl, deviceRightControl]
        default: return nil
        }
    }
}
