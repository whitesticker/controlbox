import Foundation

struct AppleTVTouchSnapshot: Equatable, Sendable {
    var active = false
    var x: Float = 0.5
    var y: Float = 0.5
    var size: Float = 0
    var familyID = 0
    var available = false
    var wheelActive = false
    var wheelDegrees: Double = 0
    var wheelAccumulated: Double = 0
}

final class AppleTVTouchReader {
    private let lock = NSLock()
    private var snapshotValue = AppleTVTouchSnapshot()
    private var lastAngle: Double?
    private var wheelLatched = false
    private var gestureRotation: Double = 0
    private var started = false

    var snapshot: AppleTVTouchSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return snapshotValue
    }

    func start() {
        guard !started else { return }
        started = true
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        AppleTVMultitouchStart({ x, y, active, size, familyID, context in
            guard let context else { return }
            Unmanaged<AppleTVTouchReader>.fromOpaque(context).takeUnretainedValue()
                .handle(x: x, y: y, active: active, size: size, familyID: familyID)
        }, pointer)
        lock.lock()
        snapshotValue.available = AppleTVMultitouchActiveFamilyID() != 0
        snapshotValue.familyID = Int(AppleTVMultitouchActiveFamilyID())
        lock.unlock()
    }

    func stop() {
        AppleTVMultitouchStop()
        started = false
        lock.lock()
        snapshotValue = AppleTVTouchSnapshot()
        lastAngle = nil
        wheelLatched = false
        gestureRotation = 0
        lock.unlock()
    }

    private func handle(x: Float, y: Float, active: Bool, size: Float, familyID: Int32) {
        let clampedX = min(max(x, 0), 1)
        let clampedY = min(max(y, 0), 1)
        let dx = Double(clampedX) - 0.5
        let dy = Double(clampedY) - 0.5
        let radius = sqrt(dx * dx + dy * dy)
        let enterRing = radius > 0.36

        lock.lock()
        defer { lock.unlock() }
        snapshotValue.available = true
        snapshotValue.active = active
        snapshotValue.x = clampedX
        snapshotValue.y = clampedY
        snapshotValue.size = size
        snapshotValue.familyID = Int(familyID)

        if !active {
            lastAngle = nil
            wheelLatched = false
            gestureRotation = 0
            snapshotValue.wheelActive = false
            snapshotValue.wheelDegrees = 0
            return
        }

        if !wheelLatched && !enterRing {
            lastAngle = nil
            snapshotValue.wheelActive = false
            snapshotValue.wheelDegrees = 0
            return
        }

        let angle = atan2(dy, dx)
        if let lastAngle {
            var delta = angle - lastAngle
            while delta > .pi { delta -= 2 * .pi }
            while delta < -.pi { delta += 2 * .pi }
            let degrees = delta * 180 / .pi
            snapshotValue.wheelDegrees = degrees
            snapshotValue.wheelAccumulated += degrees
            gestureRotation += abs(degrees)
            if gestureRotation > 8 {
                wheelLatched = true
            }
        }
        lastAngle = angle
        snapshotValue.wheelActive = true
    }
}
