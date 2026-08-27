import ControlBoxCore
import SwiftUI

struct NightShiftCurveView: View {
    @Binding var curve: NightShiftCurve
    var range: NightShift.CCTRange
    var enabled: Bool
    var onMove: (String, Double, Double, Bool) -> Void
    var onAdd: (Double, Double) -> Void
    var onRemove: (String) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var draggingID: String?
    @State private var pendingRemove = false
    @State private var selectedID: String?

    var body: some View {
        GeometryReader { geo in
            let layout = Layout(size: geo.size)
            ZStack(alignment: .topLeading) {
                TimelineView(.periodic(from: .now, by: 15)) { timeline in
                    chart(layout: layout, now: NightShiftCurve.minutes(from: timeline.date))
                }
                handles(layout: layout)
            }
            .contentShape(Rectangle())
            .gesture(drag(layout: layout))
            .onTapGesture(count: 2) { location in
                guard enabled, layout.plot.contains(location) else { return }
                if hitHandle(at: location, layout: layout) != nil { return }
                onAdd(layout.minutes(atX: location.x), layout.warmth(atY: location.y))
            }
            .onTapGesture { location in
                selectedID = hitHandle(at: location, layout: layout)
            }
        }
        .frame(minHeight: 268)
        .opacity(enabled ? 1 : 0.48)
        .allowsHitTesting(enabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Night Shift curve")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Double-click to add a point. Drag a point to change yellowness at that time.")
    }

    private var accessibilityValue: String {
        let warmth = curve.warmth(at: Date())
        return "Now \(NightShiftCurve.timeLabel(minutes: NightShiftCurve.minutes(from: Date()))), \(Int((warmth * 100).rounded())) percent warm"
    }

    private func chart(layout: Layout, now: Double) -> some View {
        Canvas { context, _ in
            drawBackground(context: &context, layout: layout)
            drawGrid(context: &context, layout: layout)
            drawFillAndCurve(context: &context, layout: layout)
            drawNow(context: &context, layout: layout, now: now)
            drawAxes(context: &context, layout: layout)
        }
    }

