import SwiftUI
import AppKit

let menuRowWidth: CGFloat = 300

/// One row's shell: an icon+title header (matching every other row), then
/// arbitrary content underneath -- the same rich, multi-line content each
/// section showed in the old 2-column card grid (sparklines, per-core bars,
/// stat grids, volume rows, etc.), just laid out at full row width instead
/// of half-width. A single summary line wasn't enough at a glance, so this
/// carries everything the compact grid used to show, directly in the main
/// menu.
struct MenuRow<Content: View, HeaderTrailing: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var headerTrailing: HeaderTrailing
    @ViewBuilder var content: Content

    init(
        title: String,
        systemImage: String,
        @ViewBuilder headerTrailing: () -> HeaderTrailing,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.headerTrailing = headerTrailing()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer(minLength: 4)
                headerTrailing
            }
            content
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: menuRowWidth - 16, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DashStyle.cardCorner, style: .continuous)
                .fill(DashColors.cardBackground)
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(width: menuRowWidth, alignment: .leading)
    }
}

extension MenuRow where HeaderTrailing == EmptyView {
    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.headerTrailing = EmptyView()
        self.content = content()
    }
}

struct DateRow: View {
    @EnvironmentObject var monitor: SystemMonitor

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm:ss a · EEE, MMM d"
        return f
    }()

    private var combinedString: String {
        Self.formatter.string(from: monitor.snapshot.date)
    }

    var body: some View {
        Text(combinedString)
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
            .foregroundColor(.secondary)
            .frame(width: menuRowWidth)
            .padding(.vertical, 6)
    }
}

struct CPURow: View {
    @EnvironmentObject var monitor: SystemMonitor
    var body: some View {
        let cpu = monitor.snapshot.cpu
        let history = monitor.cpuHistory
        MenuRow(title: "CPU", systemImage: "cpu") {
            Sparkline(values: history, maxValue: 1.0, color: DashColors.cpuLine)
                .frame(width: 70, height: 14)
        } content: {
            HStack(alignment: .firstTextBaseline) {
                Text(Fmt.percent(cpu.totalUsage))
                    .font(.system(size: 16, weight: .semibold))
                    .monospacedDigit()
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("U \(Fmt.percent(cpu.user))")
                    Text("S \(Fmt.percent(cpu.system))")
                }
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .monospacedDigit()
            }

            if !cpu.perCore.isEmpty {
                HStack(spacing: 2) {
                    ForEach(Array(cpu.perCore.enumerated()), id: \.offset) { _, v in
                        CoreBar(fraction: v, width: 5)
                    }
                }
                .frame(height: 18)
            }

            if cpu.pCoreCount > 0 {
                HStack {
                    Text("P \(Fmt.percent(cpu.performanceCoreUsage))")
                    Spacer()
                    Text("E \(Fmt.percent(cpu.efficiencyCoreUsage))")
                }
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .monospacedDigit()
            }

            HStack {
                Text(String(format: "Load %.1f %.1f %.1f", cpu.load1, cpu.load5, cpu.load15))
                Spacer()
                Text("Up \(Fmt.uptime(cpu.uptime))")
            }
            .font(.system(size: 9))
            .foregroundColor(.secondary)
            .monospacedDigit()
        }
    }
}

struct CPUDetailStandalone: View {
    @EnvironmentObject var monitor: SystemMonitor
    var body: some View {
        CPUDetail(cpu: monitor.snapshot.cpu)
    }
}

