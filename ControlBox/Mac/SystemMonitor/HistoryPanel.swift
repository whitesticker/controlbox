import SwiftUI

enum HistoryStyle: String, CaseIterable, Identifiable {
    case candles, bars, line
    var id: String { rawValue }
    var title: String {
        switch self {
        case .candles: return "Candles"
        case .bars: return "Bars"
        case .line: return "Line"
        }
    }
}

enum HistoryReadout: String, CaseIterable, Identifiable {
    case header, tooltip, both
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// The user-adjustable part of the history panel (System Monitor → History).
struct HistorySettings: Equatable {
    var style: HistoryStyle
    var readout: HistoryReadout
    var compressSpikes: Bool
    var showStats: Bool
    var barSeconds: TimeInterval
}

/// Layout values, tuned in `Prototypes/HistoryLab`. Users never see these;
/// the hidden Design lab (Option-click the History preview in the pane)
/// edits them, and the menu draws with whatever is saved.
struct HistoryDesign: Codable, Equatable {
    enum Curve: String, Codable, CaseIterable, Identifiable {
        case linear, smooth, stepped
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    var panelWidth = 280.0
    var chartHeight = 150.0
    var padding = 10.0
    var lineWidth = 1.25
    var fillOpacity = 0.45
    var barGap = 0.25
    var valueSize = 20.0
    var curve = Curve.linear
    var showGrid = true
    var showYAxis = true
    var showTimeLabels = true

    static let tuned = HistoryDesign()
}

/// The history submenu: one metric over 5 min, 1 h, or 24 h. `settings` are
/// the user's options; `design` is the fixed layout.
struct HistoryPanel: View {
    let history: MetricHistory
    let settings: HistorySettings
    let design: HistoryDesign
    let onSelectRange: (HistoryRange) -> Void
    /// `history` grouped into bar-length bins for bars and candles, else itself.
    private let plotted: MetricHistory
    private let plottedBucket: TimeInterval
    /// `settings.style`, except candles and bars fall back to lines past two
    /// series (several fans), where bins on the same date pile on each other.
    private let style: HistoryStyle

    @State private var hoverDate: Date?

    init(
        history: MetricHistory,
        settings: HistorySettings,
        design: HistoryDesign,
        onSelectRange: @escaping (HistoryRange) -> Void
    ) {
        self.history = history
        self.settings = settings
        self.design = design
        self.onSelectRange = onSelectRange
        style = history.series.count > 2 ? .line : settings.style
        if style != .line {
            plottedBucket = max(settings.barSeconds, history.range.bucket)
            plotted = Self.binned(history, seconds: plottedBucket)
        } else {
            plottedBucket = history.range.bucket
            plotted = history
        }
    }

    private var unit: HistoryUnit { history.unit }
    private var range: HistoryRange { history.range }
    private var isMirrored: Bool { history.metric.isDual }
    private var showsHeaderReadout: Bool { settings.readout != .tooltip }
    private var showsTooltip: Bool { settings.readout != .header }
    private var hasEnoughData: Bool { (plotted.series.first?.points.count ?? 0) > 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if showsHeaderReadout {
                readout
            }
            chart
                .frame(height: design.chartHeight)
                .overlay {
                    if !hasEnoughData {
                        Text("Collecting history…")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            if design.showTimeLabels {
                timeLabels
            }
            if settings.showStats {
                stats
            }
        }
        .padding(design.padding)
        .frame(width: design.panelWidth, alignment: .leading)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: history.metric.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 16)
            Text(history.metric.title)
                .font(.system(size: 12, weight: .semibold))
            Spacer(minLength: 8)
            HistoryRangePicker(selection: range, onSelect: onSelectRange)
        }
    }

    @ViewBuilder
    private var readout: some View {
        if history.series.count <= 2 {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                ForEach(history.series) { series in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(valueText(series))
                            .font(.system(size: design.valueSize, weight: .semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                        legend(series)
                    }
                }
                Spacer(minLength: 0)
                timeCaptionText
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 3) {
                    ForEach(history.series) { series in
                        HStack(spacing: 4) {
                            Circle().fill(series.color).frame(width: 6, height: 6)
                            Text(series.name)
                                .font(.system(size: 9.5))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            Spacer(minLength: 2)
                            Text(valueText(series))
                                .font(.system(size: 10.5, weight: .semibold))
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                    }
                }
                timeCaptionText
            }
        }
    }

    private var timeCaptionText: some View {
        Text(timeCaption)
            .font(.system(size: 9.5))
            .foregroundColor(.secondary)
            .monospacedDigit()
    }

    private func legend(_ series: HistorySeries) -> some View {
        HStack(spacing: 4) {
            Circle().fill(series.color).frame(width: 6, height: 6)
            Text(series.name)
                .font(.system(size: 9.5))
                .foregroundColor(.secondary)
        }
    }

