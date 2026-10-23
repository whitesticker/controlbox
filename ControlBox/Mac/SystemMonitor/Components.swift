import SwiftUI
import AppKit

// MARK: - Shared visual constants

enum DashStyle {
    static let cardCorner: CGFloat = 8
    static let labelFont: Font = .system(size: 10, weight: .regular)
    static let valueFont: Font = .system(size: 11, weight: .medium)
}

// MARK: - Detail submenu shell

/// Consistent chrome for a section's expanded detail popover: title header
/// plus scrollable content (detail lists, like all sensors or all disk
/// volumes, can be arbitrarily long, unlike the fixed-size main dashboard).
/// `title` is nil when the history panel beside it already shows it.
struct DetailPanel<Content: View>: View {
    var title: String? = nil
    var systemImage: String = ""
    var width: CGFloat = 260
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                HStack(spacing: 5) {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            // No internal ScrollView/maxHeight: the submenu panel (see
            // DetailSubmenu) grows to fit its content the same way the
            // dropdown does.
            VStack(alignment: .leading, spacing: 4) {
                content
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, title == nil ? 6 : 12)
        .padding(.bottom, 12)
        .frame(width: width)
    }
}

// MARK: - Sparkline

/// Draws a `[Double]` series as a small filled line chart. Normalizes against
/// its own max unless an explicit `maxValue` is supplied. Handles empty or
/// near-zero data safely (no division by zero).
struct Sparkline: View {
    var values: [Double]
    var maxValue: Double? = nil
    var color: Color = .accentColor
    var lineWidth: CGFloat = 1.2

    private var effectiveMax: Double {
        let m = maxValue ?? (values.max() ?? 0)
        return m > 0.0001 ? m : 1.0
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let points = normalizedPoints(width: w, height: h)

            ZStack {
                if points.count > 1 {
                    // Filled area under the line.
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: h))
                        for p in points { path.addLine(to: p) }
                        path.addLine(to: CGPoint(x: points.last!.x, y: h))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.35), color.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    // Stroke line on top.
                    Path { path in
                        path.move(to: points[0])
                        for p in points.dropFirst() { path.addLine(to: p) }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                } else {
                    // Not enough data yet: draw a flat baseline.
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: h))
                        path.addLine(to: CGPoint(x: w, y: h))
                    }
                    .stroke(color.opacity(0.25), lineWidth: lineWidth)
                }
            }
        }
    }

    private func normalizedPoints(width: CGFloat, height: CGFloat) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let m = effectiveMax
        let n = values.count
        let stepX = width / CGFloat(n - 1)
        return values.enumerated().map { idx, v in
            let clamped = max(0, min(v / m, 1))
            let x = CGFloat(idx) * stepX
            let y = height - (CGFloat(clamped) * height)
            return CGPoint(x: x, y: y)
        }
    }
}

// MARK: - Usage bar

/// A horizontal capsule bar showing `fraction` (0...1) filled, with an
/// optional color threshold ramp (green/yellow/red) or a fixed tint.
struct UsageBar: View {
    var fraction: Double
    var color: Color? = nil
    var height: CGFloat = 6
    var trackColor: Color = Color.primary.opacity(0.08)

    private var clamped: Double { max(0, min(fraction, 1)) }

    private var resolvedColor: Color {
        if let c = color { return c }
        if clamped < 0.6 { return DashColors.statusGood }
        if clamped < 0.8 { return DashColors.statusWarning }
        return DashColors.statusCritical
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(trackColor)
                Capsule()
                    .fill(resolvedColor)
                    .frame(width: geo.size.width * CGFloat(clamped))
            }
        }
        .frame(height: height)
    }
}

// MARK: - Stat row

/// Exactly `slots` fixed-height lines, whatever `items.count` is, so a list
/// whose length changes with live data keeps one height. More items than
/// slots: the last slot reads "+N more". No items: slot 0 shows `emptyText`.
/// Unused slots stay blank, so slack only ever sits below the list.
struct SlotList<Item, Row: View>: View {
    var items: [Item]
    var slots: Int
    var slotHeight: CGFloat
    var spacing: CGFloat = 4
    var emptyText: String = "—"
    @ViewBuilder var row: (Item) -> Row

    var body: some View {
        let overflow = items.count > slots
        let shown = overflow ? slots - 1 : items.count
        return VStack(alignment: .leading, spacing: spacing) {
            ForEach(0..<slots, id: \.self) { slot in
                Group {
                    if slot < shown {
                        row(items[slot])
                    } else if overflow, slot == slots - 1 {
                        Text("+\(items.count - shown) more")
                            .font(DashStyle.labelFont)
                            .foregroundColor(.secondary)
                    } else if slot == 0, items.isEmpty {
                        Text(emptyText)
                            .font(DashStyle.labelFont)
                            .foregroundColor(.secondary)
                    } else {
                        Color.clear
                    }
                }
                .frame(maxWidth: .infinity, minHeight: slotHeight, maxHeight: slotHeight, alignment: .leading)
            }
        }
    }
}

