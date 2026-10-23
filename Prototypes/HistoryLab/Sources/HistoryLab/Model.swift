import SwiftUI

enum Metric: String, CaseIterable, Identifiable, Codable {
    case cpu, gpu, memory, network, disk, temperatures, fans

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .memory: return "Memory pressure"
        case .network: return "Network"
        case .disk: return "Disk activity"
        case .temperatures: return "Temperatures"
        case .fans: return "Fans"
        }
    }

    var systemImage: String {
        switch self {
        case .cpu: return "cpu"
        case .gpu: return "cube.transparent"
        case .memory: return "memorychip"
        case .network: return "network"
        case .disk: return "internaldrive"
        case .temperatures: return "thermometer.medium"
        case .fans: return "fan"
        }
    }

    var unit: ValueUnit {
        switch self {
        case .cpu, .gpu, .memory: return .percent
        case .network, .disk: return .bytesPerSecond
        case .temperatures: return .celsius
        case .fans: return .rpm
        }
    }

    /// Two series that read as a pair (in/out), eligible for mirrored layout.
    var isDual: Bool { self == .network || self == .disk }
}

enum HistoryRange: String, CaseIterable, Identifiable, Codable {
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

    /// 1 s raw samples for 5 min; 20 s and 5 min min/avg/max buckets above.
    var bucketCount: Int {
        switch self {
        case .fiveMinutes: return 300
        case .oneHour: return 180
        case .oneDay: return 288
        }
    }

    var bucket: TimeInterval { duration / Double(bucketCount) }

    var timeLabels: [String] {
        switch self {
        case .fiveMinutes: return ["−5m", "−2.5m", "Now"]
        case .oneHour: return ["−60m", "−30m", "Now"]
        case .oneDay: return ["−24h", "−12h", "Now"]
        }
    }
}

enum ValueUnit {
    case percent, bytesPerSecond, celsius, rpm

    func format(_ v: Double) -> String {
        switch self {
        case .percent: return String(format: "%.0f%%", v * 100)
        case .bytesPerSecond: return Self.bytes(v) + "/s"
        case .celsius: return String(format: "%.0f °C", v)
        case .rpm: return String(format: "%.0f rpm", v)
        }
    }

    func axis(_ v: Double) -> String {
        switch self {
        case .percent: return String(format: "%.0f%%", v * 100)
        case .bytesPerSecond: return Self.bytes(v)
        case .celsius: return String(format: "%.0f°", v)
        case .rpm: return String(format: "%.0f", v)
        }
    }

    static func bytes(_ v: Double) -> String {
        let units = ["B", "KB", "MB", "GB"]
        var value = max(v, 0)
        var index = 0
        while value >= 1000, index < units.count - 1 {
            value /= 1000
            index += 1
        }
        return value >= 100 || index == 0
            ? String(format: "%.0f %@", value, units[index])
            : String(format: "%.1f %@", value, units[index])
    }
}

struct HistoryPoint: Identifiable {
    var date: Date
    var avg: Double
    var min: Double
    var max: Double
    var id: Date { date }
}

struct HistorySeries: Identifiable {
    let id: String
    let name: String
    let color: Color
    var points: [HistoryPoint]

    var latest: HistoryPoint? { points.last }
    /// Network upload stays red in every color palette except mono.
    var isUpload: Bool { id == "up" }
}

struct MetricHistory {
    let metric: Metric
    let range: HistoryRange
    var series: [HistorySeries]

    var unit: ValueUnit { metric.unit }

    func point(_ series: HistorySeries, nearest date: Date?) -> HistoryPoint? {
        guard let date else { return series.latest }
        return series.points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }
}

enum Scenario: String, CaseIterable, Identifiable, Codable {
    case calm, busy, spiky

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}