    // MARK: Chart

    /// Room on the trailing edge for the y-axis labels.
    private static let axisWidth: CGFloat = 34

    /// Drawn with `Canvas`, not Swift Charts: a detail submenu lays its
    /// content out several times per open (measure, move into the menu
    /// window, menu layout), and Charts rebuilt every point's marks each
    /// time, which made switching rows lag.
    private var chart: some View {
        let scale = HistoryYScale(series: plotted.series, unit: unit, style: style, compressSpikes: settings.compressSpikes, mirrored: isMirrored)
        let domain = xDomain
        let axisWidth = design.showYAxis ? Self.axisWidth : 0
        return GeometryReader { geometry in
            let plot = CGRect(
                x: 0, y: 0,
                width: max(geometry.size.width - axisWidth, 1),
                height: geometry.size.height
            )
            let mapper = HistoryPlotMapper(plot: plot, xDomain: domain, yDomain: scale.domain)
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    drawGrid(in: context, mapper: mapper, scale: scale)
                    drawSeries(in: context, mapper: mapper, scale: scale)
                    if let hoverDate {
                        let x = mapper.x(hoverDate)
                        var rule = Path()
                        rule.move(to: CGPoint(x: x, y: plot.minY))
                        rule.addLine(to: CGPoint(x: x, y: plot.maxY))
                        context.stroke(rule, with: .color(.primary.opacity(0.35)), lineWidth: 1)
                    }
                }
                Color.clear
                    .frame(width: plot.width, height: plot.height)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            updateHover(mapper.date(atX: location.x))
                        case .ended:
                            hoverDate = nil
                        }
                    }
                if showsTooltip, let hoverDate {
                    let ruleX = mapper.x(hoverDate)
                    tooltip
                        .alignmentGuide(.leading) { d in
                            ruleX + 6 + d.width <= plot.maxX ? -(ruleX + 6) : -max(ruleX - 6 - d.width, 0)
                        }
                        .alignmentGuide(.top) { _ in -2 }
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private func updateHover(_ date: Date) {
        hoverDate = plotted.series.first.flatMap { series in
            series.points.first { $0.date >= date && $0.date - plottedBucket < date }?.date
                ?? plotted.point(series, nearest: date)?.date
        }
    }

    private func drawGrid(in context: GraphicsContext, mapper: HistoryPlotMapper, scale: HistoryYScale) {
        let plot = mapper.plot
        for tick in scale.ticks {
            let y = mapper.y(tick)
            if design.showGrid {
                var line = Path()
                line.move(to: CGPoint(x: plot.minX, y: y))
                line.addLine(to: CGPoint(x: plot.maxX, y: y))
                context.stroke(
                    line,
                    with: .color(.secondary.opacity(0.5)),
                    style: StrokeStyle(lineWidth: 0.5, dash: [2, 3])
                )
            }
            if design.showYAxis {
                let label = context.resolve(
                    Text(unit.axis(scale.value(at: tick)))
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                )
                let height = label.measure(in: CGSize(width: Self.axisWidth, height: 20)).height
                let clampedY = min(max(y, plot.minY + height / 2), plot.maxY - height / 2)
                context.draw(label, at: CGPoint(x: plot.maxX + 4, y: clampedY), anchor: .leading)
            }
        }
    }

    /// Wick from low to high, body from first to last sample in the bin.
    /// Rising bins are hollow, falling bins filled.
    private func drawCandles(
        _ points: [HistoryPoint],
        color: Color,
        sign: Double,
        in context: GraphicsContext,
        mapper: HistoryPlotMapper,
        scale: HistoryYScale
    ) {
        var wicks = Path()
        var hollow = Path()
        var filled = Path()
        for point in points {
            let x0 = mapper.x(point.date.addingTimeInterval(-plottedBucket * (1 - design.barGap / 2)))
            let x1 = mapper.x(point.date.addingTimeInterval(-plottedBucket * design.barGap / 2))
            let mid = ((x0 + x1) / 2).rounded() + 0.5
            let high = mapper.y(scale.plot(point.max) * sign)
            let low = mapper.y(scale.plot(point.min) * sign)
            let open = mapper.y(scale.plot(point.open) * sign)
            let close = mapper.y(scale.plot(point.close) * sign)
            let top = min(open, close), bottom = max(max(open, close), top + 1)
            wicks.move(to: CGPoint(x: mid, y: min(high, low)))
            wicks.addLine(to: CGPoint(x: mid, y: top))
            wicks.move(to: CGPoint(x: mid, y: bottom))
            wicks.addLine(to: CGPoint(x: mid, y: max(high, low)))
            let body = CGRect(x: x0, y: top, width: max(x1 - x0, 1), height: bottom - top).insetBy(dx: 0.5, dy: 0)
            if point.close >= point.open {
                hollow.addRect(body)
            } else {
                filled.addRect(body)
            }
        }
        context.stroke(wicks, with: .color(color), lineWidth: 1)
        context.fill(filled, with: .color(color.opacity(design.fillOpacity)))
        context.stroke(filled, with: .color(color), lineWidth: 1)
        context.stroke(hollow, with: .color(color), lineWidth: 1)
    }

    private func drawSeries(in context: GraphicsContext, mapper: HistoryPlotMapper, scale: HistoryYScale) {
        var context = context
        context.clip(to: Path(mapper.plot.insetBy(dx: 0, dy: -design.lineWidth)))
        let stroke = StrokeStyle(lineWidth: design.lineWidth, lineCap: .round, lineJoin: .round)
        for (index, series) in plotted.series.enumerated() {
            let sign: Double = isMirrored && index == 1 ? -1 : 1
            let points = series.points
            guard !points.isEmpty else { continue }
            switch style {
            case .candles:
                drawCandles(series.points, color: series.color, sign: sign, in: context, mapper: mapper, scale: scale)
            case .line:
                let line = points.map { CGPoint(x: mapper.x($0.date), y: mapper.y(scale.plot($0.avg) * sign)) }
                var path = Path()
                path.addCurve(through: line, curve: design.curve)
                context.stroke(path, with: .color(series.color), style: stroke)
            case .bars:
                let base = mapper.y(scale.baseline)
                var bars = Path()
                for point in points {
                    let x0 = mapper.x(point.date.addingTimeInterval(-plottedBucket * (1 - design.barGap / 2)))
                    let x1 = mapper.x(point.date.addingTimeInterval(-plottedBucket * design.barGap / 2))
                    let y = mapper.y(scale.plot(point.avg) * sign)
                    bars.addRect(CGRect(x: x0, y: min(y, base), width: max(x1 - x0, 0.5), height: abs(y - base)))
                }
                context.fill(bars, with: .color(series.color.opacity(0.85)))
            }
        }
    }

    private var tooltip: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(timeCaption)
                .font(.system(size: 9.5, weight: .semibold))
                .monospacedDigit()
            ForEach(history.series) { series in
                HStack(spacing: 4) {
                    Circle().fill(series.color).frame(width: 6, height: 6)
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
        .foregroundColor(.secondary)
        .monospacedDigit()
    }

    @ViewBuilder
    private var stats: some View {
        if history.series.count == 1, let series = history.series.first {
            HStack(spacing: 8) {
                HistoryStat(label: "Avg", value: unit.format(average(series)))
                HistoryStat(label: "Peak", value: unit.format(series.points.map(\.max).max() ?? 0))
                HistoryStat(label: "Low", value: unit.format(series.points.map(\.min).min() ?? 0))
            }
        } else if history.metric.isDual {
            HStack(spacing: 8) {
                ForEach(history.series) { series in
                    HistoryStat(label: "\(series.name) avg", value: unit.format(average(series)))
                    HistoryStat(label: "Total", value: Fmt.bytes(total(series)))
                }
            }
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 6) {
                ForEach(history.series) { series in
                    HistoryStat(label: "\(series.name) peak", value: unit.format(series.points.map(\.max).max() ?? 0))
                }
            }
        }
    }

    // MARK: Values

    private var xDomain: ClosedRange<Date> {
        let end = plotted.series.first?.points.last?.date ?? Date()
        return end.addingTimeInterval(-range.duration)...end
    }

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm:ss a"
        return formatter
    }()

