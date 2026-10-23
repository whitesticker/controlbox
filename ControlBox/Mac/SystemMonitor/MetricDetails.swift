import SwiftUI

/// Cascading submenu content for each metric row. Compact cards live in
/// MenuRows.swift; these are the expanded views behind `.submenu`. Title and
/// graph come from the history panel beside each (except Battery).

struct CPUDetail: View {
    let cpu: CPUSample

    private static let bootFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter
    }()

    var body: some View {
        DetailPanel {
            HStack {
                StatRow(label: "Total", value: Fmt.percent(cpu.totalUsage))
            }
            StatRow(label: "User", value: Fmt.percent(cpu.user))
            StatRow(label: "System", value: Fmt.percent(cpu.system))
            StatRow(label: "Idle", value: Fmt.percent(cpu.idle))
            if cpu.pCoreCount > 0 {
                Divider()
                StatRow(label: "Performance cores", value: "\(cpu.pCoreCount)")
                StatRow(label: "Efficiency cores", value: "\(cpu.eCoreCount)")
                StatRow(label: "P-core usage", value: Fmt.percent(cpu.performanceCoreUsage))
                StatRow(label: "E-core usage", value: Fmt.percent(cpu.efficiencyCoreUsage))
            }
            if !cpu.perCore.isEmpty {
                Divider()
                Text("Per-core").font(.system(size: 9, weight: .semibold)).foregroundColor(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8), spacing: 6) {
                    ForEach(Array(cpu.perCore.enumerated()), id: \.offset) { i, v in
                        VStack(spacing: 2) {
                            CoreBar(fraction: v, width: 10)
                                .frame(height: 28)
                            Text("\(i)")
                                .font(.system(size: 7))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            Divider()
            StatRow(label: "Load avg (1m)", value: String(format: "%.2f", cpu.load1))
            StatRow(label: "Load avg (5m)", value: String(format: "%.2f", cpu.load5))
            StatRow(label: "Load avg (15m)", value: String(format: "%.2f", cpu.load15))
            Divider()
            StatRow(label: "Uptime", value: Fmt.uptime(cpu.uptime))
            StatRow(label: "Booted", value: cpu.uptime > 0 ? Self.bootFormatter.string(from: Date(timeIntervalSinceNow: -cpu.uptime)) : "—")
            Divider()
            TopProcessList(
                format: { String(format: "%.0f%%", $0) }
            )
        }
    }
}

struct GPUDetail: View {
    let gpu: GPUSample

    var body: some View {
        DetailPanel {
            if gpu.available {
                StatRow(label: "Name", value: gpu.name.isEmpty ? "GPU" : gpu.name)
                StatRow(label: "Utilization", value: Fmt.percent(gpu.utilization))
            } else {
                Text("No GPU data available").font(DashStyle.labelFont).foregroundColor(.secondary)
            }
        }
    }
}

extension MemorySample {
    /// The kernel's level, as Activity Monitor colors its pressure graph.
    var pressureColor: Color {
        switch pressureLevel {
        case 4: return DashColors.statusCritical
        case 2: return DashColors.statusWarning
        default: return DashColors.statusGood
        }
    }

    var pressureTitle: String {
        switch pressureLevel {
        case 4: return "Critical"
        case 2: return "Warning"
        default: return "Normal"
        }
    }
}

struct MemoryDetail: View {
    let memory: MemorySample

    var body: some View {
        DetailPanel {
            MemoryRing(memory: memory)
            Divider()
            StatRow(
                label: "Pressure",
                value: "\(Fmt.percent(memory.pressure)) · \(memory.pressureTitle)",
                valueColor: memory.pressureColor
            )
            StatRow(label: "Swap used", value: "\(Fmt.bytesBinary(memory.swapUsed)) of \(Fmt.bytesBinary(memory.swapTotal))")
            Divider()
            TopProcessList(
                format: { Fmt.bytesBinary($0) }
            )
        }
    }
}

/// Where physical RAM is going, as a ring: App, Wired and Compressed are
/// "used" (the center figure); Cached can be dropped at any time, and Free
/// is unused. The ring is the sum of the five, which runs a little under
/// total RAM (pages the kernel does not count in any of them).
struct MemoryRing: View {
    let memory: MemorySample

    private var segments: [(label: String, bytes: UInt64, color: Color)] {
        [
            ("App", memory.app, .blue),
            ("Wired", memory.wired, .orange),
            ("Compressed", memory.compressed, .purple),
            ("Cached", memory.cached, .teal),
            ("Free", memory.free, Color.secondary.opacity(0.35)),
        ]
    }

    var body: some View {
        let segments = segments
        let sum = Double(segments.reduce(0) { $0 + $1.bytes })
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.06), lineWidth: 11)
                if sum > 0 {
                    ForEach(Array(arcs(segments, sum: sum).enumerated()), id: \.offset) { _, arc in
                        Circle()
                            .trim(from: arc.start, to: arc.end)
                            .stroke(arc.color, style: StrokeStyle(lineWidth: 11, lineCap: .butt))
                    }
                    .rotationEffect(.degrees(-90))
                }
                VStack(spacing: 0) {
                    Text(Fmt.bytesBinary(memory.used))
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                    Text("of \(Fmt.bytesBinary(memory.total))")
                        .font(.system(size: 8.5))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }
            .frame(width: 82, height: 82)
            .padding(5.5)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(segments, id: \.label) { segment in
                    HStack(spacing: 5) {
                        Circle().fill(segment.color).frame(width: 7, height: 7)
                        Text(segment.label)
                            .font(DashStyle.labelFont)
                            .foregroundColor(.secondary)
                        Spacer(minLength: 6)
                        Text(Fmt.bytesBinary(segment.bytes))
                            .font(DashStyle.valueFont)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    /// Clockwise from 12 o'clock with a hairline gap between segments.
    private func arcs(
        _ segments: [(label: String, bytes: UInt64, color: Color)],
        sum: Double
    ) -> [(start: CGFloat, end: CGFloat, color: Color)] {
        var start = 0.0
        return segments.compactMap { segment in
            let fraction = Double(segment.bytes) / sum
            defer { start += fraction }
            guard fraction > 0.004 else { return nil }
            return (CGFloat(start + 0.002), CGFloat(start + fraction - 0.002), segment.color)
        }
    }
}

struct NetworkDetail: View {
    let network: NetworkSample
    @ObservedObject private var publicIP = PublicIPLookup.shared

    /// Active (has an IPv4 address) only, primary first. The monitor keeps
    /// the idle ones because their traffic still counts toward the totals.
    private var listedInterfaces: [NetworkInterfaceSample] {
        func rank(_ iface: NetworkInterfaceSample) -> Int {
            iface.name == network.primaryInterface ? 0 : 1
        }
        return network.interfaces
            .filter { !$0.ipv4.isEmpty }
            .enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
    }

    private static let maxInterfaceSlots = 6
    /// Room for the two speed columns in Top processes.
    static let width: CGFloat = 310

    var body: some View {
        DetailPanel(width: Self.width) {
            StatRow(label: "Download", value: Fmt.speed(network.downBytesPerSec))
            StatRow(label: "Upload", value: Fmt.speed(network.upBytesPerSec))
            Divider()
            publicIPRow
            Divider()
            StatRow(label: "Session ↓", value: Fmt.bytes(network.sessionDown))
            StatRow(label: "Session ↑", value: Fmt.bytes(network.sessionUp))
            StatRow(label: "Total ↓ (boot)", value: Fmt.bytes(network.totalDown))
            StatRow(label: "Total ↑ (boot)", value: Fmt.bytes(network.totalUp))
            Divider()
            Text("Interfaces").font(.system(size: 9, weight: .semibold)).foregroundColor(.secondary)
            let interfaces = listedInterfaces
            SlotList(
                items: interfaces,
                slots: min(max(interfaces.count, 1), Self.maxInterfaceSlots),
                slotHeight: 26,
                spacing: 2,
                emptyText: "No active interfaces"
            ) { iface in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
                        Image(systemName: iface.kind.systemImage)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 13)
                        Text(iface.displayName).font(.system(size: 10, weight: .medium))
                        if iface.displayName != iface.name {
                            Text(iface.name).font(.system(size: 8.5)).foregroundColor(.secondary)
                        }
                        if iface.name == network.primaryInterface {
                            Text("Primary")
                                .font(.system(size: 7.5, weight: .semibold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.primary.opacity(0.08)))
                        }
                        Spacer()
                        CopyableIPText(ip: iface.ipv4)
                    }
                    .lineLimit(1)
                    Text("↓\(Fmt.speed(iface.downBytesPerSec)) ↑\(Fmt.speed(iface.upBytesPerSec))")
                        .font(.system(size: 8.5))
                        .foregroundColor(.secondary)
                        .padding(.leading, 17)
                }
            }
            Divider()
            TopProcessList(
                label: "Top processes (last 4 s)",
                format: { Fmt.speed($0) },
                split: .init(read: ("↓", DashColors.download), write: ("↑", DashColors.upload), writeFirst: true)
            )
        }
        .onChange(of: "\(network.primaryInterface)|\(network.primaryIP)") { _, key in
            publicIP.networkChanged(key)
        }
    }

    /// Looked up only on click (see `PublicIPLookup`).
    private var publicIPRow: some View {
        HStack(spacing: 4) {
            Text("Public IP")
                .font(DashStyle.labelFont)
                .foregroundColor(.secondary)
            Spacer(minLength: 8)
            switch publicIP.state {
            case .idle:
                Button("Show") { publicIP.lookUp() }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10, weight: .medium))
            case .loading:
                ProgressView().controlSize(.mini)
            case .found(let ip):
                CopyableIPText(ip: ip, font: DashStyle.valueFont)
                refreshButton
            case .failed:
                Text("Couldn't reach ipv4.icanhazip.com")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                refreshButton
            }
        }
        .frame(height: 16)
    }

    private var refreshButton: some View {
        Button { publicIP.lookUp() } label: {
            Image(systemName: "arrow.clockwise").font(.system(size: 9, weight: .semibold))
        }
        .buttonStyle(.borderless)
        .help("Look up again")
    }
}

