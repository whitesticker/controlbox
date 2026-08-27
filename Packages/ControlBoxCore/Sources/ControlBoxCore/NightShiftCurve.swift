import Foundation

/// One knot on the 24-hour Night Shift curve. `minutes` is local time from midnight.
public struct NightShiftPoint: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var minutes: Double
    public var warmth: Double

    public init(id: String = UUID().uuidString, minutes: Double, warmth: Double) {
        self.id = id
        self.minutes = NightShiftCurve.wrap(minutes)
        self.warmth = min(max(warmth, 0), 1)
    }
}

/// Periodic yellowness over a day. X is time, Y is Night Shift strength.
public struct NightShiftCurve: Codable, Equatable, Sendable {
    public static let minPoints = 3
    public static let maxPoints = 16
    public static let minutesPerDay = 1440.0

    public var points: [NightShiftPoint]

    public static var factory: NightShiftCurve {
        NightShiftCurve(points: [
            NightShiftPoint(minutes: 485.41, warmth: 1.0000),
            NightShiftPoint(minutes: 652.55, warmth: 0.7508),
            NightShiftPoint(minutes: 810.07, warmth: 0.0881),
            NightShiftPoint(minutes: 1012.60, warmth: 0.0989),
            NightShiftPoint(minutes: 1128.29, warmth: 0.7347),
            NightShiftPoint(minutes: 1320, warmth: 1.0000),
        ])
    }

    /// First shipping default (cool mornings, milder evenings).
    public static var shippingV1: NightShiftCurve {
        NightShiftCurve(points: [
            NightShiftPoint(minutes: 7 * 60, warmth: 0.00),
            NightShiftPoint(minutes: 17 * 60 + 30, warmth: 0.08),
            NightShiftPoint(minutes: 20 * 60, warmth: 0.55),
            NightShiftPoint(minutes: 22 * 60 + 30, warmth: 0.95),
            NightShiftPoint(minutes: 4 * 60, warmth: 0.90),
            NightShiftPoint(minutes: 6 * 60, warmth: 0.22),
        ])
    }

    /// 7 p.m. to 10 a.m. night plateau.
    public static var shippingV2: NightShiftCurve {
        NightShiftCurve(points: [
            NightShiftPoint(minutes: 10 * 60, warmth: 0.00),
            NightShiftPoint(minutes: 18 * 60 + 30, warmth: 0.12),
            NightShiftPoint(minutes: 19 * 60, warmth: 0.92),
            NightShiftPoint(minutes: 22 * 60, warmth: 1.00),
            NightShiftPoint(minutes: 6 * 60, warmth: 1.00),
            NightShiftPoint(minutes: 9 * 60 + 30, warmth: 0.92),
        ])
    }

    public func matchesShape(of other: NightShiftCurve) -> Bool {
        let lhs = sorted
        let rhs = other.sorted
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { a, b in
            abs(a.minutes - b.minutes) < 1 && abs(a.warmth - b.warmth) < 0.02
        }
    }

    public init(points: [NightShiftPoint]) {
        self.points = Self.normalized(points)
    }

    public var sorted: [NightShiftPoint] {
        points.sorted { $0.minutes < $1.minutes }
    }

    public func warmth(atMinutes minutes: Double) -> Double {
        let knots = sorted
        guard knots.count >= 2 else {
            return knots.first?.warmth ?? 0
        }
        let t = Self.wrap(minutes)
        let n = knots.count
        func sample(_ i: Int) -> (minutes: Double, warmth: Double) {
            let cycle = Int(floor(Double(i) / Double(n)))
            let wrapped = ((i % n) + n) % n
            let point = knots[wrapped]
            return (point.minutes + Double(cycle) * Self.minutesPerDay, point.warmth)
        }
        var index = -1
        for candidate in -1..<n {
            if sample(candidate).minutes <= t, t < sample(candidate + 1).minutes {
                index = candidate
                break
            }
        }
        let prev = sample(index - 1)
        let a = sample(index)
        let b = sample(index + 1)
        let next = sample(index + 2)
        return Self.hermite(
            t: t,
            t0: a.minutes,
            w0: a.warmth,
            t1: b.minutes,
            w1: b.warmth,
            tPrev: prev.minutes,
            wPrev: prev.warmth,
            tNext: next.minutes,
            wNext: next.warmth
        )
    }

