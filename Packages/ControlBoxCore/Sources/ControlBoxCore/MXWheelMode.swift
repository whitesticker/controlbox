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
        case .switchTabs: return "Navigate Between Tabs"
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
/// ControlEngine's one-shot button actions: a wheel burst can repeat without
/// changing button Previous/Next Tab behavior.
///
/// Accumulation, cooldown, and diverted-to-native scaling follow OpenLogi's
/// `0x2150` dispatcher (`wheel.rs` + `ThumbwheelSensitivity`).
public final class MXWheelActionEngine: @unchecked Sendable {
    /// OpenLogi default sensitivity (14) is 1×. Control Box stores that as 50%.
    private static let openLogiDefault = 14
    /// OpenLogi forgets a partly accumulated discrete action after this gap.
    private static let actionDecay: TimeInterval = 0.30
    /// OpenLogi minimum gap between two fires of the same discrete action.
    private static let actionCooldown: TimeInterval = 0.20
    /// Navigate Between Tabs is 1.5× the OpenLogi discrete rate.
    private static let switchTabsRate = 1.5
    /// One quarter-turn of the thumb wheel is one desktop at 1× sensitivity.
    private static let desktopsPerRevolution = 4.0
    private static let desktopIdle: TimeInterval = 0.14
    /// MX4 traced fallback when `getThumbwheelInfo` has not answered yet.
    private static let defaultDivertedResolution = 120

    private struct Repeater {
        var increments = 0
        var direction = 0.0
        var lastInputAt = Date.distantPast
        var lastEmitAt = Date.distantPast

        mutating func reset() {
            increments = 0
            direction = 0
            lastInputAt = .distantPast
            lastEmitAt = .distantPast
        }

        mutating func takeAction(
            delta: Double,
            sensitivity: Double,
            mode: MXWheelMode,
            now: Date
        ) -> Bool {
            let nextDirection = delta > 0 ? 1.0 : -1.0
            if now.timeIntervalSince(lastInputAt) > MXWheelActionEngine.actionDecay
                || direction != nextDirection {
                increments = 0
            }
            direction = nextDirection
            lastInputAt = now
            if now.timeIntervalSince(lastEmitAt) < MXWheelActionEngine.cooldown(for: mode) {
                return false
            }
            increments += max(Int(abs(delta).rounded()), 0)
            let threshold = MXWheelActionEngine.actionThreshold(sensitivity, mode: mode)
            guard increments >= threshold else { return false }
            increments = 0
            lastEmitAt = now
            return true
        }
    }

    private var thumbRepeater = Repeater()
    private var tickRemainderX = 0.0
    private var tickRemainderY = 0.0
    private var desktopSwipe = DockSwipe.Session()
    private var desktopProgress = 0.0
    private var lastDesktopAt = Date.distantPast

    public init() {
        desktopSwipe.locksFullPages = true
    }

    public func reset() {
        thumbRepeater.reset()
        tickRemainderX = 0
        tickRemainderY = 0
        desktopSwipe.cancel()
        desktopProgress = 0
        AppSwitcher.cancel()
    }

    /// End a live desktop swipe when the thumb wheel stops.
    public func idle(force: Bool = false) {
        guard desktopSwipe.isActive else { return }
        if !force, Date().timeIntervalSince(lastDesktopAt) < Self.desktopIdle { return }
        desktopSwipe.end()
        desktopProgress = 0
    }

    public func process(
        delta: Double,
        mode: MXWheelMode,
        naturalScrolling: Bool,
        scrollSpeed: Double,
        nativeResolution: Int = 0,
        divertedResolution: Int = 0
    ) {
        if mode != .switchDesktops {
            finishDesktopSwipe()
        }
        guard delta != 0 else { return }

        switch mode {
        case .verticalScroll, .horizontalScroll:
            postScroll(
                delta: delta,
                horizontal: mode == .horizontalScroll,
                naturalScrolling: naturalScrolling,
                speed: scrollSpeed,
                nativeResolution: nativeResolution,
                divertedResolution: divertedResolution
            )
            return
        case .switchDesktops:
            applyDesktopSwipe(
                delta: delta,
                speed: scrollSpeed,
                divertedResolution: divertedResolution
            )
            return
        case .none:
            return
        default:
            break
        }

        let now = Date()
        guard thumbRepeater.takeAction(delta: delta, sensitivity: scrollSpeed, mode: mode, now: now) else {
            return
        }
        perform(mode: mode, forward: delta > 0, increase: delta > 0)
    }

