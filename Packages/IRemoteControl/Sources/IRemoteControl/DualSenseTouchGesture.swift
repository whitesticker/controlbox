import Foundation

/// Turns DualSense touchpad contacts into the same hold-to-swipe XY that
/// `HoldGesture` already uses for the MX haptic / gesture button.
///
/// 1-finger and 2-finger are separate owners. Finger count locks after the
/// 100ms arm window so a second finger can still promote the owner.
public struct DualSenseTouchGesture {
    public static let pixelsPerUnit = 640.0

    public private(set) var owner: DeviceButton?
    public private(set) var active = false
    public private(set) var x = 0.0
    public private(set) var y = 0.0

    private var originX = 0.0
    private var originY = 0.0
    private var startedAt: Date?
    private var locked = false

    public init() {}

    public mutating func reset() {
        owner = nil
        active = false
        x = 0
        y = 0
        originX = 0
        originY = 0
        startedAt = nil
        locked = false
    }

    public mutating func update(touch1: AnalogSample, touch2: AnalogSample, scale: Double) {
        let fingers = Self.points(touch1: touch1, touch2: touch2)
        guard !fingers.isEmpty else {
            reset()
            return
        }

        let proposed: DeviceButton = fingers.count >= 2 ? .touchpadTwoFinger : .touchpadOneFinger
        let point = Self.centroid(fingers)
        let now = Date()

        if owner == nil {
            owner = proposed
            originX = point.x
            originY = point.y
            startedAt = now
            locked = false
            active = true
            x = 0
            y = 0
            return
        }

        if !locked {
            if let startedAt, now.timeIntervalSince(startedAt) >= HoldGesture.armDelay {
                locked = true
            } else if owner == .touchpadOneFinger, proposed == .touchpadTwoFinger {
                owner = proposed
                originX = point.x
                originY = point.y
                x = 0
                y = 0
                return
            }
        }

        active = true
        x = (point.x - originX) * scale
        y = -(point.y - originY) * scale
    }

    private static func points(touch1: AnalogSample, touch2: AnalogSample) -> [(x: Double, y: Double)] {
        var points: [(x: Double, y: Double)] = []
        if touch1.active {
            points.append((Double(touch1.x), Double(touch1.y)))
        }
        if touch2.active {
            points.append((Double(touch2.x), Double(touch2.y)))
        }
        return points
    }

    private static func centroid(_ points: [(x: Double, y: Double)]) -> (x: Double, y: Double) {
        let n = Double(points.count)
        return (
            points.reduce(0) { $0 + $1.x } / n,
            points.reduce(0) { $0 + $1.y } / n
        )
    }
}
