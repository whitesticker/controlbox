import SwiftUI
import AppKit

private let menuRowWidth: CGFloat = 300

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

    private var combinedString: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm:ss a · EEE, MMM d"
        return f.string(from: monitor.snapshot.date)
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

            Text(String(format: "Load %.1f %.1f %.1f", cpu.load1, cpu.load5, cpu.load15))
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
    }
}

struct CPUDetailStandalone: View {
    @EnvironmentObject var monitor: SystemMonitor
    var body: some View {
        CPUDetail(cpu: monitor.snapshot.cpu, history: monitor.cpuHistory)
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
        GPUDetail(gpu: monitor.snapshot.gpu, history: monitor.gpuHistory)
    }
}

struct MemoryRow: View {
    @EnvironmentObject var monitor: SystemMonitor

    private var pressureColor: Color {
        let memory = monitor.snapshot.memory
        if memory.pressure < 0.6 { return DashColors.statusGood }
        if memory.pressure < 0.8 { return DashColors.statusWarning }
        return DashColors.statusCritical
    }

    var body: some View {
        let memory = monitor.snapshot.memory
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
        let memory = monitor.snapshot.memory
        let pressureColor: Color = memory.pressure < 0.6 ? DashColors.statusGood
            : memory.pressure < 0.8 ? DashColors.statusWarning : DashColors.statusCritical
        MemoryDetail(memory: memory, history: monitor.memHistory, pressureColor: pressureColor)
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

            CopyableIPText(
                prefix: "\(network.primaryInterface.isEmpty ? "—" : network.primaryInterface) · ",
                ip: network.primaryIP.isEmpty ? "—" : network.primaryIP,
                font: .system(size: 9)
            )
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
            if disk.volumes.isEmpty {
                Text("No volumes found")
                    .font(DashStyle.labelFont)
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(topVolumes.enumerated()), id: \.offset) { _, vol in
                    VolumeRow(volume: vol)
                }
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
        DiskDetail(
            disk: monitor.snapshot.disk,
            readHistory: monitor.diskReadHistory,
            writeHistory: monitor.diskWriteHistory
        )
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
                HStack {
                    if sensors.cpuTemp > 0 {
                        HighlightStat(label: "CPU", value: Fmt.temp(sensors.cpuTemp))
                    }
                    if sensors.gpuTemp > 0 {
                        HighlightStat(label: "GPU", value: Fmt.temp(sensors.gpuTemp))
                    }
                    ForEach(Array(sensors.fans.enumerated()), id: \.offset) { _, f in
                        HighlightStat(label: f.label, value: Fmt.rpm(f.rpm))
                    }
                    Spacer(minLength: 0)
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
    var body: some View {
        SensorsDetail(sensors: monitor.snapshot.sensors)
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

// MARK: - Detail submenu

/// Owns one section's cascading detail submenu: a custom NSHostingView
/// whose frame is refined to the SwiftUI content's real size right before
/// display (`menuWillOpen`), exactly like the top-level menu's own sizing
/// fix -- otherwise the content gets clipped top and bottom, since SwiftUI
/// hasn't laid the view out yet at construction time. The leading
/// separator absorbs NSMenu's own top-inset chrome for the same reason.
///
/// `menuWillOpen` alone isn't quite enough, though: the very first (and
/// sometimes second) time a given submenu actually opens, its hosting view
/// has never been part of any real window before, so even `menuWillOpen`'s
/// `fittingSize` read can come back wrong that one time -- matching the
/// reported "crops top/bottom on the first click or two" bug. `warmUp()`
/// forces one real layout pass at construction time (via a throwaway
/// offscreen window) so `fittingSize` is already trustworthy before the
/// menu is ever shown, not just from the second open onward.
final class DetailSubmenu: NSObject, NSMenuDelegate {
    let menu = NSMenu()
    private let hostingView: NSHostingView<AnyView>

    init<Content: View>(@ViewBuilder content: () -> Content) {
        hostingView = NSHostingView(rootView: AnyView(content()))
        hostingView.frame = NSRect(x: 0, y: 0, width: 260, height: 600)
        super.init()
        warmUp()

        menu.delegate = self
        menu.addItem(.separator())
        let item = NSMenuItem()
        item.view = hostingView
        menu.addItem(item)
    }

    private func warmUp() {
        let warmupWindow = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        warmupWindow.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        let fitting = hostingView.fittingSize
        if fitting.height > 0 {
            hostingView.frame = NSRect(origin: .zero, size: fitting)
        }
        warmupWindow.contentView = nil
    }

    func menuWillOpen(_ menu: NSMenu) {
        // Force a fresh layout pass before measuring, not just at
        // construction -- content that branches on live data (e.g. a
        // detail view's "no data yet" vs. real fallback) can otherwise
        // keep reporting a stale `fittingSize` for the first several opens.
        // See StatusItemController.menuWillOpen for the full explanation.
        hostingView.layoutSubtreeIfNeeded()
        let fitting = hostingView.fittingSize
        guard fitting.height > 0 else { return }
        hostingView.frame = NSRect(origin: .zero, size: fitting)
    }
}
