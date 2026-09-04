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
        /// Live Spaces follow: macOS commits at most one desktop per gesture
        /// session, so each full page is ended and a new session starts.
        var locksFullPages = false

        private var origin = 0.0
        private var lastDelta = 0.0
        private var pending = 0.0
        private var lastPost = Date.distantPast
        private var started = false
        private var axis: Axis = .horizontal
        private var committedPages = 0.0
        private var lastAbsolute = 0.0

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
            lastAbsolute = offset
            if locksFullPages, axis == .horizontal {
                consumeFullPages(total: offset)
                postRemaining(offset - committedPages)
                return
            }
            postRemaining(offset)
        }

        @discardableResult
        func end(exitSpeed: Double? = nil, snapToNearestPage: Bool = true) -> Bool {
            if locksFullPages, axis == .horizontal {
                consumeFullPages(total: lastAbsolute)
                postRemaining(lastAbsolute - committedPages, force: true)
                let locked = abs(committedPages) >= 0.5
                let did = started ? finishNearestPage(exitSpeed: exitSpeed) : false
                committedPages = 0
                lastAbsolute = 0
                return did || locked
            }
            guard started else { return false }
            if abs(pending - origin) > 0.00005 {
                origin = pending
                postAbsolute(origin, phase: .changed)
            }
            if snapToNearestPage {
                return finishNearestPage(exitSpeed: exitSpeed)
            }
            let commit = abs(origin) >= 0.28
            postAbsolute(origin, phase: commit ? .ended : .cancelled, exitSpeed: exitSpeed)
            resetLiveState()
            return commit
        }

        func cancel() {
            if started {
                postAbsolute(origin, phase: .cancelled)
            }
            resetLiveState()
            committedPages = 0
            lastAbsolute = 0
        }

        /// Space (or Mission Control page) whose center is closest to the
        /// current preview. Halfway rounds away from the start.
        static func landingPage(offset: Double, axis: Axis) -> Double {
            let page = offset.rounded()
            switch axis {
            case .horizontal:
                return page
            case .vertical:
                return min(max(page, -1), 1)
            }
        }

        /// macOS `.ended` keeps one Space and rubber-bands the rest, even at
        /// offset 2.0. End the current session at ±1 and keep going.
        private func consumeFullPages(total: Double) {
            while abs(total - committedPages) >= 1.0 {
                let sign = (total - committedPages) > 0 ? 1.0 : -1.0
                if !started {
                    started = true
                    origin = 0
                    lastDelta = 0
                    pending = 0
                    lastPost = Date()
                    postAbsolute(0, phase: .began)
                }
                origin = sign
                pending = sign
                lastDelta = sign
                lastPost = Date()
                postAbsolute(origin, phase: .changed)
                postAbsolute(origin, phase: .ended, exitSpeed: 6 * sign)
                resetLiveState()
                committedPages += sign
            }
        }

        private func postRemaining(_ remaining: Double, force: Bool = false) {
            if !started {
                guard abs(remaining) > 0.00005 else { return }
                started = true
                origin = remaining
                lastDelta = remaining
                pending = remaining
                lastPost = Date()
                postAbsolute(remaining, phase: .began)
                return
            }
            pending = remaining
            let now = Date()
            if !force {
                guard now.timeIntervalSince(lastPost) >= 1.0 / 90.0 || abs(remaining - origin) >= 0.008 else {
                    return
                }
            }
            let delta = remaining - origin
            guard abs(delta) > 0.00005 else { return }
            lastPost = now
            lastDelta = delta
            origin = remaining
            postAbsolute(remaining, phase: .changed)
        }

        private func finishNearestPage(exitSpeed: Double?) -> Bool {
            let page = Self.landingPage(offset: origin, axis: axis)
            if abs(page) < 0.5 {
                postAbsolute(origin, phase: .cancelled, exitSpeed: exitSpeed ?? 0)
                resetLiveState()
                return false
            }
            if abs(page - origin) > 0.00005 {
                origin = page
                postAbsolute(origin, phase: .changed)
            }
            let sign = page > 0 ? 1.0 : -1.0
            postAbsolute(origin, phase: .ended, exitSpeed: exitSpeed ?? 6 * sign)
            resetLiveState()
            return true
        }

        private func resetLiveState() {
            started = false
            origin = 0
            lastDelta = 0
            pending = 0
        }

        private func postAbsolute(_ offset: Double, phase: Phase, exitSpeed: Double? = nil) {
            let speed: Double
            if let exitSpeed {
                speed = exitSpeed
            } else if phase == .ended || phase == .cancelled {
                speed = lastDelta * 100
            } else {
                speed = 0
            }
            postPair(offset: offset, axis: axis, phase: phase, exitSpeed: speed)
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
        session.end(snapToNearestPage: false)
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
