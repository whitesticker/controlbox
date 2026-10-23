import SwiftUI
import Charts

/// The candidate tertiary submenu: one metric's history over a range.
/// Everything visual comes from `HistoryDesign`; data from `MetricHistory`.
/// This is the view that moves into Control Box once the design settles.
struct HistoryPanel: View {
    let history: MetricHistory
    let design: HistoryDesign
    let onSelectRange: (HistoryRange) -> Void
    /// What the chart draws: `history` grouped into bar-length bins for the
    /// bar style, otherwise `history` itself.
    private let plotted: MetricHistory
    private let plottedBucket: TimeInterval

    @State private var hoverDate: Date?

    init(history: MetricHistory, design: HistoryDesign, onSelectRange: @escaping (HistoryRange) -> Void = { _ in }) {
        self.history = history
        self.design = design
        self.onSelectRange = onSelectRange
        if design.style == .bars {
            plottedBucket = max(design.barSeconds(history.range), history.range.bucket)
            plotted = Self.binned(history, seconds: plottedBucket)
        } else {
            plottedBucket = history.range.bucket
            plotted = history
        }
    }

    private var unit: ValueUnit { history.unit }
    private var range: HistoryRange { history.range }
    private var isDual: Bool { history.metric.isDual }
    private var isMirrored: Bool { isDual && design.dualLayout == .mirrored && design.style != .heatStrip }
    private var showsHeaderReadout: Bool { design.readout != .tooltip }
    private var showsTooltip: Bool { design.readout != .header }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if showsHeaderReadout {
                readout
            }
            charts
            if design.showTimeLabels {
                timeLabels
            }
            if design.showStats {
                stats
            }
        }
        .padding(design.padding)
        .frame(width: design.panelWidth, alignment: .leading)
        .background(background)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: history.metric.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(history.metric.title)
                .font(.system(size: 12, weight: .semibold))
            Spacer(minLength: 8)
            if design.showRangePicker {
                RangePicker(selection: range, onSelect: onSelectRange)
            }
        }
    }

    @ViewBuilder
    private var readout: some View {
        if history.series.count <= 2 {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                ForEach(Array(history.series.enumerated()), id: \.element.id) { index, series in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(valueText(series))
                            .font(.system(size: design.valueSize, weight: .semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                        legend(series, index: index)
                    }
                }
                Spacer(minLength: 0)
                Text(timeCaption)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 3) {
                    ForEach(Array(history.series.enumerated()), id: \.element.id) { index, series in
                        HStack(spacing: 4) {
                            Circle().fill(design.color(series, index: index)).frame(width: 6, height: 6)
                            Text(series.name)
                                .font(.system(size: 9.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer(minLength: 2)
                            Text(valueText(series))
                                .font(.system(size: 10.5, weight: .semibold))
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                    }
                }
                Text(timeCaption)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private func legend(_ series: HistorySeries, index: Int) -> some View {
        HStack(spacing: 4) {
            Circle().fill(design.color(series, index: index)).frame(width: 6, height: 6)
            Text(series.name)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Charts

    @ViewBuilder
    private var charts: some View {
        if design.style == .heatStrip {
            heatStrip
                .frame(height: max(design.chartHeight, Double(history.series.count) * 14))
        } else if isDual, design.dualLayout == .stacked {
            VStack(spacing: 6) {
                ForEach(Array(plotted.series.enumerated()), id: \.element.id) { index, series in
                    chart([(series, index)], mirrored: false)
                        .frame(height: design.chartHeight / 2)
                }
            }
        } else {
            chart(Array(plotted.series.enumerated()).map { ($0.element, $0.offset) }, mirrored: isMirrored)
                .frame(height: design.chartHeight)
        }
    }

    private func chart(_ list: [(series: HistorySeries, index: Int)], mirrored: Bool) -> some View {
        let scale = YScale(series: list.map(\.series), unit: unit, design: design, mirrored: mirrored)
        return Chart {
            ForEach(list, id: \.series.id) { entry in
                let sign: Double = mirrored && entry.index == 1 ? -1 : 1
                let color = design.color(entry.series, index: entry.index)
                ForEach(entry.series.points) { point in
                    marks(entry.series, point, sign: sign, scale: scale, color: color)
                }
            }
            hoverRule
        }
        .chartYScale(domain: scale.domain)
        .chartXScale(domain: xDomain)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: scale.ticks) { value in
                if design.showGrid {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                }
                if design.showYAxis, let v = value.as(Double.self) {
                    AxisValueLabel {
                        Text(unit.axis(scale.value(at: v)))
                            .font(.system(size: 8))
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .chartOverlay { proxy in hoverOverlay(proxy) }
    }

    @ChartContentBuilder
    private func marks(
        _ series: HistorySeries,
        _ point: HistoryPoint,
        sign: Double,
        scale: YScale,
        color: Color
    ) -> some ChartContent {
        let x = PlottableValue.value("Time", point.date)
        let y = scale.plot(point.avg) * sign
        let baseline = scale.baseline
        switch design.style {
        case .area, .heatStrip:
            AreaMark(
                x: x,
                yStart: .value("Base", baseline),
                yEnd: .value("Value", y),
                series: .value("Series", series.id)
            )
            .interpolationMethod(design.interpolation.method)
            .foregroundStyle(
                LinearGradient(
                    colors: [color.opacity(design.fillOpacity), color.opacity(0.02)],
                    startPoint: sign < 0 ? .bottom : .top,
                    endPoint: sign < 0 ? .top : .bottom
                )
            )
            LineMark(x: x, y: .value("Value", y), series: .value("Series", series.id))
                .interpolationMethod(design.interpolation.method)
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: design.lineWidth, lineCap: .round, lineJoin: .round))
        case .line:
            LineMark(x: x, y: .value("Value", y), series: .value("Series", series.id))
                .interpolationMethod(design.interpolation.method)
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: design.lineWidth, lineCap: .round, lineJoin: .round))
        case .bars:
            RectangleMark(
                xStart: .value("Start", point.date.addingTimeInterval(-plottedBucket * (1 - design.barGap / 2))),
                xEnd: .value("End", point.date.addingTimeInterval(-plottedBucket * design.barGap / 2)),
                yStart: .value("Base", baseline),
                yEnd: .value("Value", y)
            )
            .foregroundStyle(color.opacity(0.85))
        case .band:
            AreaMark(
                x: x,
                yStart: .value("Low", scale.plot(point.min) * sign),
                yEnd: .value("High", scale.plot(point.max) * sign),
                series: .value("Series", series.id + ".band")
            )
            .interpolationMethod(design.interpolation.method)
            .foregroundStyle(color.opacity(design.fillOpacity))
            LineMark(x: x, y: .value("Value", y), series: .value("Series", series.id))
                .interpolationMethod(design.interpolation.method)
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: design.lineWidth, lineCap: .round, lineJoin: .round))
        }
    }

    /// One row per series, colored by value: reads as a thermal timeline.
    private var heatStrip: some View {
        Chart {
            ForEach(history.series) { series in
                let bounds = valueBounds(series)
                ForEach(series.points) { point in
                    RectangleMark(
                        xStart: .value("Start", point.date.addingTimeInterval(-range.bucket)),
                        xEnd: .value("End", point.date),
                        y: .value("Series", series.name),
                        height: .ratio(0.75)
                    )
                    .foregroundStyle(heatColor(point.avg, bounds: bounds))
                }
            }
            hoverRule
        }
        .chartXScale(domain: xDomain)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisValueLabel()
                    .font(.system(size: 8.5))
            }
        }
        .chartLegend(.hidden)
        .chartOverlay { proxy in hoverOverlay(proxy) }
    }

    @ChartContentBuilder
    private var hoverRule: some ChartContent {
        if let hoverDate {
            RuleMark(x: .value("Time", hoverDate))
                .foregroundStyle(Color.primary.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 1))
                .annotation(
                    position: .top,
                    spacing: 2,
                    overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                ) {
                    if showsTooltip {
                        tooltip
                    }
                }
        }
    }

    private func hoverOverlay(_ proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        guard let plotFrame = proxy.plotFrame else { return }
                        let x = location.x - geometry[plotFrame].origin.x
                        guard let date: Date = proxy.value(atX: x) else { return }
                        hoverDate = plotted.series.first.flatMap { series in
                            series.points.first { $0.date >= date && $0.date - plottedBucket < date }?.date
                                ?? plotted.point(series, nearest: date)?.date
                        }
                    case .ended:
                        hoverDate = nil
                    }
                }
        }
    }

    private var tooltip: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(timeCaption)
                .font(.system(size: 9.5, weight: .semibold))
                .monospacedDigit()
            ForEach(Array(history.series.enumerated()), id: \.element.id) { index, series in
                HStack(spacing: 4) {
                    Circle().fill(design.color(series, index: index)).frame(width: 6, height: 6)
                    Text(series.name)
                    Spacer(minLength: 8)
                    Text(valueText(series))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                .font(.system(size: 9.5))
            }
        }
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .fixedSize()
    }

    // MARK: Footer

    private var timeLabels: some View {
        HStack {
            ForEach(Array(range.timeLabels.enumerated()), id: \.offset) { index, label in
                if index > 0 { Spacer() }
                Text(label)
            }
        }
        .font(.system(size: 8.5))
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }

    @ViewBuilder
    private var stats: some View {
        if history.series.count == 1, let series = history.series.first {
            HStack(spacing: 8) {
                StatChip(label: "Avg", value: unit.format(average(series)))
                StatChip(label: "Peak", value: unit.format(series.points.map(\.max).max() ?? 0))
                StatChip(label: "Low", value: unit.format(series.points.map(\.min).min() ?? 0))
            }
        } else if isDual {
            HStack(spacing: 8) {
                ForEach(history.series) { series in
                    StatChip(label: "\(series.name) avg", value: unit.format(average(series)))
                    StatChip(label: "Total", value: ValueUnit.bytes(total(series)))
                }
            }
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 6) {
                ForEach(history.series) { series in
                    StatChip(label: "\(series.name) peak", value: unit.format(series.points.map(\.max).max() ?? 0))
                }
            }
        }
    }

    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: design.cornerRadius, style: .continuous)
        switch design.background {
        case .card:
            shape.fill(Color.primary.opacity(0.05))
        case .outlined:
            shape.fill(Color.primary.opacity(0.025))
                .overlay(shape.strokeBorder(Color.primary.opacity(0.15)))
        case .plain:
            Color.clear
        }
    }

    // MARK: Values

    private var xDomain: ClosedRange<Date> {
        let end = plotted.series.first?.points.last?.date ?? Date()
        return end.addingTimeInterval(-range.duration)...end
    }

    /// Groups points into bins of `seconds` aligned to the clock, so bars
    /// keep their edges while Live appends. The newest bin may be partial;
    /// bins that start before the visible range are dropped.
    private static func binned(_ history: MetricHistory, seconds: TimeInterval) -> MetricHistory {
        var result = history
        result.series = history.series.map { series in
            var bins: [(end: TimeInterval, points: [HistoryPoint])] = []
            for point in series.points {
                let end = (floor((point.date.timeIntervalSince1970 - 0.001) / seconds) + 1) * seconds
                if bins.last?.end == end {
                    bins[bins.count - 1].points.append(point)
                } else {
                    bins.append((end, [point]))
                }
            }
            let start = (bins.last?.end ?? 0) - history.range.duration
            let points = bins.filter { $0.end - seconds >= start - 0.001 }.map { bin in
                HistoryPoint(
                    date: Date(timeIntervalSince1970: bin.end),
                    avg: bin.points.map(\.avg).reduce(0, +) / Double(bin.points.count),
                    min: bin.points.map(\.min).min() ?? 0,
                    max: bin.points.map(\.max).max() ?? 0
                )
            }
            return HistorySeries(id: series.id, name: series.name, color: series.color, points: points)
        }
        return result
    }

    private var timeCaption: String {
        guard let hoverDate else { return "Now" }
        let formatter = DateFormatter()
        formatter.dateFormat = range == .oneDay ? "h:mm a" : "h:mm:ss a"
        return formatter.string(from: hoverDate)
    }

    private func valueText(_ series: HistorySeries) -> String {
        let source = hoverDate == nil ? series : (plotted.series.first { $0.id == series.id } ?? series)
        guard let point = history.point(source, nearest: hoverDate) else { return "—" }
        return unit.format(point.avg)
    }

    private func valueBounds(_ series: HistorySeries) -> ClosedRange<Double> {
        switch unit {
        case .percent: return 0...1
        case .celsius: return 30...80
        default:
            let values = series.points.map(\.avg)
            let lo = values.min() ?? 0
            return lo...max(values.max() ?? 1, lo + 1)
        }
    }

    private func heatColor(_ value: Double, bounds: ClosedRange<Double>) -> Color {
        let t = min(max((value - bounds.lowerBound) / (bounds.upperBound - bounds.lowerBound), 0), 1)
        return Color(hue: 0.33 * (1 - t), saturation: 0.75, brightness: 0.9).opacity(0.35 + t * 0.6)
    }

    private func average(_ series: HistorySeries) -> Double {
        guard !series.points.isEmpty else { return 0 }
        return series.points.map(\.avg).reduce(0, +) / Double(series.points.count)
    }

    private func total(_ series: HistorySeries) -> Double {
        series.points.map(\.avg).reduce(0, +) * range.bucket
    }
}