    private func handles(layout: Layout) -> some View {
        ForEach(curve.sorted) { point in
            let origin = layout.point(minutes: point.minutes, warmth: point.warmth)
            let active = draggingID == point.id || selectedID == point.id
            Circle()
                .fill(handleFill)
                .overlay {
                    Circle().strokeBorder(pendingRemove && draggingID == point.id ? Color.red : handleStroke, lineWidth: active ? 2.4 : 1.6)
                }
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.45 : 0.18), radius: active ? 3 : 1.5, y: 0.5)
                .frame(width: active ? 15 : 12, height: active ? 15 : 12)
                .position(origin)
                .help(handleHelp(point))
        }
    }

    private func drag(layout: Layout) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if draggingID == nil {
                    draggingID = hitHandle(at: value.startLocation, layout: layout)
                    selectedID = draggingID
                }
                guard let id = draggingID else { return }
                let rawWarmth = layout.rawWarmth(atY: value.location.y)
                pendingRemove = rawWarmth < -0.10 && curve.points.count > NightShiftCurve.minPoints
                onMove(id, layout.minutes(atX: value.location.x), min(max(rawWarmth, 0), 1), true)
            }
            .onEnded { value in
                defer {
                    draggingID = nil
                    pendingRemove = false
                }
                guard let id = draggingID else { return }
                let rawWarmth = layout.rawWarmth(atY: value.location.y)
                if rawWarmth < -0.10, curve.points.count > NightShiftCurve.minPoints {
                    onRemove(id)
                } else {
                    onMove(id, layout.minutes(atX: value.location.x), min(max(rawWarmth, 0), 1), false)
                }
            }
    }

    private func hitHandle(at location: CGPoint, layout: Layout) -> String? {
        curve.sorted.min { a, b in
            hypot(layout.point(minutes: a.minutes, warmth: a.warmth).x - location.x,
                  layout.point(minutes: a.minutes, warmth: a.warmth).y - location.y)
            < hypot(layout.point(minutes: b.minutes, warmth: b.warmth).x - location.x,
                    layout.point(minutes: b.minutes, warmth: b.warmth).y - location.y)
        }.flatMap { point in
            let origin = layout.point(minutes: point.minutes, warmth: point.warmth)
            return hypot(origin.x - location.x, origin.y - location.y) < 18 ? point.id : nil
        }
    }

    private func handleHelp(_ point: NightShiftPoint) -> String {
        "\(NightShiftCurve.timeLabel(minutes: point.minutes)) · \(Int((point.warmth * 100).rounded()))% · \(NightShiftCurve.kelvin(warmth: point.warmth, range: range)) K"
    }

    private func drawBackground(context: inout GraphicsContext, layout: Layout) {
        let plot = layout.plot
        context.fill(
            Path(plot),
            with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.98, green: 0.62, blue: 0.22).opacity(colorScheme == .dark ? 0.34 : 0.22),
                    Color(red: 0.45, green: 0.62, blue: 0.95).opacity(colorScheme == .dark ? 0.22 : 0.14),
                ]),
                startPoint: CGPoint(x: plot.midX, y: plot.minY),
                endPoint: CGPoint(x: plot.midX, y: plot.maxY)
            )
        )
        context.stroke(
            RoundedRectangle(cornerRadius: 8, style: .continuous).path(in: plot.insetBy(dx: -0.5, dy: -0.5)),
            with: .color(Color.primary.opacity(0.10)),
            lineWidth: 1
        )
    }

    private func drawGrid(context: inout GraphicsContext, layout: Layout) {
        let plot = layout.plot
        for hour in [0, 6, 12, 18, 24] {
            let x = layout.x(forMinutes: Double(hour * 60))
            var path = Path()
            path.move(to: CGPoint(x: x, y: plot.minY))
            path.addLine(to: CGPoint(x: x, y: plot.maxY))
            context.stroke(path, with: .color(Color.primary.opacity(hour == 0 || hour == 24 ? 0.08 : 0.12)), lineWidth: 1)
        }
        for warmth in [0.0, 0.5, 1.0] {
            let y = layout.y(forWarmth: warmth)
            var path = Path()
            path.move(to: CGPoint(x: plot.minX, y: y))
            path.addLine(to: CGPoint(x: plot.maxX, y: y))
            context.stroke(path, with: .color(Color.primary.opacity(0.10)), lineWidth: 1)
        }
    }

    private func drawFillAndCurve(context: inout GraphicsContext, layout: Layout) {
        let plot = layout.plot
        let samples = stride(from: 0.0, through: NightShiftCurve.minutesPerDay, by: 4).map { minutes in
            layout.point(minutes: minutes, warmth: curve.warmth(atMinutes: minutes))
        }
        guard let first = samples.first, let last = samples.last else { return }

        var fill = Path()
        fill.move(to: CGPoint(x: first.x, y: plot.maxY))
        for sample in samples {
            fill.addLine(to: sample)
        }
        fill.addLine(to: CGPoint(x: last.x, y: plot.maxY))
        fill.closeSubpath()
        context.fill(
            fill,
            with: .linearGradient(
                Gradient(colors: [
                    Color(red: 1.0, green: 0.58, blue: 0.16).opacity(0.42),
                    Color(red: 0.55, green: 0.68, blue: 1.0).opacity(0.08),
                ]),
                startPoint: CGPoint(x: plot.midX, y: plot.minY),
                endPoint: CGPoint(x: plot.midX, y: plot.maxY)
            )
        )

        var stroke = Path()
        stroke.move(to: first)
        for sample in samples.dropFirst() {
            stroke.addLine(to: sample)
        }
        context.stroke(
            stroke,
            with: .color(Color(red: 0.98, green: 0.55, blue: 0.14)),
            style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
        )
    }

    private func drawNow(context: inout GraphicsContext, layout: Layout, now: Double) {
        let plot = layout.plot
        let x = layout.x(forMinutes: now)
        var line = Path()
        line.move(to: CGPoint(x: x, y: plot.minY))
        line.addLine(to: CGPoint(x: x, y: plot.maxY))
        context.stroke(
            line,
            with: .color(Color.primary.opacity(0.55)),
            style: StrokeStyle(lineWidth: 1, dash: [3, 3])
        )
        let warmth = curve.warmth(atMinutes: now)
        let dot = layout.point(minutes: now, warmth: warmth)
        let marker = Path(ellipseIn: CGRect(x: dot.x - 3.5, y: dot.y - 3.5, width: 7, height: 7))
        context.fill(marker, with: .color(.white))
        context.stroke(marker, with: .color(Color.primary.opacity(0.75)), lineWidth: 1.2)
        context.draw(
            Text("Now").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary),
            at: CGPoint(x: min(max(x, plot.minX + 16), plot.maxX - 16), y: plot.minY + 10)
        )
    }

    private func drawAxes(context: inout GraphicsContext, layout: Layout) {
        let plot = layout.plot
        let labels: [(minutes: Double, title: String)] = [
            (0, "12 AM"),
            (6 * 60, "6 AM"),
            (12 * 60, "12 PM"),
            (18 * 60, "6 PM"),
            (24 * 60, "12 AM"),
        ]
        for label in labels {
            let x = layout.x(forMinutes: label.minutes)
            let anchor: UnitPoint = label.minutes <= 0
                ? .leading
                : (label.minutes >= 24 * 60 ? .trailing : .center)
            context.draw(
                Text(label.title).font(.system(size: 10)).foregroundStyle(.secondary),
                at: CGPoint(x: x, y: plot.maxY + 14),
                anchor: anchor
            )
        }
        context.draw(
            Text("Warm").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary),
            at: CGPoint(x: 22, y: plot.minY + 2),
            anchor: .top
        )
        context.draw(
            Text("Cool").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary),
            at: CGPoint(x: 22, y: plot.maxY - 2),
            anchor: .bottom
        )
    }

    private var handleFill: Color {
        colorScheme == .dark ? Color(white: 0.92) : Color.white
    }

    private var handleStroke: Color {
        Color(red: 0.92, green: 0.48, blue: 0.12)
    }

    private struct Layout {
        var size: CGSize

        var plot: CGRect {
            CGRect(x: 46, y: 10, width: max(size.width - 64, 40), height: max(size.height - 36, 40))
        }

        func x(forMinutes minutes: Double) -> CGFloat {
            plot.minX + CGFloat(NightShiftCurve.wrap(minutes) / NightShiftCurve.minutesPerDay) * plot.width
        }

        func y(forWarmth warmth: Double) -> CGFloat {
            plot.maxY - CGFloat(min(max(warmth, 0), 1)) * plot.height
        }

        func point(minutes: Double, warmth: Double) -> CGPoint {
            CGPoint(x: x(forMinutes: minutes), y: y(forWarmth: warmth))
        }

        func minutes(atX x: CGFloat) -> Double {
            let t = Double((x - plot.minX) / max(plot.width, 1))
            return NightShiftCurve.wrap(t * NightShiftCurve.minutesPerDay)
        }

        func rawWarmth(atY y: CGFloat) -> Double {
            Double((plot.maxY - y) / max(plot.height, 1))
        }

        func warmth(atY y: CGFloat) -> Double {
            min(max(rawWarmth(atY: y), 0), 1)
        }
    }
}
