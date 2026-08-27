import AppKit
import CoreGraphics
import Foundation

/// Intercepts mouse-wheel events the way Scroll Reverser does: a session event
/// tap rewrites scroll deltas in place. Firmware invert bits and HID++ divert
/// are not required for direction or speed to take effect.
public final class MouseScrollTap: @unchecked Sendable {
    public var wantNatural = true
    public var verticalScale = 1.0
    public var horizontalScale = 1.0
    public var smoothScrolling = true

    private var activePort: CFMachPort?
    private var activeSource: CFRunLoopSource?
    private var gesturePort: CFMachPort?
    private var gestureSource: CFRunLoopSource?
    private var touching = 0
    private var lastTouchAt: UInt64 = 0
    private var lineRemainder: [UInt32: Double] = [:]
    private var pointRemainder: [UInt32: Double] = [:]

    public var isActive: Bool { activePort != nil && activeSource != nil }

    public func setActive(_ active: Bool) {
        if active {
            start()
        } else {
            stop()
        }
    }

    public init() {}

    public func start() {
        if isActive { return }
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        let scrollMask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        let gestureMask = CGEventMask(1 << 29)

        guard let scrollTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: scrollMask,
            callback: Self.callback,
            userInfo: userInfo
        ) else { return }

        let gestureTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: gestureMask,
            callback: Self.callback,
            userInfo: userInfo
        )

        let scrollSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, scrollTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), scrollSource, .commonModes)
        activePort = scrollTap
        activeSource = scrollSource

        if let gestureTap {
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, gestureTap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            gesturePort = gestureTap
            gestureSource = source
        }
    }

    public func stop() {
        if let activeSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), activeSource, .commonModes)
        }
        if let activePort {
            CFMachPortInvalidate(activePort)
        }
        if let gestureSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), gestureSource, .commonModes)
        }
        if let gesturePort {
            CFMachPortInvalidate(gesturePort)
        }
        activePort = nil
        activeSource = nil
        gesturePort = nil
        gestureSource = nil
        touching = 0
        lastTouchAt = 0
        lineRemainder.removeAll()
        pointRemainder.removeAll()
    }

    private static let callback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let tap = Unmanaged<MouseScrollTap>.fromOpaque(refcon).takeUnretainedValue()
        return tap.handle(type: type, event: event)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let activePort { CGEvent.tapEnable(tap: activePort, enable: true) }
            if let gesturePort { CGEvent.tapEnable(tap: gesturePort, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        if type.rawValue == 29 {
            if let nsEvent = NSEvent(cgEvent: event) {
                let count = nsEvent.touches(matching: .touching, in: nil).count
                if count >= 2 {
                    touching = max(touching, count)
                    lastTouchAt = DispatchTime.now().uptimeNanoseconds
                }
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .scrollWheel else {
            return Unmanaged.passUnretained(event)
        }

        let pid = event.getIntegerValueField(.eventSourceUnixProcessID)
        if pid != 0 {
            return Unmanaged.passUnretained(event)
        }

        let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let recentTouches = touching >= 2
            && DispatchTime.now().uptimeNanoseconds &- lastTouchAt < 222_000_000
        touching = 0
        if continuous, recentTouches {
            return Unmanaged.passUnretained(event)
        }

        let invertedFromDevice = NSEvent(cgEvent: event)?.isDirectionInvertedFromDevice ?? false
        let reverse = wantNatural != invertedFromDevice
        let vmul = (reverse ? -1.0 : 1.0) * max(verticalScale, 0.05)
        let hmul = (reverse ? -1.0 : 1.0) * max(horizontalScale, 0.05)
        if abs(vmul - 1) < 0.001, abs(hmul - 1) < 0.001 {
            return Unmanaged.passUnretained(event)
        }

        apply(
            vmul,
            to: event,
            continuous: continuous,
            line: .scrollWheelEventDeltaAxis1,
            point: .scrollWheelEventPointDeltaAxis1,
            fixed: .scrollWheelEventFixedPtDeltaAxis1
        )
        apply(
            hmul,
            to: event,
            continuous: continuous,
            line: .scrollWheelEventDeltaAxis2,
            point: .scrollWheelEventPointDeltaAxis2,
            fixed: .scrollWheelEventFixedPtDeltaAxis2
        )
        return Unmanaged.passUnretained(event)
    }

    /// Scroll Reverser: set line delta first, then point/fixed. Setting the line
    /// field makes macOS rewrite the pixel fields, so those have to be restored.
    private func apply(
        _ multiplier: Double,
        to event: CGEvent,
        continuous: Bool,
        line: CGEventField,
        point: CGEventField,
        fixed: CGEventField
    ) {
        guard abs(multiplier - 1) >= 0.001 else { return }
        let lineDelta = Double(event.getIntegerValueField(line))
        let pointDelta = Double(event.getIntegerValueField(point))
        let fixedDelta = event.getDoubleValueField(fixed)
        // High-res / smooth wheels emit many tiny events. Accumulate leftovers
        // so they still move, and do not force a leftover ±1 line on each one.
        let keepLineStep = !continuous && !smoothScrolling
        event.setIntegerValueField(
            line,
            value: scaledInt(lineDelta * multiplier, original: lineDelta, field: line, keepStep: keepLineStep, store: &lineRemainder)
        )
        event.setIntegerValueField(
            point,
            value: scaledInt(pointDelta * multiplier, original: pointDelta, field: point, keepStep: false, store: &pointRemainder)
        )
        event.setDoubleValueField(fixed, value: scaledDouble(fixedDelta * multiplier, original: fixedDelta))
    }

    private func scaledInt(
        _ value: Double,
        original: Double,
        field: CGEventField,
        keepStep: Bool,
        store: inout [UInt32: Double]
    ) -> Int64 {
        let key = field.rawValue
        var remainder = store[key] ?? 0
        if original != 0, remainder != 0, (value > 0) != (remainder > 0) {
            remainder = 0
        }
        let total = remainder + value
        let rounded = total.rounded(.towardZero)
        if keepStep, original != 0, rounded == 0 {
            store[key] = 0
            return original > 0 ? 1 : -1
        }
        store[key] = total - rounded
        return Int64(rounded)
    }

    private func scaledDouble(_ value: Double, original: Double) -> Double {
        if original != 0, abs(value) < 0.0001 {
            return original > 0 ? 0.1 : -0.1
        }
        return value
    }
}
