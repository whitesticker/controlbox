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
        private var started = false
        private var axis: Axis = .horizontal

        var isActive: Bool { started }
        var offset: Double { origin }
        var currentAxis: Axis { axis }

        func add(_ delta: Double, axis: Axis) {
            guard abs(delta) > 0.00005 else { return }
            self.axis = axis
            if !started {
                started = true
                origin = 0
                lastDelta = 0
                post(delta: delta, phase: .began)
            } else {
                post(delta: delta, phase: .changed)
            }
        }

        @discardableResult
        func end() -> Bool {
            guard started else { return false }
            let commit = abs(origin) >= 0.28
            post(delta: lastDelta, phase: commit ? .ended : .cancelled)
            started = false
            origin = 0
            lastDelta = 0
            return commit
        }

        func cancel() {
            guard started else { return }
            post(delta: lastDelta, phase: .cancelled)
            started = false
            origin = 0
            lastDelta = 0
        }

        private func post(delta: Double, phase: Phase) {
            var resolved = phase
            if phase == .began {
                origin = delta
            } else if phase == .changed {
                origin += delta
            } else if phase == .ended {
                let lastSign = (lastDelta > 0 ? 1 : 0) - (lastDelta < 0 ? 1 : 0)
                let originSign = (origin > 0 ? 1 : 0) - (origin < 0 ? 1 : 0)
                if lastSign != 0, originSign != 0, lastSign != originSign {
                    resolved = .cancelled
                }
            }

            let exitSpeed = (resolved == .ended || resolved == .cancelled) ? lastDelta * 100 : 0
            postPair(offset: origin, axis: axis, phase: resolved, exitSpeed: exitSpeed)
            lastDelta = delta
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

    static var horizontalSpan: Double {
        max(NSScreen.main?.frame.width ?? 1440, 800)
    }

    static var verticalSpan: Double {
        max((NSScreen.main?.frame.height ?? 900) * 1.7, 700)
    }

    static var verticalSwipeSpan: Double {
        max(NSScreen.main?.frame.height ?? 900, 600) * 0.7
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
