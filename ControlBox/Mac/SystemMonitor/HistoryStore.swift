import SwiftUI

// MARK: - History model

/// What one history panel charts. Each metric is one or more series. The
/// Sensors submenu charts one of `sensorCases` at a time, picked by hover.
enum HistoryMetric: Hashable, CaseIterable {
    case cpu, gpu, memory, network, disk, fans, power
    /// The hottest sensor in one group.
    case sensorGroup(SensorGroup)

    static let systemCases: [HistoryMetric] = [.cpu, .gpu, .memory, .network, .disk]
    static let sensorCases: [HistoryMetric] = [.power, .fans] + SensorGroup.allCases.map { .sensorGroup($0) }
    static var allCases: [HistoryMetric] { systemCases + sensorCases }

    var title: String {
        switch self {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .memory: return "Memory"
        case .network: return "Network"
        case .disk: return "Disk"
        case .fans: return "Fans"
        case .power: return "Power"
        case .sensorGroup(let group): return group.title
        }
    }

    var systemImage: String {
        switch self {
        case .cpu: return "cpu"
        case .gpu: return "cube.transparent"
        case .memory: return "memorychip"
        case .network: return "network"
        case .disk: return "internaldrive"
        case .sensorGroup: return "thermometer.medium"
        case .fans: return "fan"
        case .power: return "bolt"
        }
    }

    var unit: HistoryUnit {
        switch self {
        case .cpu, .gpu, .memory: return .percent
        case .network, .disk: return .bytesPerSecond
        case .sensorGroup: return .celsius
        case .fans: return .rpm
        case .power: return .watts
        }
    }

    /// In/out pair drawn mirrored around zero (download up, upload down).
    var isDual: Bool { self == .network || self == .disk }
}

enum HistoryRange: String, CaseIterable, Identifiable {
    case fiveMinutes = "5m"
    case oneHour = "1h"
    case oneDay = "24h"

    var id: String { rawValue }
    var title: String { rawValue }

    var duration: TimeInterval {
        switch self {
        case .fiveMinutes: return 5 * 60
        case .oneHour: return 60 * 60
        case .oneDay: return 24 * 60 * 60
        }
    }

    /// Stored resolution: 1 s samples, then 20 s and 5 min min/avg/max buckets.
    var bucket: TimeInterval {
        switch self {
        case .fiveMinutes: return 1
        case .oneHour: return 20
        case .oneDay: return 300
        }
    }

    var timeLabels: [String] {
        switch self {
        case .fiveMinutes: return ["−5m", "−2.5m", "Now"]
        case .oneHour: return ["−60m", "−30m", "Now"]
        case .oneDay: return ["−24h", "−12h", "Now"]
        }
    }

    /// Bar lengths offered in settings: multiples of `bucket`.
    var barChoices: [TimeInterval] {
        switch self {
        case .fiveMinutes: return [5, 10, 15, 30, 60]
        case .oneHour: return [60, 120, 180, 300, 600]
        case .oneDay: return [900, 1800, 3600, 7200]
        }
    }

    var defaultBarSeconds: TimeInterval {
        switch self {
        case .fiveMinutes: return 10
        case .oneHour: return 120
        case .oneDay: return 3600
        }
    }
}

enum HistoryUnit {
    case percent, bytesPerSecond, celsius, rpm, watts

    func format(_ v: Double) -> String {
        switch self {
        case .percent: return Fmt.percent(v)
        case .bytesPerSecond: return Fmt.speed(v)
        case .celsius: return Fmt.temp(v)
        case .rpm: return Fmt.rpm(v)
        case .watts: return Fmt.watts(v)
        }
    }

    func axis(_ v: Double) -> String {
        switch self {
        case .percent: return String(format: "%.0f%%", v * 100)
        case .bytesPerSecond: return Fmt.bytes(v)
        case .celsius: return String(format: "%.0f°", v)
        case .rpm: return String(format: "%.0f", v)
        case .watts: return String(format: "%.0f W", v)
        }
    }
}

struct HistoryPoint: Identifiable {
    var date: Date
    var avg: Double
    var min: Double
    var max: Double
    /// First and last sample in the bucket (candle body).
    var open: Double
    var close: Double
    var id: Date { date }
}

struct HistorySeries: Identifiable {
    let id: String
    let name: String
    let color: Color
    var points: [HistoryPoint]

    var latest: HistoryPoint? { points.last }
}

struct MetricHistory {
    let metric: HistoryMetric
    let range: HistoryRange
    var series: [HistorySeries]

    var unit: HistoryUnit { metric.unit }

    func point(_ series: HistorySeries, nearest date: Date?) -> HistoryPoint? {
        guard let date else { return series.latest }
        return series.points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }
}

// MARK: - Store

/// Min/avg/max history at the three `HistoryRange` resolutions, fed from the
/// System Monitor poll queue and read by the history submenus on main.
/// In memory only (well under 1 MB with every sensor group), so it starts
/// empty at launch; the 24 h range fills over a day.
final class HistoryStore {
    static let shared = HistoryStore()

