import CoreGraphics
import Foundation

public enum MXWheelMode: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case verticalScroll
    case horizontalScroll
    case switchTabs
    case volume
    case zoom
    case switchDesktops
    case switchApplications
    case none

    public var title: String {
        switch self {
        case .verticalScroll: return "Vertical Scroll"
        case .horizontalScroll: return "Horizontal Scroll"
        case .switchTabs: return "Switch Between Tabs"
        case .volume: return "Volume"
        case .zoom: return "Zoom In/Out"
        case .switchDesktops: return "Switch Between Desktops"
        case .switchApplications: return "Switch Between Apps"
        case .none: return "None"
        }
    }

    public static let thumbWheelOptions: [MXWheelMode] = [
        .horizontalScroll,
        .verticalScroll,
        .switchTabs,
        .volume,
        .zoom,
        .switchDesktops,
        .switchApplications,
        .none
    ]
}

/// Delta-driven MX thumb-wheel actions. This is intentionally separate from
/// ControlEngine's one-shot button actions: a wheel burst can repeat and
/// accelerate without changing button Previous/Next Tab behavior.
public final class MXWheelActionEngine: @unchecked Sendable {
    private struct Repeater {
        var remainder = 0.0
        var burst = 0
        var direction = 0.0
        var lastInputAt = Date.distantPast
        var lastEmitAt = Date.distantPast

        mutating func reset() {
            remainder = 0
            burst = 0
            direction = 0
            lastInputAt = .distantPast
            lastEmitAt = .distantPast
        }

        mutating func takeSteps(
            delta: Double,
            mode: MXWheelMode,
            now: Date
        ) -> Int {
            let nextDirection = delta > 0 ? 1.0 : -1.0
            let gap = now.timeIntervalSince(lastInputAt)
            let resetGap: TimeInterval = mode == .switchTabs ? 0.50 : 0.28
            if gap > resetGap || direction != nextDirection {
                remainder = 0
                burst = 0
            } else if gap < 0.12 {
                burst = min(burst + 1, 10)
            } else {
                burst = max(burst - 1, 0)
            }
            direction = nextDirection
            lastInputAt = now

            // HID++ 0x2150: one MX ratchet is typically 120 counts. Tabs must
            // not treat that as three steps the way volume / apps still can.
            let units: Double
            switch mode {
            case .switchTabs:
                units = min(max(abs(delta) / 120.0, 0.08), 1.0)
            default:
                units = min(max(abs(delta) / 8.0, 0.35), 3.0)
            }

            let accelerated = mode == .volume || mode == .switchApplications
            let boost = accelerated ? 1.0 + Double(burst) * 0.10 : 1.0
            remainder += units * boost

            let interval: TimeInterval
            switch mode {
            case .switchTabs:
                interval = 0.22
            case .switchDesktops:
                interval = 0.28
            case .zoom:
                interval = 0.11
            case .switchApplications:
                interval = max(0.055, 0.10 - Double(burst) * 0.004)
            default:
                interval = max(0.035, 0.085 - Double(burst) * 0.005)
            }
            guard now.timeIntervalSince(lastEmitAt) >= interval else { return 0 }

            let cap: Int
            switch mode {
            case .switchTabs, .switchDesktops, .zoom:
                cap = 1
            case .switchApplications:
                cap = 2
            default:
                cap = 3
            }
            let steps = min(Int(remainder), cap)
            guard steps > 0 else { return 0 }
            remainder -= Double(steps)
            lastEmitAt = now
            return steps
        }
    }

    private var thumbRepeater = Repeater()

    public init() {}

    public func reset() {
        thumbRepeater.reset()
        AppSwitcher.cancel()
    }

    public func process(
        delta: Double,
        mode: MXWheelMode,
        naturalScrolling: Bool,
        scrollSpeed: Double
    ) {
        guard delta != 0 else { return }

        switch mode {
        case .verticalScroll, .horizontalScroll:
            postScroll(
                delta: delta,
                horizontal: mode == .horizontalScroll,
                naturalScrolling: naturalScrolling,
                speed: scrollSpeed
            )
            return
        case .none:
            return
        default:
            break
        }

        let now = Date()
        let steps = thumbRepeater.takeSteps(delta: delta, mode: mode, now: now)
        guard steps > 0 else { return }

        let forward = delta > 0
        let increase = delta > 0
        for _ in 0..<steps {
            perform(mode: mode, forward: forward, increase: increase)
        }
    }

    private func postScroll(
        delta: Double,
        horizontal: Bool,
        naturalScrolling: Bool,
        speed: Double
    ) {
        let gain = 0.35 + min(max(speed, 0), 1) * 2.1
        let direction = naturalScrolling ? 1.0 : -1.0
        let pixels = delta * gain * direction
        EventPoster.scroll(
            deltaY: horizontal ? 0 : pixels,
            deltaX: horizontal ? pixels : 0,
            continuous: true
        )
    }

    private func perform(mode: MXWheelMode, forward: Bool, increase: Bool) {
        switch mode {
        case .switchTabs:
            pulseKey(forward ? 30 : 33, flags: [.maskCommand, .maskShift])
        case .volume:
            EventPoster.media(increase ? MediaKey.soundUp : MediaKey.soundDown, down: true)
            EventPoster.media(increase ? MediaKey.soundUp : MediaKey.soundDown, down: false)
        case .zoom:
            // Public APIs cannot post a magnification gesture to another app.
            // Command-= and Command-- are the interoperable app-content zoom path.
            pulseKey(increase ? 24 : 27, flags: .maskCommand)
        case .switchDesktops:
            DockSwipe.playOneSpace(axis: .horizontal, towardPositive: forward)
        case .switchApplications:
            AppSwitcher.step(back: !forward)
        case .verticalScroll, .horizontalScroll, .none:
            break
        }
    }

    private func pulseKey(_ virtualKey: UInt16, flags: CGEventFlags) {
        EventPoster.key(virtualKey, flags: flags, down: true)
        EventPoster.key(virtualKey, flags: flags, down: false)
    }
}
