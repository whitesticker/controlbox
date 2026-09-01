import Foundation

public enum AppearanceScheduleMode: String, Codable, Sendable, CaseIterable, Hashable {
    case sunset
    case custom
}

/// Light/Dark window while Night Shift take-over is on. Apple Auto follows the
/// 00:00–23:59 warmth schedule, so we drive appearance ourselves.
public struct AppearanceSchedule: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var mode: AppearanceScheduleMode
    public var darkFromMinutes: Double
    public var darkToMinutes: Double

    public static let factory = AppearanceSchedule(
        enabled: true,
        mode: .sunset,
        darkFromMinutes: 19 * 60,
        darkToMinutes: 7 * 60
    )

    public init(
        enabled: Bool,
        mode: AppearanceScheduleMode,
        darkFromMinutes: Double,
        darkToMinutes: Double
    ) {
        self.enabled = enabled
        self.mode = mode
        self.darkFromMinutes = NightShiftCurve.wrap(darkFromMinutes)
        self.darkToMinutes = NightShiftCurve.wrap(darkToMinutes)
    }

    public func wantsDark(at date: Date, solar: (sunrise: Double, sunset: Double)) -> Bool {
        let from: Double
        let to: Double
        switch mode {
        case .sunset:
            from = solar.sunset
            to = solar.sunrise
        case .custom:
            from = darkFromMinutes
            to = darkToMinutes
        }
        return Self.contains(NightShiftCurve.minutes(from: date), from: from, to: to)
    }

    public static func contains(_ minutes: Double, from: Double, to: Double) -> Bool {
        let t = NightShiftCurve.wrap(minutes)
        let start = NightShiftCurve.wrap(from)
        let end = NightShiftCurve.wrap(to)
        if abs(start - end) < 0.5 {
            return true
        }
        if start < end {
            return t >= start && t < end
        }
        return t >= start || t < end
    }
}

/// Official sunrise / sunset in local minutes. No Core Location — timezone
/// coordinates, then longitude from the GMT offset.
public enum SolarTimes {
    public static func today(date: Date = Date(), calendar: Calendar = .current) -> (sunrise: Double, sunset: Double) {
        let coords = coordinates(for: calendar.timeZone)
        return minutes(
            on: date,
            latitude: coords.latitude,
            longitude: coords.longitude,
            calendar: calendar
        )
    }

    public static func coordinates(for timeZone: TimeZone) -> (latitude: Double, longitude: Double) {
        if let known = knownCoordinates[timeZone.identifier] {
            return known
        }
        let longitude = Double(timeZone.secondsFromGMT()) / 3600 * 15
        return (40, min(max(longitude, -180), 180))
    }

    public static func minutes(
        on date: Date,
        latitude: Double,
        longitude: Double,
        calendar: Calendar = .current
    ) -> (sunrise: Double, sunset: Double) {
        let day = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        let offsetHours = Double(calendar.timeZone.secondsFromGMT(for: date)) / 3600
        let sunrise = eventMinutes(
            dayOfYear: day,
            latitude: latitude,
            longitude: longitude,
            sunrise: true,
            offsetHours: offsetHours
        )
        let sunset = eventMinutes(
            dayOfYear: day,
            latitude: latitude,
            longitude: longitude,
            sunrise: false,
            offsetHours: offsetHours
        )
        return (
            sunrise ?? 7 * 60,
            sunset ?? 19 * 60
        )
    }

    private static let zenith = 90.833

    private static func eventMinutes(
        dayOfYear n: Int,
        latitude: Double,
        longitude: Double,
        sunrise: Bool,
        offsetHours: Double
    ) -> Double? {
        let lngHour = longitude / 15
        let t = Double(n) + ((sunrise ? 6 : 18) - lngHour) / 24
        let m = (0.9856 * t) - 3.289
        var l = m + (1.916 * sinDeg(m)) + (0.020 * sinDeg(2 * m)) + 282.634
        l = normalizeDegrees(l)
        var ra = atanDeg(0.91764 * tanDeg(l))
        ra = normalizeDegrees(ra)
        let lQuad = floor(l / 90) * 90
        let raQuad = floor(ra / 90) * 90
        ra = (ra + (lQuad - raQuad)) / 15
        let sinDec = 0.39782 * sinDeg(l)
        let cosDec = cos(asin(sinDec))
        let cosH = (cosDeg(zenith) - (sinDec * sinDeg(latitude))) / (cosDec * cosDeg(latitude))
        guard cosH >= -1, cosH <= 1 else { return nil }
        var h = acosDeg(cosH)
        if sunrise { h = 360 - h }
        h /= 15
        let time = h + ra - (0.06571 * t) - 6.622
        var ut = time - lngHour
        ut = normalizeHours(ut)
        var local = ut + offsetHours
        local = normalizeHours(local)
        return local * 60
    }

    private static func sinDeg(_ deg: Double) -> Double { sin(deg * .pi / 180) }
    private static func cosDeg(_ deg: Double) -> Double { cos(deg * .pi / 180) }
    private static func tanDeg(_ deg: Double) -> Double { tan(deg * .pi / 180) }
    private static func atanDeg(_ x: Double) -> Double { atan(x) * 180 / .pi }
    private static func acosDeg(_ x: Double) -> Double { acos(min(max(x, -1), 1)) * 180 / .pi }

    private static func normalizeDegrees(_ value: Double) -> Double {
        var next = value.truncatingRemainder(dividingBy: 360)
        if next < 0 { next += 360 }
        return next
    }

    private static func normalizeHours(_ value: Double) -> Double {
        var next = value.truncatingRemainder(dividingBy: 24)
        if next < 0 { next += 24 }
        return next
    }

    private static let knownCoordinates: [String: (latitude: Double, longitude: Double)] = [
        "America/Los_Angeles": (37.77, -122.42),
        "America/Vancouver": (49.28, -123.12),
        "America/Denver": (39.74, -104.99),
        "America/Phoenix": (33.45, -112.07),
        "America/Chicago": (41.88, -87.63),
        "America/New_York": (40.71, -74.01),
        "America/Toronto": (43.65, -79.38),
        "America/Sao_Paulo": (-23.55, -46.63),
        "Europe/London": (51.51, -0.13),
        "Europe/Paris": (48.86, 2.35),
        "Europe/Berlin": (52.52, 13.40),
        "Europe/Amsterdam": (52.37, 4.90),
        "Europe/Stockholm": (59.33, 18.07),
        "Asia/Tokyo": (35.68, 139.69),
        "Asia/Shanghai": (31.23, 121.47),
        "Asia/Hong_Kong": (22.32, 114.17),
        "Asia/Singapore": (1.35, 103.82),
        "Asia/Seoul": (37.57, 126.98),
        "Australia/Sydney": (-33.87, 151.21),
        "Pacific/Auckland": (-36.85, 174.76),
    ]
}
