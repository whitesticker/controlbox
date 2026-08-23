import Foundation

/// Hold-to-swipe for the **haptic thumb pad** only.
/// Pad press and 12-bit X/Y share mouse report `0x02`.
public struct HoldGesture {
    public static let armDelay: TimeInterval = 0.10

    public private(set) var owner: DeviceButton?
    public var isActive: Bool { owner != nil }

    private var set: GestureSet?
    private var startedAt: Date?
    private var lastX = 0.0
    private var lastY = 0.0
    private var armedX = 0.0
    private var armedY = 0.0
    private var hasSample = false
    private var armed = false
    private var axis: Axis?
    private var space = DockSwipe.Session()
    private var firedDiscrete: ControlAction?
    private var volumeCursor = 0.0
    private var didSwipe = false

    private enum Axis {
        case horizontal
        case vertical
    }

    public init() {}

    public mutating func begin(owner: DeviceButton, set: GestureSet) {
        cancel()
        self.owner = owner
        self.set = set
        startedAt = Date()
    }

    public mutating func move(x: Double, y: Double) -> ControlAction? {
        guard owner != nil, let set else { return nil }
        if hasSample {
            let jump = hypot(x - lastX, y - lastY)
            let previous = hypot(lastX, lastY)
            if jump > 64, previous > 24, hypot(x, y) < previous * 0.45 {
                return nil
            }
        }
        lastX = x
        lastY = y
        hasSample = true

        guard let startedAt, Date().timeIntervalSince(startedAt) >= Self.armDelay else {
            return nil
        }
        if !armed {
            armed = true
            armedX = x
            armedY = y
            volumeCursor = 0
            return nil
        }

        let relX = x - armedX
        let relY = y - armedY
        resolveAxis(x: relX, y: relY)
        guard let axis else { return nil }

        switch axis {
        case .horizontal:
            return applyHorizontal(x: relX, set: set)
        case .vertical:
            return applyVertical(y: relY, set: set)
        }
    }

    @discardableResult
    public mutating func end() -> ControlAction? {
        let tap = !didSwipe && firedDiscrete == nil ? set?.click : nil
        space.end()
        reset()
        if let tap, tap != .none { return tap }
        return nil
    }

    public mutating func cancel() {
        space.cancel()
        reset()
    }

    private mutating func reset() {
        owner = nil
        set = nil
        startedAt = nil
        lastX = 0
        lastY = 0
        armedX = 0
        armedY = 0
        hasSample = false
        armed = false
        axis = nil
        firedDiscrete = nil
        volumeCursor = 0
        didSwipe = false
    }

    private mutating func resolveAxis(x: Double, y: Double) {
        guard axis == nil else { return }
        if abs(y) >= 6, abs(y) >= abs(x) {
            axis = .vertical
            return
        }
        if hypot(x, y) >= 10 {
            axis = .horizontal
        }
    }

    private mutating func applyHorizontal(x: Double, set: GestureSet) -> ControlAction? {
        if set.right.isLiveSpace || set.left.isLiveSpace {
            didSwipe = true
            let flip = set.right == .spaceLeft || set.left == .spaceRight
            space.setAbsolute((flip ? -x : x) / DockSwipe.horizontalSpan, axis: .horizontal)
            return nil
        }
        guard firedDiscrete == nil else { return nil }
        let action: ControlAction
        if x <= -40 {
            action = set.left
        } else if x >= 40 {
            action = set.right
        } else {
            return nil
        }
        guard action.isDiscreteSwipe else { return nil }
        firedDiscrete = action
        didSwipe = true
        return action
    }

    private mutating func applyVertical(y: Double, set: GestureSet) -> ControlAction? {
        if set.down == .appExpose, y >= 40, firedDiscrete == nil {
            space.cancel()
            firedDiscrete = .appExpose
            didSwipe = true
            return .appExpose
        }
        if set.up.isLiveMissionSwipe, -y > 0.002 {
            didSwipe = true
            space.setAbsolute(-y / DockSwipe.liveVerticalSpan, axis: .vertical)
            return nil
        }
        if set.down.isLiveMissionSwipe, set.down != .appExpose {
            didSwipe = true
            space.setAbsolute(-y / DockSwipe.liveVerticalSpan, axis: .vertical)
            return nil
        }
        applyVolume(y: y, set: set)
        return nil
    }

    private mutating func applyVolume(y: Double, set: GestureSet) {
        guard set.up.isLiveVolume || set.down.isLiveVolume else { return }
        let target = (-y / 36.0).rounded(.towardZero)
        guard target != volumeCursor else { return }
        let step = target > volumeCursor ? 0.04 : -0.04
        let count = Int(abs(target - volumeCursor))
        for _ in 0..<count {
            if let level = SystemVolume.adjust(by: step) {
                VolumeHUD.show(level: level)
            }
        }
        volumeCursor = target
        didSwipe = true
    }
}