    private static let shortClockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    private var timeCaption: String {
        guard let hoverDate else { return "Now" }
        return (range == .oneDay ? Self.shortClockFormatter : Self.clockFormatter).string(from: hoverDate)
    }

    private func valueText(_ series: HistorySeries) -> String {
        let source = hoverDate == nil ? series : (plotted.series.first { $0.id == series.id } ?? series)
        guard let point = history.point(source, nearest: hoverDate) else { return "—" }
        return unit.format(point.avg)
    }

    private func average(_ series: HistorySeries) -> Double {
        guard !series.points.isEmpty else { return 0 }
        return series.points.map(\.avg).reduce(0, +) / Double(series.points.count)
    }

    private func total(_ series: HistorySeries) -> Double {
        series.points.map(\.avg).reduce(0, +) * range.bucket
    }

    /// Bins of `seconds` aligned to the clock, so bars keep their edges as
    /// samples arrive. The newest bin may be partial; bins that start
    /// before the visible range are dropped.
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
                    max: bin.points.map(\.max).max() ?? 0,
                    open: bin.points.first?.open ?? 0,
                    close: bin.points.last?.close ?? 0
                )
            }
            return HistorySeries(id: series.id, name: series.name, color: series.color, points: points)
        }
        return result
    }
}

/// Maps values into plot space. Byte rates can be √-compressed so one burst
/// does not flatten the rest; axis labels map back to real values.
struct HistoryYScale {
    let domain: ClosedRange<Double>
    let baseline: Double
    let ticks: [Double]
    private let top: Double
    private let compressed: Bool