struct GPURow: View {
    @EnvironmentObject var monitor: SystemMonitor
    var body: some View {
        let gpu = monitor.snapshot.gpu
        MenuRow(title: "GPU", systemImage: "cube.transparent") {
            if gpu.available {
                Sparkline(values: monitor.gpuHistory, maxValue: 1.0, color: DashColors.gpuLine)
                    .frame(width: 70, height: 14)
            }
        } content: {
            if gpu.available {
                Text(Fmt.percent(gpu.utilization))
                    .font(.system(size: 16, weight: .semibold))
                    .monospacedDigit()
                Text(gpu.name.isEmpty ? "GPU" : gpu.name)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Text("n/a")
                    .font(DashStyle.labelFont)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct GPUDetailStandalone: View {
    @EnvironmentObject var monitor: SystemMonitor
    var body: some View {
        GPUDetail(gpu: monitor.snapshot.gpu)
    }
}

struct MemoryRow: View {
    @EnvironmentObject var monitor: SystemMonitor

    var body: some View {
        let memory = monitor.snapshot.memory
        let pressureColor = memory.pressureColor
        MenuRow(title: "Memory", systemImage: "memorychip") {
            Text(Fmt.percent(memory.pressure))
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(pressureColor)
        } content: {
            HStack {
                Text("\(Fmt.bytesBinary(memory.used)) / \(Fmt.bytesBinary(memory.total))")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                Spacer()
            }
            UsageBar(fraction: memory.pressure, color: pressureColor, height: 6)

            StatGrid2x2(items: [
                ("App", Fmt.bytesBinary(memory.app)),
                ("Wired", Fmt.bytesBinary(memory.wired)),
                ("Compressed", Fmt.bytesBinary(memory.compressed)),
                ("Cached", Fmt.bytesBinary(memory.cached)),
            ])
        }
    }
}

struct MemoryDetailStandalone: View {
    @EnvironmentObject var monitor: SystemMonitor
    var body: some View {
        MemoryDetail(memory: monitor.snapshot.memory)
    }
}

struct NetworkRow: View {
    @EnvironmentObject var monitor: SystemMonitor

    var body: some View {
        let network = monitor.snapshot.network
        MenuRow(title: "Network", systemImage: "network") {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(DashColors.download)
                        Text(Fmt.speed(network.downBytesPerSec))
                            .font(.system(size: 10.5, weight: .semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    Sparkline(values: monitor.netDownHistory, color: DashColors.download)
                        .frame(height: 16)
                }
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(DashColors.upload)
                        Text(Fmt.speed(network.upBytesPerSec))
                            .font(.system(size: 10.5, weight: .semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    Sparkline(values: monitor.netUpHistory, color: DashColors.upload)
                        .frame(height: 16)
                }
            }

            HStack(spacing: 3) {
                Image(systemName: network.primaryKind.systemImage)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundColor(.secondary)
                CopyableIPText(
                    prefix: network.primaryInterface.isEmpty ? "— · "
                        : network.primaryDisplayName == network.primaryInterface ? "\(network.primaryInterface) · "
                        : "\(network.primaryDisplayName) (\(network.primaryInterface)) · ",
                    ip: network.primaryIP.isEmpty ? "—" : network.primaryIP,
                    font: .system(size: 9)
                )
            }
            .lineLimit(1)
            .truncationMode(.middle)

            Text("↓\(Fmt.bytes(network.sessionDown)) ↑\(Fmt.bytes(network.sessionUp)) session")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }
}

struct NetworkDetailStandalone: View {
    @EnvironmentObject var monitor: SystemMonitor
    var body: some View {
        NetworkDetail(network: monitor.snapshot.network)
    }
}

struct DiskRow: View {
    @EnvironmentObject var monitor: SystemMonitor

    private var topVolumes: [DiskVolumeSample] {
        Array(monitor.snapshot.disk.volumes.sorted { $0.total > $1.total }.prefix(2))
    }

    var body: some View {
        let disk = monitor.snapshot.disk
        MenuRow(title: "Disk", systemImage: "internaldrive") {
            SlotList(items: topVolumes, slots: 2, slotHeight: 15, emptyText: "No volumes found") { vol in
                VolumeRow(volume: vol)
            }

            HStack(spacing: 4) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(DashColors.diskRead)
                Text(Fmt.speed(disk.readBytesPerSec))
                    .font(.system(size: 9.5, weight: .medium))
                    .monospacedDigit()
                Spacer(minLength: 6)
                Image(systemName: "arrow.up.doc")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(DashColors.diskWrite)
                Text(Fmt.speed(disk.writeBytesPerSec))
                    .font(.system(size: 9.5, weight: .medium))
                    .monospacedDigit()
                Spacer()
                Sparkline(values: monitor.diskReadHistory, color: DashColors.diskRead)
                    .frame(width: 40, height: 14)
                Sparkline(values: monitor.diskWriteHistory, color: DashColors.diskWrite)
                    .frame(width: 40, height: 14)
            }
        }
    }
}

struct DiskDetailStandalone: View {
    @EnvironmentObject var monitor: SystemMonitor
    var body: some View {
        DiskDetail(disk: monitor.snapshot.disk)
    }
}

struct SensorsRow: View {
    @EnvironmentObject var monitor: SystemMonitor

    private func hottestOther(_ sensors: SensorSample) -> TemperatureSample? {
        sensors.temperatures.filter { $0.celsius > 0 }.max(by: { $0.celsius < $1.celsius })
    }

    var body: some View {
        let sensors = monitor.snapshot.sensors
        MenuRow(title: "Sensors", systemImage: "thermometer.medium") {
            if sensors.cpuTemp <= 0 && sensors.gpuTemp <= 0 && sensors.fans.isEmpty {
                Text("No sensor data")
                    .font(DashStyle.labelFont)
                    .foregroundColor(.secondary)
            } else {
                HStack(spacing: 8) {
                    if sensors.cpuTemp > 0 {
                        HighlightStat(label: "CPU", value: Fmt.temp(sensors.cpuTemp))
                    }
                    if sensors.gpuTemp > 0 {
                        HighlightStat(label: "GPU", value: Fmt.temp(sensors.gpuTemp))
                    }
                    ForEach(Array(sensors.fans.enumerated()), id: \.offset) { _, f in
                        HighlightStat(label: "\(f.label) (rpm)", value: Fmt.rpmNumber(f.rpm))
                    }
                }

                if let hot = hottestOther(sensors) {
                    Text("\(SensorNames.displayName(for: hot.label)): \(Fmt.temp(hot.celsius))")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

struct SensorsDetailStandalone: View {
    @EnvironmentObject var monitor: SystemMonitor
    @ObservedObject var focus: HistoryFocus

    var body: some View {
        SensorsDetail(sensors: monitor.snapshot.sensors, focused: focus.metric) { focus.select($0) }
    }
}

struct PowerRow: View {
    @EnvironmentObject var monitor: SystemMonitor

    private var levelColor: Color {
        let power = monitor.snapshot.power
        if power.isCharging { return DashColors.statusGood }
        if power.percentage < 0.2 { return DashColors.statusCritical }
        if power.percentage < 0.4 { return DashColors.statusWarning }
        return DashColors.statusGood
    }

    private func timeLabel(_ power: PowerSample) -> String {
        if power.isCharging {
            return power.timeToFullMinutes >= 0 ? "\(Fmt.minutes(power.timeToFullMinutes)) to full" : "Calculating…"
        } else {
            return power.timeToEmptyMinutes >= 0 ? "\(Fmt.minutes(power.timeToEmptyMinutes)) left" : "Calculating…"
        }
    }

    var body: some View {
        let power = monitor.snapshot.power
        MenuRow(title: "Battery", systemImage: "battery.100") {
            if power.hasBattery {
                HStack(spacing: 4) {
                    if power.isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9))
                            .foregroundColor(DashColors.statusGood)
                    }
                    Text(Fmt.percent(power.percentage))
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                    Spacer(minLength: 4)
                    Text(timeLabel(power))
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                UsageBar(fraction: power.percentage, color: levelColor, height: 5)

                StatGrid2x2(items: [
                    ("Cycles", "\(power.cycleCount)"),
                    ("Health", Fmt.percent(power.health)),
                    ("Draw", Fmt.watts(power.powerWatts)),
                    ("Temp", Fmt.temp(power.temperature)),
                ])
            } else {
                Text("On AC power / no battery")
                    .font(DashStyle.labelFont)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct PowerDetailStandalone: View {
    @EnvironmentObject var monitor: SystemMonitor
    var body: some View {
        PowerDetail(power: monitor.snapshot.power)
    }
}

// MARK: - Menu hosting view

/// SwiftUI content for one dropdown row or detail submenu (see MenuPanel.swift).
///
/// - `warmUp()` runs one real layout pass in a throwaway offscreen window at
///   construction. Without it the first open or two read a too-short
///   `fittingSize` and clip the content.
/// - Setting `isTracking` to true (when its panel opens) re-measures against
///   current data before display.
/// - While tracking, every SwiftUI-driven `layout()` schedules one
///   re-measure, and `onResize` lets the owning panel follow: a volume
///   mounting or the battery row loading while the panel is up grows or
///   shrinks it instead of clipping or leaving a gap.
/// - Content is pinned to the top, so a frame that is briefly taller than
///   the content leaves the slack at the bottom, not split above and below.
final class MenuHostingView: NSHostingView<AnyView> {
    var isTracking = false {
        didSet { if isTracking { fit() } }
    }
    var onResize: (() -> Void)?
    private var fitPending = false

    init<Content: View>(content: Content, initialSize: NSSize) {
        super.init(rootView: Self.pinned(content))
        frame = NSRect(origin: .zero, size: initialSize)
        warmUp()
    }

    /// Swaps the SwiftUI content in place (same view, same panel).
    func setContent<Content: View>(_ content: Content) {
        rootView = Self.pinned(content)
    }

    private static func pinned<Content: View>(_ content: Content) -> AnyView {
        AnyView(content.frame(maxHeight: .infinity, alignment: .top))
    }

    required init(rootView: AnyView) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        guard isTracking, !fitPending else { return }
        fitPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            fitPending = false
            if isTracking { fit() }
        }
    }

    private func fit() {
        layoutSubtreeIfNeeded()
        let fitting = fittingSize
        guard fitting.height > 0,
              abs(fitting.height - frame.height) > 0.5 || abs(fitting.width - frame.width) > 0.5
        else { return }
        setFrameSize(fitting)
        onResize?()
    }

    private func warmUp() {
        let warmupWindow = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        warmupWindow.contentView = self
        fit()
        warmupWindow.contentView = nil
    }
}

// MARK: - Detail submenu

/// One section's detail submenu: a `MenuPanel` beside the dropdown, shown
/// as soon as the pointer enters its row and hidden (not torn down) when
/// another row takes over, so the next show is only a window order-in.
///
/// A submenu with a top-process list owns that list's `TopProcessFeed`, which
/// samples only while this submenu is shown.
///
/// `history` feeds get a second panel (`HistoryColumn`) beyond the stats
/// panel, on the side away from the dropdown, tops aligned. It opens when
/// the pointer enters the stats panel and closes when the pointer is back on
/// a dropdown row. Two panels rather than two columns in one: either side
/// can be the taller one, and a shared panel left an empty block under the
/// shorter.
final class DetailSubmenu {
    let panel: MenuPanel
    private let hostingView: MenuHostingView
    private let historyPanel: MenuPanel?
    private let historyHostingView: MenuHostingView?
    private let topProcesses: TopProcessFeed?
    private let historyFeeds: [HistoryFeed]
    private var opensLeft = false

    /// Gap between panels, and how far above its row the submenu's top sits.
    private static let gap: CGFloat = 2
    private static let topInset: CGFloat = 5

    init<Content: View>(
        topProcesses kind: TopProcessKind? = nil,
        history feeds: [HistoryFeed] = [],
        width: CGFloat = 260,
        @ViewBuilder content: () -> Content
    ) {
        let built = content()
        let feed = kind.map(TopProcessFeed.init(kind:))
        let detail = feed.map { AnyView(built.environmentObject($0)) } ?? AnyView(built)
        topProcesses = feed
        hostingView = MenuHostingView(content: detail, initialSize: NSSize(width: width, height: 600))
        panel = MenuPanel(content: hostingView)

        historyFeeds = feeds
        if historyFeeds.isEmpty {
            historyHostingView = nil
            historyPanel = nil
        } else {
            let history = MenuHostingView(
                content: HistoryColumn(feeds: historyFeeds),
                initialSize: NSSize(width: PreferencesStore.shared.historyDesign.panelWidth + 10, height: 340)
            )
            historyHostingView = history
            historyPanel = MenuPanel(content: history)
        }

        hostingView.onResize = { [weak self] in
            guard let self, panel.isVisible else { return }
            panel.fitContent(anchorRight: opensLeft)
            placeHistory()
        }
        historyHostingView?.onResize = { [weak self] in
            guard let self, historyPanel?.isVisible == true else { return }
            placeHistory()
        }
        panel.onPointerEnter = { [weak self] in self?.showHistory() }
    }

    func owns(_ window: NSWindow?) -> Bool {
        window != nil && (window === panel || window === historyPanel)
    }

    /// Opens on the side of `parent` away from the screen edge it is near,
    /// falling back to the other side when the stats and history panels do
    /// not fit there.
    func show(beside parent: NSRect, rowTop: CGFloat) {
        let screen = (NSScreen.screens.first { $0.frame.intersects(parent) } ?? NSScreen.main)?.visibleFrame ?? parent
        topProcesses?.start()
        hostingView.isTracking = true

        let size = hostingView.frame.size
        let historyWidth = historyHostingView.map { $0.frame.width + Self.gap } ?? 0
        let needed = size.width + Self.gap + historyWidth
        let roomLeft = parent.minX - needed >= screen.minX
        let roomRight = parent.maxX + needed <= screen.maxX
        opensLeft = parent.midX > screen.midX ? (roomLeft || !roomRight) : !roomRight

        let x = opensLeft ? parent.minX - size.width - Self.gap : parent.maxX + Self.gap
        let tallest = max(size.height, historyHostingView?.frame.height ?? 0)
        let top = max(min(rowTop + Self.topInset, screen.maxY), screen.minY + tallest)
        panel.place(topLeft: NSPoint(x: x, y: top))
        panel.orderFront(nil)
    }

    func hide() {
        hideHistory()
        panel.orderOut(nil)
        hostingView.isTracking = false
        topProcesses?.stop()
    }

    private func showHistory() {
        guard panel.isVisible, let historyPanel, !historyPanel.isVisible else { return }
        historyFeeds.forEach { $0.start() }
        historyHostingView?.isTracking = true
        placeHistory()
        historyPanel.orderFront(nil)
    }

    func hideHistory() {
        guard let historyPanel, historyPanel.isVisible else { return }
        historyPanel.orderOut(nil)
        historyHostingView?.isTracking = false
        historyFeeds.forEach { $0.stop() }
    }

    /// Beyond the stats panel on the outer side, tops aligned.
    private func placeHistory() {
        guard let historyPanel, let historyHostingView else { return }
        let width = historyHostingView.frame.width
        let stats = panel.frame
        let x = opensLeft ? stats.minX - Self.gap - width : stats.maxX + Self.gap
        historyPanel.place(topLeft: NSPoint(x: x, y: stats.maxY))
    }
}
