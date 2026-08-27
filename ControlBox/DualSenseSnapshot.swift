import Foundation

struct Vec3: Equatable, Sendable {
    var x: Double
    var y: Double
    var z: Double

    static let zero = Vec3(x: 0, y: 0, z: 0)

    var magnitude: Double {
        sqrt(x * x + y * y + z * z)
    }
}

struct TouchFinger: Equatable, Sendable {
    var x: Float
    var y: Float
    var active: Bool
}

struct InputLogEvent: Identifiable, Equatable, Sendable {
    let id: UUID
    let date: Date
    let label: String
    let pressed: Bool
}

struct DualSenseSnapshot: Equatable, Sendable {
    var connected = false
    var name = "No controller"
    var product = ""
    var isDualSense = false
    var playerIndex = -1

    var cross = false
    var circle = false
    var square = false
    var triangle = false
    var dpadUp = false
    var dpadDown = false
    var dpadLeft = false
    var dpadRight = false
    var l1 = false
    var r1 = false
    var l3 = false
    var r3 = false
    var create = false
    var options = false
    var ps = false
    var touchpadClick = false

    var l2: Float = 0
    var r2: Float = 0
    var leftStick = SIMD2<Float>(repeating: 0)
    var rightStick = SIMD2<Float>(repeating: 0)

    var touch1 = TouchFinger(x: 0, y: 0, active: false)
    var touch2 = TouchFinger(x: 0, y: 0, active: false)

    var gravity = Vec3.zero
    var userAcceleration = Vec3.zero
    var rotationRate = Vec3.zero
    var hasMotion = false

    var batteryPercent: Int?
    var batteryCharging = false
    var batteryFull = false
    var batteryAvailable = false
    var batteryStateDescription = "Unknown"

    var events: [InputLogEvent] = []

    func hadButtonDown(from previous: DualSenseSnapshot) -> Bool {
        func rose(_ now: Bool, _ was: Bool) -> Bool { now && !was }
        if rose(cross, previous.cross) { return true }
        if rose(circle, previous.circle) { return true }
        if rose(square, previous.square) { return true }
        if rose(triangle, previous.triangle) { return true }
        if rose(dpadUp, previous.dpadUp) { return true }
        if rose(dpadDown, previous.dpadDown) { return true }
        if rose(dpadLeft, previous.dpadLeft) { return true }
        if rose(dpadRight, previous.dpadRight) { return true }
        if rose(l1, previous.l1) { return true }
        if rose(r1, previous.r1) { return true }
        if rose(l3, previous.l3) { return true }
        if rose(r3, previous.r3) { return true }
        if rose(create, previous.create) { return true }
        if rose(options, previous.options) { return true }
        if rose(ps, previous.ps) { return true }
        if rose(touchpadClick, previous.touchpadClick) { return true }
        if previous.l2 <= 0.2 && l2 > 0.2 { return true }
        if previous.r2 <= 0.2 && r2 > 0.2 { return true }
        return false
    }

    func matchesIgnoringMotion(_ other: DualSenseSnapshot) -> Bool {
        var lhs = self
        var rhs = other
        lhs.gravity = .zero
        lhs.userAcceleration = .zero
        lhs.rotationRate = .zero
        rhs.gravity = .zero
        rhs.userAcceleration = .zero
        rhs.rotationRate = .zero
        return lhs == rhs
    }
}