struct VolumeRow: View {
    let volume: DiskVolumeSample

    private var fraction: Double {
        volume.total > 0 ? Double(volume.used) / Double(volume.total) : 0
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: volume.isInternal ? "internaldrive" : "externaldrive")
                .font(.system(size: 8.5))
                .foregroundColor(.secondary)
            Text(volume.name.isEmpty ? "Volume" : volume.name)
                .font(.system(size: 9.5, weight: .medium))
                .lineLimit(1)
                .frame(width: 78, alignment: .leading)
            UsageBar(fraction: fraction, height: 5)
            Text("\(Fmt.bytes(volume.used))/\(Fmt.bytes(volume.total))")
                .font(.system(size: 8.5))
                .foregroundColor(.secondary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.vertical, 1)
    }
}

struct DiskDetail: View {
    let disk: DiskSample
    /// Room for the two speed columns in Top processes.
    static let width: CGFloat = 310

    var body: some View {
        DetailPanel(width: Self.width) {
            StatRow(label: "Read", value: Fmt.speed(disk.readBytesPerSec))
            StatRow(label: "Write", value: Fmt.speed(disk.writeBytesPerSec))
            Divider()
            Text("Volumes (\(disk.volumes.count))").font(.system(size: 9, weight: .semibold)).foregroundColor(.secondary)
            SlotList(items: disk.volumes, slots: 4, slotHeight: 16, emptyText: "No volumes found") { vol in
                VolumeRow(volume: vol)
            }
            Divider()
            TopProcessList(
                label: "Top processes (last 10 s)",
                format: { Fmt.speed($0) },
                split: .init(read: ("R", DashColors.diskRead), write: ("W", DashColors.diskWrite))
            )
        }
    }
}