    public func warmth(at date: Date, calendar: Calendar = .current) -> Double {
        warmth(atMinutes: Self.minutes(from: date, calendar: calendar))
    }

    public mutating func move(id: String, minutes: Double, warmth: Double) {
        guard let index = points.firstIndex(where: { $0.id == id }) else { return }
        points[index].minutes = Self.wrap(minutes)
        points[index].warmth = min(max(warmth, 0), 1)
        points = Self.normalized(points)
    }

    public mutating func add(minutes: Double, warmth: Double) -> String? {
        guard points.count < Self.maxPoints else { return nil }
        let wrapped = Self.wrap(minutes)
        if sorted.contains(where: { abs(Self.shortestDelta($0.minutes, wrapped)) < 12 }) {
            return nil
        }
        let point = NightShiftPoint(minutes: wrapped, warmth: warmth)
        points.append(point)
        points = Self.normalized(points)
        return point.id
    }

    @discardableResult
    public mutating func remove(id: String) -> Bool {
        guard points.count > Self.minPoints else { return false }
        let next = points.filter { $0.id != id }
        guard next.count >= Self.minPoints else { return false }
        points = Self.normalized(next)
        return true
    }

    public static func wrap(_ minutes: Double) -> Double {
        var value = minutes.truncatingRemainder(dividingBy: minutesPerDay)
        if value < 0 { value += minutesPerDay }
        if value >= minutesPerDay { value = 0 }
        return value
    }

    public static func minutes(from date: Date, calendar: Calendar = .current) -> Double {
        let parts = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        let seconds = Double(parts.second ?? 0) + Double(parts.nanosecond ?? 0) / 1_000_000_000
        return Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0)) + seconds / 60
    }

    public static func timeLabel(minutes: Double, calendar: Calendar = .current) -> String {
        let wrapped = Int(wrap(minutes).rounded()) % Int(minutesPerDay)
        var parts = calendar.dateComponents([.year, .month, .day], from: Date())
        parts.hour = wrapped / 60
        parts.minute = wrapped % 60
        parts.second = 0
        let date = calendar.date(from: parts) ?? Date()
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    public static func kelvin(warmth: Double, range: NightShift.CCTRange = .fallback) -> Int {
        let t = min(max(warmth, 0), 1)
        return Int((range.maxKelvin - t * (range.maxKelvin - range.minKelvin)).rounded())
    }

    static func shortestDelta(_ a: Double, _ b: Double) -> Double {
        var delta = b - a
        if delta > minutesPerDay / 2 { delta -= minutesPerDay }
        if delta < -minutesPerDay / 2 { delta += minutesPerDay }
        return delta
    }

    private static func normalized(_ points: [NightShiftPoint]) -> [NightShiftPoint] {
        var seen = Set<String>()
        var next: [NightShiftPoint] = []
        for point in points {
            var copy = point
            if copy.id.isEmpty || seen.contains(copy.id) {
                copy.id = UUID().uuidString
            }
            seen.insert(copy.id)
            copy.minutes = wrap(copy.minutes)
            copy.warmth = min(max(copy.warmth, 0), 1)
            next.append(copy)
        }
        if next.count < minPoints {
            return factory.points
        }
        if next.count > maxPoints {
            next = Array(next.sorted { $0.minutes < $1.minutes }.prefix(maxPoints))
        }
        return next
    }

    private static func hermite(
        t: Double,
        t0: Double,
        w0: Double,
        t1: Double,
        w1: Double,
        tPrev: Double,
        wPrev: Double,
        tNext: Double,
        wNext: Double
    ) -> Double {
        let dt = t1 - t0
        guard dt > 0.001 else { return min(max(w0, 0), 1) }
        let u = min(max((t - t0) / dt, 0), 1)
        let m0 = ((w1 - wPrev) / max(t1 - tPrev, 0.001)) * dt * 0.85
        let m1 = ((wNext - w0) / max(tNext - t0, 0.001)) * dt * 0.85
        let u2 = u * u
        let u3 = u2 * u
        let y = (2 * u3 - 3 * u2 + 1) * w0
            + (u3 - 2 * u2 + u) * m0
            + (-2 * u3 + 3 * u2) * w1
            + (u3 - u2) * m1
        return min(max(y, 0), 1)
    }
}