/// "Who's using the most of this resource right now" -- a ranked top-5
/// list with app icons (Activity-Monitor-style), fed by the enclosing
/// `DetailSubmenu`'s `TopProcessFeed` while that submenu is open. Five
/// fixed slots whether the feed is loading, empty, or returned fewer rows.
struct TopProcessList: View {
    var label: String = "Top processes"
    var format: (Double) -> String
    /// Shows a process's `split` as two columns instead of `value`.
    var split: Split?

    struct Split {
        /// Mark and color for `IORate.read`, then for `IORate.write`.
        var read: (mark: String, color: Color)
        var write: (mark: String, color: Color)
        /// Display order; network shows upload (write) first, like the menu bar.
        var writeFirst = false
        /// Fits the mark plus "999.9 KB/s" in `DashStyle.valueFont`.
        var columnWidth: CGFloat = 72
    }

    @EnvironmentObject private var feed: TopProcessFeed

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 9, weight: .semibold)).foregroundColor(.secondary)
            SlotList(
                items: feed.processes,
                slots: TopProcessFeed.slotCount,
                slotHeight: 16,
                emptyText: feed.loaded ? "—" : "…"
            ) { proc in
                HStack(spacing: 6) {
                    if let icon = feed.icons[proc.pid] {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "gearshape")
                            .frame(width: 14, height: 14)
                            .foregroundColor(.secondary)
                    }
                    Text(proc.name)
                        .font(DashStyle.labelFont)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 8)
                    if let split, let rate = proc.split {
                        let columns = [(split.read, rate.read), (split.write, rate.write)]
                        ForEach(Array((split.writeFirst ? columns.reversed() : columns).enumerated()), id: \.offset) { _, column in
                            splitColumn(column.0, value: column.1, width: split.columnWidth)
                        }
                    } else {
                        Text(format(proc.value))
                            .font(DashStyle.valueFont)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    private func splitColumn(_ style: (mark: String, color: Color), value: Double, width: CGFloat) -> some View {
        HStack(spacing: 2) {
            Text(style.mark)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(style.color)
            Spacer(minLength: 0)
            Text(format(value))
                .font(DashStyle.valueFont)
                .monospacedDigit()
                .foregroundColor(value > 0 ? .primary : .secondary)
                .lineLimit(1)
        }
        .frame(width: width)
    }
}

/// An IP address, click-to-copy with brief "copied" feedback -- the IP is
/// usually the one thing in this app someone actually wants to paste
/// somewhere else. `prefix` is shown in secondary style before the bolded
/// IP itself (e.g. "en0 · "); pass "" for none.
struct CopyableIPText: View {
    var prefix: String = ""
    var ip: String
    var font: Font = .system(size: 8.5)

    @State private var copied = false

    private var isCopyable: Bool {
        !ip.isEmpty && ip != "—"
    }

    var body: some View {
        HStack(spacing: 3) {
            (Text(prefix).foregroundColor(.secondary)
                + Text(ip).fontWeight(.bold).foregroundColor(.primary))
                .font(font)
            if copied {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(DashColors.statusGood)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard isCopyable else { return }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(ip, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                copied = false
            }
        }
    }
}

/// A compact label/value row: label on the left (secondary), value on the
/// right (monospaced digits, primary).
struct StatRow: View {
    var label: String
    var value: String
    var valueColor: Color = .primary

    var body: some View {
        HStack {
            Text(label)
                .font(DashStyle.labelFont)
                .foregroundColor(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(DashStyle.valueFont)
                .foregroundColor(valueColor)
                .monospacedDigit()
        }
    }
}

/// A tiny label/value pair stacked vertically, sized for use inside a
/// 2-column grid (e.g. memory / battery detail stats) where a full-width
/// `StatRow` would waste horizontal space.
struct TinyStat: View {
    var label: String
    var value: String
    var valueColor: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 8.5))
                .foregroundColor(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(valueColor)
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A tight 2x2 grid of `TinyStat`s, used to replace four stacked full-width
/// `StatRow`s in space-constrained cards (Memory, Battery).
struct StatGrid2x2: View {
    var items: [(String, String)]

    var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 8) {
                    if row * 2 < items.count {
                        TinyStat(label: items[row * 2].0, value: items[row * 2].1)
                    }
                    if row * 2 + 1 < items.count {
                        TinyStat(label: items[row * 2 + 1].0, value: items[row * 2 + 1].1)
                    }
                }
            }
        }
    }
}

// MARK: - Mini core bar (vertical, for per-core CPU display)

/// A small vertical usage bar for a single CPU core, used in a dense grid.
struct CoreBar: View {
    var fraction: Double
    var width: CGFloat = 6

    private var clamped: Double { max(0, min(fraction, 1)) }

    private var barColor: Color {
        if clamped < 0.6 { return DashColors.statusGood }
        if clamped < 0.85 { return DashColors.statusWarning }
        return DashColors.statusCritical
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.primary.opacity(0.08))
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(barColor)
                    .frame(height: geo.size.height * CGFloat(clamped))
            }
        }
        .frame(width: width)
    }
}