/// One row per sensor category: system power, fans, then each temperature
/// group in physical order, each with one value (watts, fastest fan,
/// hottest sensor). Hovering a row opens the history panel on that
/// category, with every sensor of it listed under the chart
/// (`SensorsHistoryDetail`). The charted row keeps a highlight while the
/// history panel is open. Empty groups are hidden; the set of groups is
/// fixed per Mac, so the submenu keeps one height.
struct SensorsDetail: View {
    static let width: CGFloat = 250
    let sensors: SensorSample
    var focused: HistoryMetric?
    var onFocus: ((HistoryMetric) -> Void)?

    var body: some View {
        let groups = SensorReadings.groups(sensors)
        let hasPower = sensors.systemPower > 0
        DetailPanel(width: Self.width) {
            if sensors.fans.isEmpty && groups.isEmpty && !hasPower {
                Text("No sensor data").font(DashStyle.labelFont).foregroundColor(.secondary)
            }
            if hasPower {
                row(.power, count: nil, value: Fmt.watts(sensors.systemPower), color: .primary)
            }
            if let fastest = sensors.fans.map(\.rpm).max() {
                row(.fans, count: sensors.fans.count, value: Fmt.rpm(fastest), color: .primary)
            }
            if (hasPower || !sensors.fans.isEmpty) && !groups.isEmpty {
                Divider().padding(.vertical, 2)
            }
            ForEach(groups, id: \.group) { entry in
                if let hottest = entry.temps.first {
                    row(
                        .sensorGroup(entry.group),
                        count: entry.temps.count,
                        value: Fmt.temp(hottest.celsius),
                        color: SensorReadings.heatColor(hottest.celsius)
                    )
                }
            }
        }
    }

