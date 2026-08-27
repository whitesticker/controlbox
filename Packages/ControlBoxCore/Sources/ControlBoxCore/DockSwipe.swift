import AppKit
import CoreGraphics
import Foundation

/// Posts the same dock-swipe events a Magic Trackpad uses so Spaces,
/// Mission Control, and App Expose follow the cursor instead of jumping.
enum DockSwipe {
    enum Axis: Int {
        case horizontal = 1
        case vertical = 2
    }

    private enum Phase: Int {
        case began = 1
        case changed = 2
        case ended = 4
        case cancelled = 8
    }

    final class Session {
        private var origin = 0.0
        private var lastDelta = 0.0
        private var pending = 0.0
        private var lastPost = Date.distantPast
        private var started = false
        private var axis: Axis = .horizontal

        var isActive: Bool { started }
        var offset: Double { origin }
        var currentAxis: Axis { axis }

        func add(_ delta: Double, axis: Axis) {
            setAbsolute(origin + delta, axis: axis)
        }

        /// Trackpad-style: the event carries the absolute swipe progress, not a
        /// delta that can jump backward if one sample is missing or reset.
        func setAbsolute(_ offset: Double, axis: Axis) {
            self.axis = axis
            if !started {
                started = true
                origin = offset
                lastDelta = offset
                pending = 0
                lastPost = Date()
                postAbsolute(offset, phase: .began)
                return
            }
            pending = offset
            let now = Date()
            guard now.timeIntervalSince(lastPost) >= 1.0 / 90.0 || abs(offset - origin) >= 0.008 else {
                return
            }
            let delta = offset - origin
            guard abs(delta) > 0.00005 else { return }
            lastPost = now
            lastDelta = delta
            origin = offset
            postAbsolute(offset, phase: .changed)
        }

        @discardableResult
        func end(exitSpeed: Double? = nil) -> Bool {
            guard started else { return false }
            if abs(pending - origin) > 0.00005 {
                origin = pending
                postAbsolute(origin, phase: .changed)
            }
            let commit = abs(origin) >= 0.28
            postAbsolute(origin, phase: commit ? .ended : .cancelled, exitSpeed: exitSpeed)
            started = false
            origin = 0
            lastDelta = 0
            pending = 0
            return commit
        }

        func cancel() {
            guard started else { return }
            postAbsolute(origin, phase: .cancelled)
            started = false
            origin = 0
            lastDelta = 0
            pending = 0
        }

        private func postAbsolute(_ offset: Double, phase: Phase, exitSpeed: Double? = nil) {
            var resolved = phase
            if phase == .ended {
                let lastSign = (lastDelta > 0 ? 1 : 0) - (lastDelta < 0 ? 1 : 0)
                let originSign = (offset > 0 ? 1 : 0) - (offset < 0 ? 1 : 0)
                if lastSign != 0, originSign != 0, lastSign != originSign {
                    resolved = .cancelled
                }
            }
            let speed: Double
            if let exitSpeed {
                speed = exitSpeed
            } else {
                speed = (resolved == .ended || resolved == .cancelled) ? lastDelta * 100 : 0
            }
            postPair(offset: offset, axis: axis, phase: resolved, exitSpeed: speed)
        }
    }

    static func play(axis: Axis, offset: Double) {
        let session = Session()
        let steps = 8
        let step = offset / Double(steps)
        session.add(step, axis: axis)
        for _ in 1..<steps {
            session.add(step, axis: axis)
        }
        session.end()
    }

    /// DualSense button desktop switch only. One Space; 1.5 peeks into the next.
    static func playOneSpace(axis: Axis, towardPositive: Bool) {
        let session = Session()
        let sign = towardPositive ? 1.0 : -1.0
        let steps = 10
        for step in 1...steps {
            session.setAbsolute(sign * Double(step) / Double(steps), axis: axis)
        }
        session.end(exitSpeed: 6 * sign)
    }

    static var horizontalSpan: Double {
        max(NSScreen.main?.frame.width ?? 1440, 800)
    }

    static var verticalSpan: Double {
        max((NSScreen.main?.frame.height ?? 900) * 1.7, 700)
    }

    static var verticalSwipeSpan: Double {
        max(NSScreen.main?.frame.height ?? 900, 600) * 0.7
    }

    /// Same physical travel as a desktop switch at the same haptic-speed slider.
    static var liveVerticalSpan: Double {
        horizontalSpan
    }

    private static func field(_ raw: UInt32) -> CGEventField {
        CGEventField(rawValue: raw)!
    }

    private static func postPair(offset: Double, axis: Axis, phase: Phase, exitSpeed: Double) {
        let companion = CGEvent(source: nil)
        companion?.setDoubleValueField(field(55), value: 29)
        companion?.setDoubleValueField(field(41), value: 33231)

        let event = CGEvent(source: nil)
        event?.setDoubleValueField(field(55), value: 30)
        event?.setDoubleValueField(field(110), value: 23)
        event?.setDoubleValueField(field(132), value: Double(phase.rawValue))
        event?.setDoubleValueField(field(134), value: Double(phase.rawValue))
        event?.setDoubleValueField(field(124), value: offset)

        var offsetFloat = Float(offset)
        var offsetBits: UInt32 = 0
        memcpy(&offsetBits, &offsetFloat, MemoryLayout<Float>.size)
        event?.setIntegerValueField(field(135), value: Int64(offsetBits))
        event?.setDoubleValueField(field(41), value: 33231)

        let weird: Double
        switch axis {
        case .horizontal: weird = 1.401298464324817e-45
        case .vertical: weird = 2.802596928649634e-45
        }
        event?.setDoubleValueField(field(119), value: weird)
        event?.setDoubleValueField(field(139), value: weird)
        event?.setDoubleValueField(field(123), value: Double(axis.rawValue))
        event?.setDoubleValueField(field(165), value: Double(axis.rawValue))
        event?.setIntegerValueField(field(136), value: 0)

        if phase == .ended || phase == .cancelled {
            event?.setDoubleValueField(field(129), value: exitSpeed)
            event?.setDoubleValueField(field(130), value: exitSpeed)
        }

        if let event {
            event.post(tap: .cgSessionEventTap)
        }
        if let companion {
            companion.post(tap: .cgSessionEventTap)
        }
    }
}