    init(series: [HistorySeries], unit: HistoryUnit, style: HistoryStyle, compressSpikes: Bool, mirrored: Bool) {
        let useRange = style == .candles
        let points = series.flatMap(\.points)
        let peak = points.map { useRange ? $0.max : $0.avg }.max() ?? 1
        compressed = unit == .bytesPerSecond && compressSpikes
        switch unit {
        case .percent:
            top = 1
            domain = mirrored ? -1...1 : 0...1
            baseline = 0
        case .bytesPerSecond, .watts:
            top = max(peak * 1.1, 1)
            let upper = compressed ? 1 : top
            domain = mirrored ? -upper...upper : 0...upper
            baseline = 0
        case .celsius, .rpm:
            let low = points.map { useRange ? $0.min : $0.avg }.min() ?? 0
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

/// Maps dates and plot-space values into the chart's plot rectangle.
struct HistoryPlotMapper {
    let plot: CGRect
    let xDomain: ClosedRange<Date>
    let yDomain: ClosedRange<Double>

    private var duration: TimeInterval {
        max(xDomain.upperBound.timeIntervalSince(xDomain.lowerBound), 1)
    }

    func x(_ date: Date) -> CGFloat {
        plot.minX + plot.width * CGFloat(date.timeIntervalSince(xDomain.lowerBound) / duration)
    }

    func y(_ value: Double) -> CGFloat {
        let span = yDomain.upperBound - yDomain.lowerBound
        return plot.maxY - plot.height * CGFloat((value - yDomain.lowerBound) / (span > 0 ? span : 1))
    }

    func date(atX x: CGFloat) -> Date {
        let fraction = Double(min(max((x - plot.minX) / plot.width, 0), 1))
        return xDomain.lowerBound.addingTimeInterval(fraction * duration)
    }
}

extension Path {
    /// Linear, monotone-cubic (no overshoot past the data), or centre-step
    /// through `points`, as a new subpath.
    mutating func addCurve(through points: [CGPoint], curve: HistoryDesign.Curve) {
        guard let first = points.first else { return }
        move(to: first)
        guard points.count > 1 else { return }
        switch curve {
        case .linear:
            for point in points.dropFirst() { addLine(to: point) }
        case .stepped:
            for (p0, p1) in zip(points, points.dropFirst()) {
                let mid = (p0.x + p1.x) / 2
                addLine(to: CGPoint(x: mid, y: p0.y))
                addLine(to: CGPoint(x: mid, y: p1.y))
                addLine(to: p1)
            }
        case .smooth:
            let n = points.count
            var slopes = [CGFloat](repeating: 0, count: n - 1)
            for i in 0..<(n - 1) {
                let dx = points[i + 1].x - points[i].x
                slopes[i] = dx == 0 ? 0 : (points[i + 1].y - points[i].y) / dx
            }
            var tangents = [CGFloat](repeating: 0, count: n)
            tangents[0] = slopes[0]
            tangents[n - 1] = slopes[n - 2]
            for i in 1..<(n - 1) {
                tangents[i] = slopes[i - 1] * slopes[i] <= 0 ? 0 : (slopes[i - 1] + slopes[i]) / 2
            }
            for i in 0..<(n - 1) {
                guard slopes[i] != 0 else {
                    tangents[i] = 0
                    tangents[i + 1] = 0
                    continue
                }
                let a = tangents[i] / slopes[i], b = tangents[i + 1] / slopes[i]
                let length = a * a + b * b
                if length > 9 {
                    let tau = 3 / length.squareRoot()
                    tangents[i] = tau * a * slopes[i]
                    tangents[i + 1] = tau * b * slopes[i]
                }
            }
            for i in 0..<(n - 1) {
                let p0 = points[i], p1 = points[i + 1]
                let third = (p1.x - p0.x) / 3
                addCurve(
                    to: p1,
                    control1: CGPoint(x: p0.x + third, y: p0.y + tangents[i] * third),
                    control2: CGPoint(x: p1.x - third, y: p1.y - tangents[i + 1] * third)
                )
            }
        }
    }
}

/// Compact 5m / 1h / 24h switch. Plain buttons rather than a segmented
/// `Picker`, which does not take clicks reliably inside an `NSMenu`.
struct HistoryRangePicker: View {
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

struct HistoryStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 8.5))
                .foregroundColor(.secondary)
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
