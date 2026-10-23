import SwiftUI
import Charts

/// Every knob the Inspector exposes. Codable so a tuned design can be copied
/// out as JSON and become the defaults when the panel moves into Control Box.
struct HistoryDesign: Codable, Equatable {
    enum Style: String, CaseIterable, Identifiable, Codable {
        case area, line, bars, band, heatStrip
        var id: String { rawValue }
        /// The styles Control Box users can pick between.
        static let userChoices: [Style] = [.band, .bars, .line]
        var title: String {
            switch self {
            case .area: return "Area"
            case .line: return "Line"
            case .bars: return "Bars"
            case .band: return "Min–max band"
            case .heatStrip: return "Heat strip"
            }
        }
    }

    enum Interpolation: String, CaseIterable, Identifiable, Codable {
        case smooth, linear, stepped
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var method: InterpolationMethod {
            switch self {
            case .smooth: return .monotone
            case .linear: return .linear
            case .stepped: return .stepCenter
            }
        }
    }

    enum DualLayout: String, CaseIterable, Identifiable, Codable {
        case mirrored, overlaid, stacked
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    enum Readout: String, CaseIterable, Identifiable, Codable {
        case header, tooltip, both
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    enum Background: String, CaseIterable, Identifiable, Codable {
        case card, outlined, plain
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    enum Palette: String, CaseIterable, Identifiable, Codable {
        case standard, accent, mono
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    var panelWidth = 280.0
    var chartHeight = 150.0
    var padding = 10.0
    var cornerRadius = 6.0

    var style = Style.band
    var interpolation = Interpolation.linear
    var dualLayout = DualLayout.mirrored
    var lineWidth = 1.25
    var fillOpacity = 0.45
    var barGap = 0.25
    /// Time one bar covers, per range, so a longer range draws wider
    /// buckets instead of more, thinner bars.
    var barSeconds5m = 10.0
    var barSeconds1h = 120.0
    var barSeconds24h = 3600.0
    var compressSpikes = true
    var showGrid = true
    var showYAxis = true
    var showTimeLabels = true

    var readout = Readout.both
    var valueSize = 20.0
    var showStats = true
    var showRangePicker = true

    var background = Background.plain
    var palette = Palette.accent

    static let defaults = HistoryDesign()

    func barSeconds(_ range: HistoryRange) -> TimeInterval {
        switch range {
        case .fiveMinutes: return barSeconds5m
        case .oneHour: return barSeconds1h
        case .oneDay: return barSeconds24h
        }
    }

    mutating func setBarSeconds(_ seconds: TimeInterval, for range: HistoryRange) {
        switch range {
        case .fiveMinutes: barSeconds5m = seconds
        case .oneHour: barSeconds1h = seconds
        case .oneDay: barSeconds24h = seconds
        }
    }

    /// Multiples of the range's stored bucket (1 s, 20 s, 5 min).
    static func barChoices(_ range: HistoryRange) -> [TimeInterval] {
        switch range {
        case .fiveMinutes: return [5, 10, 15, 30, 60]
        case .oneHour: return [60, 120, 180, 300, 600]
        case .oneDay: return [900, 1800, 3600, 7200]
        }
    }

    func color(_ series: HistorySeries, index: Int) -> Color {
        if series.isUpload, palette != .mono { return .red }
        switch palette {
        case .standard: return series.color
        case .accent: return Color.accentColor.opacity(index == 0 ? 1 : max(0.35, 1 - Double(index) * 0.2))
        case .mono: return Color.primary.opacity(index == 0 ? 0.85 : max(0.3, 0.7 - Double(index) * 0.12))
        }
    }
}