    private func postScroll(
        delta: Double,
        horizontal: Bool,
        naturalScrolling: Bool,
        speed: Double,
        nativeResolution: Int,
        divertedResolution: Int
    ) {
        // OpenLogi: one diverted increment is native_res/diverted_res of a
        // native HID tick, then multiplied by sensitivity/14.
        let nativePerIncrement: Double
        if nativeResolution > 0, divertedResolution > 0 {
            nativePerIncrement = Double(nativeResolution) / Double(divertedResolution)
        } else {
            nativePerIncrement = 1
        }
        let direction = naturalScrolling ? 1.0 : -1.0
        let distance = delta * nativePerIncrement * Self.scrollMultiplier(speed) * direction
        if horizontal {
            tickRemainderY = 0
            tickRemainderX += distance
            let ticks = Int32(tickRemainderX.rounded())
            tickRemainderX -= Double(ticks)
            EventPoster.scrollTicks(deltaY: 0, deltaX: ticks)
        } else {
            tickRemainderX = 0
            tickRemainderY += distance
            let ticks = Int32(tickRemainderY.rounded())
            tickRemainderY -= Double(ticks)
            EventPoster.scrollTicks(deltaY: ticks, deltaX: 0)
        }
    }

    private func applyDesktopSwipe(delta: Double, speed: Double, divertedResolution: Int) {
        let span = Self.desktopSpan(divertedResolution: divertedResolution, speed: speed)
        guard span > 0.0001 else { return }
        desktopProgress += delta / span
        lastDesktopAt = Date()
        desktopSwipe.setAbsolute(desktopProgress, axis: .horizontal)
    }

    private func finishDesktopSwipe() {
        guard desktopSwipe.isActive else { return }
        desktopSwipe.end()
        desktopProgress = 0
    }

    /// Diverted increments that equal one desktop. A quarter revolution at 1×.
    private static func desktopSpan(divertedResolution: Int, speed: Double) -> Double {
        let revolution = Double(divertedResolution > 0 ? divertedResolution : defaultDivertedResolution)
        return (revolution / desktopsPerRevolution) / scrollMultiplier(speed)
    }

    private func perform(mode: MXWheelMode, forward: Bool, increase: Bool) {
        switch mode {
        case .switchTabs:
            EventPoster.tab(forward: forward, down: true)
            EventPoster.tab(forward: forward, down: false)
        case .volume:
            SystemVolume.nudge(up: increase)
        case .zoom:
            // Public APIs cannot post a magnification gesture to another app.
            // Command-= and Command-- are the interoperable app-content zoom path.
            pulseKey(increase ? 24 : 27, flags: .maskCommand)
        case .switchDesktops:
            break
        case .switchApplications:
            AppSwitcher.step(back: !forward)
        case .verticalScroll, .horizontalScroll, .none:
            break
        }
    }

    /// OpenLogi `ThumbwheelSensitivity::scroll_multiplier`: value / 14.
    private static func scrollMultiplier(_ speed: Double) -> Double {
        Double(openLogiValue(speed)) / Double(openLogiDefault)
    }

    /// OpenLogi `ThumbwheelSensitivity::action_threshold`: (2×14 − value).max(1).
    /// Navigate Between Tabs uses 1.5× that rate.
    private static func actionThreshold(_ speed: Double, mode: MXWheelMode) -> Int {
        let base = max(1, 2 * openLogiDefault - openLogiValue(speed))
        guard mode == .switchTabs else { return base }
        return max(1, Int((Double(base) / switchTabsRate).rounded()))
    }

    private static func cooldown(for mode: MXWheelMode) -> TimeInterval {
        mode == .switchTabs ? actionCooldown / switchTabsRate : actionCooldown
    }

    private static func openLogiValue(_ speed: Double) -> Int {
        max(1, min(100, Int((min(max(speed, 0), 1) * Double(openLogiDefault * 2)).rounded())))
    }

    private func pulseKey(_ virtualKey: UInt16, flags: CGEventFlags) {
        EventPoster.key(virtualKey, flags: flags, down: true)
        EventPoster.key(virtualKey, flags: flags, down: false)
    }
}