    private struct Bucket {
        var end: TimeInterval
        var sum: Double
        var count: Int
        var min: Double
        var max: Double
        var first: Double
        var latest: Double
        var last: Date

        init(end: TimeInterval, value: Double, at date: Date) {
            self.end = end
            sum = value
            count = 1
            min = value
            max = value
            first = value
            latest = value
            last = date
        }

        mutating func add(_ value: Double, at date: Date) {
            sum += value
            count += 1
            min = Swift.min(min, value)
            max = Swift.max(max, value)
            latest = value
            last = date
        }

        func point(at date: Date) -> HistoryPoint {
            HistoryPoint(date: date, avg: sum / Double(count), min: min, max: max, open: first, close: latest)
        }
    }

    private struct Tier {
        let range: HistoryRange
        var points: [HistoryPoint] = []
        var open: Bucket?

        mutating func add(_ value: Double, at date: Date) {
            let end = (floor(date.timeIntervalSince1970 / range.bucket) + 1) * range.bucket
            if open?.end == end {
                open?.add(value, at: date)
                return
            }
            if let open {
                points.append(open.point(at: Date(timeIntervalSince1970: open.end)))
            }
            open = Bucket(end: end, value: value, at: date)
            let cutoff = date.addingTimeInterval(-range.duration - range.bucket)
            let stale = points.firstIndex { $0.date >= cutoff } ?? points.count
            if stale > 0 { points.removeFirst(stale) }
        }

        /// Closed buckets plus the one still filling, stamped at its newest sample.
        var snapshot: [HistoryPoint] {
            guard let open else { return points }
            return points + [open.point(at: open.last)]
        }
    }

    private struct Track {
        var name: String
        var tiers = HistoryRange.allCases.map { Tier(range: $0) }
    }

    private let lock = NSLock()
    private var tracks: [String: Track] = [:]

    private init() {}

    /// Poll queue.
    func record(_ id: String, name: String, value: Double, at date: Date) {
        lock.lock()
        defer { lock.unlock() }
        var track = tracks[id] ?? Track(name: name)
        track.name = name
        for index in track.tiers.indices {
            track.tiers[index].add(value, at: date)
        }
        tracks[id] = track
    }

    func history(_ metric: HistoryMetric, range: HistoryRange) -> MetricHistory {
        lock.lock()
        defer { lock.unlock() }
        let tier = HistoryRange.allCases.firstIndex(of: range) ?? 0
        let series = seriesIDs(metric).compactMap { id -> HistorySeries? in
            guard let track = tracks[id] else { return nil }
            return HistorySeries(id: id, name: track.name, color: Self.color(id), points: track.tiers[tier].snapshot)
        }
        return MetricHistory(metric: metric, range: range, series: series)
    }

    /// The newest `count` 1 s samples per series, for the parent graph row.
    func recent(_ metric: HistoryMetric, count: Int) -> [HistorySeries] {
        lock.lock()
        defer { lock.unlock() }
        return seriesIDs(metric).compactMap { id in
            guard let track = tracks[id] else { return nil }
            return HistorySeries(
                id: id,
                name: track.name,
                color: Self.color(id),
                points: Array(track.tiers[0].snapshot.suffix(count))
            )
        }
    }

    func hasData(_ metric: HistoryMetric) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return seriesIDs(metric).contains { tracks[$0] != nil }
    }

    /// Caller holds `lock`.
    private func seriesIDs(_ metric: HistoryMetric) -> [String] {
        switch metric {
        case .cpu: return ["cpu"]
        case .gpu: return ["gpu"]
        case .memory: return ["memory"]
        case .network: return ["net.down", "net.up"]
        case .disk: return ["disk.read", "disk.write"]
        case .sensorGroup(let group): return [Self.temperatureID(group)]
        case .power: return ["power.system"]
        case .fans:
            return tracks.keys.filter { $0.hasPrefix("fan.") }
                .sorted { (Int($0.dropFirst(4)) ?? 0) < (Int($1.dropFirst(4)) ?? 0) }
        }
    }

    static func temperatureID(_ group: SensorGroup) -> String {
        "temp.\(group)"
    }

    private static func color(_ id: String) -> Color {
        switch id {
        case "cpu": return DashColors.cpuLine
        case "gpu": return DashColors.gpuLine
        case "memory": return DashColors.accent
        case "net.down": return DashColors.download
        case "net.up": return DashColors.upload
        case "disk.read": return DashColors.diskRead
        case "disk.write": return DashColors.diskWrite
        case temperatureID(.cpu): return .orange
        case temperatureID(.gpu): return .purple
        case temperatureID(.soc): return .red
        case temperatureID(.memoryStorage): return .green
        case temperatureID(.power): return .yellow
        case temperatureID(.enclosure): return .teal
        case temperatureID(.batteryWireless): return .indigo
        case "power.system": return .yellow
        case "fan.1": return .indigo
        case "fan.2": return .mint
        default: return .cyan
        }
    }
}
