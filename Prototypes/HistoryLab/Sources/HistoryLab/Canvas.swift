import AppKit
import SwiftUI

/// The live panel as it renders inside a menu, shared by the canvas and the
/// real menu bar preview.
struct LiveHistoryPanel: View {
    @EnvironmentObject private var store: LabStore

    var body: some View {
        HistoryPanel(history: store.history, design: store.design) { store.range = $0 }
            .padding(.horizontal, 5)
    }
}

/// Stand-in for a Control Box detail submenu so the history panel is judged
/// next to what it cascades from. The graph is its own menu item in the real
/// menu: hovering it opens the history submenu, with no separate row.
struct DetailMock: View {
    let metric: Metric

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailGraphMock(metric: metric, forceHighlight: true)
                .alignmentGuide(.historyRow) { $0[.top] }
            DetailListMock()
        }
        .frame(width: 260, alignment: .leading)
    }
}

/// Header plus the live graph. Hover tints it to show that it opens history.
struct DetailGraphMock: View {
    @EnvironmentObject private var store: LabStore
    let metric: Metric
    var forceHighlight = false

    @State private var hovering = false

    private var history: MetricHistory { store.history }
    private var highlighted: Bool { hovering || forceHighlight }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(metric.title)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                ForEach(history.series.prefix(2)) { series in
                    if let latest = series.latest {
                        Text(history.unit.format(latest.avg))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(history.series.count > 1 ? store.design.color(series, index: 0) : .primary)
                            .monospacedDigit()
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .opacity(highlighted ? 1 : 0)
            }
            sparkline
                .frame(height: 34)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(highlighted ? 0.08 : 0))
        )
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: highlighted)
        .frame(width: 260, alignment: .leading)
    }

    private var sparkline: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(Array(history.series.prefix(2).enumerated()), id: \.element.id) { index, series in
                    let values = series.points.suffix(60).map(\.avg)
                    let all = history.series.prefix(2).flatMap { $0.points.suffix(60).map(\.avg) }
                    let lo = all.min() ?? 0
                    let span = max((all.max() ?? 1) - lo, 0.0001)
                    Path { path in
                        for (i, value) in values.enumerated() {
                            let x = geometry.size.width * Double(i) / Double(max(values.count - 1, 1))
                            let y = geometry.size.height * (1 - (value - lo) / span)
                            i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    .stroke(store.design.color(series, index: index), lineWidth: 1.2)
                }
            }
        }
    }
}

struct DetailListMock: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            Text("Top processes")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            ForEach(Self.processes, id: \.self) { name in
                HStack {
                    Image(systemName: "app.dashed")
                        .foregroundStyle(.secondary)
                    Text(name)
                    Spacer()
                    Text("—")
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 11))
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .frame(width: 260, alignment: .leading)
    }

    private static let processes = ["WindowServer", "Safari", "Xcode", "Cursor Helper", "mds_stores"]
}

extension VerticalAlignment {
    private enum HistoryRow: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { d[.top] }
    }

    static let historyRow = VerticalAlignment(HistoryRow.self)
}

/// Fake menu chrome: the same material, corner, and shadow as an `NSMenu`.
struct MenuChrome<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.vertical, 5)
            .background(VisualEffect(material: .menu))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
    }
}

struct VisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

struct LabCanvas: View {
    @EnvironmentObject private var store: LabStore

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            HStack(alignment: .historyRow, spacing: -2) {
                MenuChrome {
                    DetailMock(metric: store.metric)
                }
                MenuChrome {
                    LiveHistoryPanel()
                }
                .alignmentGuide(.historyRow) { $0[.top] + 5 }
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(
            LinearGradient(
                colors: [Color(red: 0.25, green: 0.35, blue: 0.55), Color(red: 0.55, green: 0.4, blue: 0.5)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}
