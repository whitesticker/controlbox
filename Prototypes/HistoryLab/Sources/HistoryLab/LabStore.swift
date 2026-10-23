import AppKit
import SwiftUI

enum LabAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Shared by the window canvas and the real menu bar preview, so both always
/// draw the same design and the same data.
final class LabStore: ObservableObject {
    @Published var design: HistoryDesign {
        didSet { saveDesign() }
    }
    @Published var metric = Metric.memory { didSet { regenerate() } }
    @Published var range: HistoryRange {
        didSet {
            UserDefaults.standard.set(range.rawValue, forKey: Self.rangeKey)
            regenerate()
        }
    }
    @Published var scenario = Scenario.calm { didSet { regenerate() } }
    @Published var seed: UInt64 = 1 { didSet { regenerate() } }
    @Published var live = true
    @Published var appearance = LabAppearance.system
    @Published private(set) var history: MetricHistory

    private static let designKey = "historyLab.design"
    private static let rangeKey = "historyLab.range"
    private var stream: MockStream
    private var timer: Timer?
    private var sinceLastBucket: TimeInterval = 0

    init() {
        design = Self.loadDesign()
        let savedRange = UserDefaults.standard.string(forKey: Self.rangeKey).flatMap(HistoryRange.init(rawValue:))
        let initialRange = savedRange ?? .oneHour
        range = initialRange
        (history, stream) = Self.generate(metric: .memory, range: initialRange, scenario: .calm, seed: 1)
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func regenerate() {
        (history, stream) = Self.generate(metric: metric, range: range, scenario: scenario, seed: seed)
        sinceLastBucket = 0
    }

    func resetDesign() {
        design = .defaults
    }

    func copyDesignJSON() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(design), let json = String(data: data, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(json, forType: .string)
    }

    private func tick() {
        guard live else { return }
        sinceLastBucket += 1
        guard sinceLastBucket >= range.bucket else { return }
        sinceLastBucket = 0
        let values = stream.next()
        let date = Date()
        for index in history.series.indices where index < values.count {
            let v = values[index]
            history.series[index].points.removeFirst()
            history.series[index].points.append(HistoryPoint(date: date, avg: v.avg, min: v.min, max: v.max))
        }
    }

    private static func generate(
        metric: Metric,
        range: HistoryRange,
        scenario: Scenario,
        seed: UInt64
    ) -> (MetricHistory, MockStream) {
        var stream = MockStream(metric: metric, scenario: scenario, seed: seed, spread: range != .fiveMinutes)
        let definitions = MockStream.seriesDefinitions(metric)
        var points = Array(repeating: [HistoryPoint](), count: definitions.count)
        let start = Date().addingTimeInterval(-range.duration)
        for bucket in 0..<range.bucketCount {
            let date = start.addingTimeInterval(Double(bucket + 1) * range.bucket)
            for (index, v) in stream.next().enumerated() where index < points.count {
                points[index].append(HistoryPoint(date: date, avg: v.avg, min: v.min, max: v.max))
            }
        }
        let series = definitions.enumerated().map { index, def in
            HistorySeries(id: def.id, name: def.name, color: def.color, points: points[index])
        }
        return (MetricHistory(metric: metric, range: range, series: series), stream)
    }

    /// Overlays the saved keys on the defaults, so adding a knob keeps every
    /// value already tuned instead of dropping the whole saved design.
    private static func loadDesign() -> HistoryDesign {
        guard let saved = UserDefaults.standard.data(forKey: designKey),
              let savedKeys = try? JSONSerialization.jsonObject(with: saved) as? [String: Any],
              let defaults = try? JSONEncoder().encode(HistoryDesign.defaults),
              var merged = try? JSONSerialization.jsonObject(with: defaults) as? [String: Any]
        else { return .defaults }
        merged.merge(savedKeys) { _, new in new }
        guard let data = try? JSONSerialization.data(withJSONObject: merged),
              let design = try? JSONDecoder().decode(HistoryDesign.self, from: data)
        else { return .defaults }
        return design
    }

    private func saveDesign() {
        if let data = try? JSONEncoder().encode(design) {
            UserDefaults.standard.set(data, forKey: Self.designKey)
        }
    }
}