    private func row(_ metric: HistoryMetric, count: Int?, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: metric.systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 14)
            Text(metric.title)
                .font(DashStyle.labelFont)
                .lineLimit(1)
            if let count {
                Text("\(count)")
                    .font(.system(size: 8.5))
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 6)
            Text(value)
                .font(DashStyle.valueFont)
                .monospacedDigit()
                .foregroundColor(color)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.primary.opacity(focused == metric ? 0.08 : 0))
        )
        .padding(.horizontal, -6)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { onFocus?(metric) }
        }
    }
}

/// Under the Sensors history chart: every sensor of the charted category.
struct SensorsHistoryDetail: View {
    @EnvironmentObject var monitor: SystemMonitor
    @ObservedObject var focus: HistoryFocus

    var body: some View {
        let sensors = monitor.snapshot.sensors
        VStack(alignment: .leading, spacing: 4) {
            switch focus.metric {
            case .power:
                header("Sensors")
                StatRow(label: "System total", value: Fmt.watts(sensors.systemPower))
            case .fans:
                header("Fans (\(sensors.fans.count))")
                ForEach(Array(sensors.fans.enumerated()), id: \.offset) { _, fan in
                    StatRow(label: fan.label, value: Fmt.rpm(fan.rpm))
                    if fan.maxRPM > 0 {
                        Text("Range \(Fmt.rpmNumber(fan.minRPM))–\(Fmt.rpmNumber(fan.maxRPM)) rpm")
                            .font(.system(size: 8.5))
                            .foregroundColor(.secondary)
                    }
                }
            case .sensorGroup(let group):
                let temps = SensorReadings.groups(sensors).first { $0.group == group }?.temps ?? []
                header("\(group.title) sensors (\(temps.count))")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 3) {
                    ForEach(Array(temps.enumerated()), id: \.offset) { _, temp in
                        SensorTile(temp: temp)
                    }
                }
            default:
                EmptyView()
            }
        }
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(.secondary)
    }
}

/// Temperature readings grouped the way the Sensors submenu shows them.
enum SensorReadings {
    /// Non-empty groups in physical order, hottest sensor first in each.
    static func groups(_ sensors: SensorSample) -> [(group: SensorGroup, temps: [TemperatureSample])] {
        let byGroup = Dictionary(grouping: sensors.temperatures) { SensorGroup.of($0.label) }
        return SensorGroup.allCases.compactMap { group in
            guard let temps = byGroup[group], !temps.isEmpty else { return nil }
            return (group, temps.sorted { $0.celsius > $1.celsius })
        }
    }

    static func heatColor(_ celsius: Double) -> Color {
        if celsius < 45 { return DashColors.statusGood }
        if celsius < 65 { return DashColors.statusWarning }
        return DashColors.statusCritical
    }
}

/// Name and temperature on one line, tinted by heat; "°" only, since the
/// header already says what is measured.
struct SensorTile: View {
    let temp: TemperatureSample

    var body: some View {
        HStack(spacing: 3) {
            Text(SensorNames.shortName(for: temp.label))
                .font(.system(size: 8.5))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            Text(String(format: "%.0f°", temp.celsius))
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 5)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(SensorReadings.heatColor(temp.celsius).opacity(0.22))
        )
    }
}

/// One equal-width column in the Sensors row. One line, scaled down if the
/// value is too wide: wrapping "1005 rpm" onto two lines changed the row's
/// height, and every live resize made the whole menu jump.
struct HighlightStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 8.5))
                .foregroundColor(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PowerDetail: View {
    let power: PowerSample

    var body: some View {
        DetailPanel(title: "Battery & Power", systemImage: "battery.100") {
            if power.hasBattery {
                StatRow(label: "Charge", value: Fmt.percent(power.percentage))
                StatRow(label: "Status", value: power.isCharging ? "Charging" : (power.isPluggedIn ? "Plugged in" : "On battery"))
                StatRow(label: "Time to full", value: power.timeToFullMinutes >= 0 ? Fmt.minutes(power.timeToFullMinutes) : "—")
                StatRow(label: "Time to empty", value: power.timeToEmptyMinutes >= 0 ? Fmt.minutes(power.timeToEmptyMinutes) : "—")
                Divider()
                StatRow(label: "Cycle count", value: "\(power.cycleCount)")
                StatRow(label: "Health", value: Fmt.percent(power.health))
                StatRow(label: "Power draw", value: Fmt.watts(power.powerWatts))
                StatRow(label: "Battery temp", value: Fmt.temp(power.temperature))
            } else {
                Text("On AC power / no battery").font(DashStyle.labelFont).foregroundColor(.secondary)
            }
            Divider()
            TopProcessList(
                label: "Energy impact",
                format: { String(format: "%.1f", $0) }
            )
        }
    }
}
