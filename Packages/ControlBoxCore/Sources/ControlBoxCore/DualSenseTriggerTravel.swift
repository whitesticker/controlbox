import Foundation

/// DualSense L2 / R2 analog travel for tab switching.
/// Mid pull = one tab. Full hold = keep switching at `interval`.
public struct DualSenseTriggerTravel {
    public static let rest: Float = 0.12
    public static let single: Float = 0.38
    public static let hold: Float = 0.82

    private enum Phase {
        case idle
        case singleFired
        case repeating
    }

    private var phase = Phase.idle
    private var nextRepeat = Date.distantPast

    public init() {}

    public mutating func reset() {
        phase = .idle
        nextRepeat = .distantPast
    }

    /// How many tab steps to fire this sample (0 or 1).
    public mutating func steps(value: Float, interval: TimeInterval) -> Int {
        if value < Self.rest {
            reset()
            return 0
        }
        if value < Self.single {
            if phase != .idle {
                reset()
            }
            return 0
        }

        var fire = 0
        if phase == .idle {
            phase = .singleFired
            fire = 1
        }
        if value >= Self.hold {
            let now = Date()
            if phase == .singleFired {
                phase = .repeating
                nextRepeat = now.addingTimeInterval(interval)
            } else if now >= nextRepeat {
                fire = 1
                nextRepeat = now.addingTimeInterval(interval)
            }
        }
        return fire
    }
}