/// Maps values into plot space. Byte rates can be √-compressed so one burst
/// does not flatten the rest; axis labels map back to real values.
struct YScale {
    let domain: ClosedRange<Double>
    let baseline: Double
    let ticks: [Double]
    private let top: Double
    private let compressed: Bool

    init(series: [HistorySeries], unit: ValueUnit, design: HistoryDesign, mirrored: Bool) {
        let useBand = design.style == .band
        let points = series.flatMap(\.points)
        let peak = points.map { useBand ? $0.max : $0.avg }.max() ?? 1
        compressed = unit == .bytesPerSecond && design.compressSpikes
        switch unit {
        case .percent:
            top = 1
            domain = mirrored ? -1...1 : 0...1
            baseline = 0
        case .bytesPerSecond:
            top = max(peak * 1.1, 1)
            let upper = compressed ? 1 : top
            domain = mirrored ? -upper...upper : 0...upper
            baseline = 0
        case .celsius, .rpm:
            let low = points.map { useBand ? $0.min : $0.avg }.min() ?? 0
            let lower = max(0, low * 0.95)
            top = max(peak * 1.05, lower + 1)
            domain = lower...top
            baseline = lower
        }
        let lower = domain.lowerBound, upper = domain.upperBound
        ticks = mirrored ? [lower, 0, upper] : [lower, (lower + upper) / 2, upper]
    }

    func plot(_ value: Double) -> Double {
        compressed ? (max(value, 0) / top).squareRoot() : value
    }

    func value(at y: Double) -> Double {
        compressed ? y * y * top : abs(y)
    }
}

/// Compact 5m / 1h / 24h switch. Plain buttons rather than a segmented
/// `Picker`, which does not take clicks reliably inside an `NSMenu`.
struct RangePicker: View {
    let selection: HistoryRange
    let onSelect: (HistoryRange) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(HistoryRange.allCases) { range in
                Button {
                    onSelect(range)
                } label: {
                    Text(range.title)
                        .font(.system(size: 9.5, weight: range == selection ? .semibold : .regular))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Color.primary.opacity(range == selection ? 0.14 : 0))
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.primary.opacity(0.05)))
    }
}

struct StatChip: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 8.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 10.5, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
