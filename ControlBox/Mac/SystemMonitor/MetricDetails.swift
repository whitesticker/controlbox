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

    /// Addressed interfaces first, then Wi-Fi / Ethernet even when
    /// disconnected, so idle tunnels are what folds into "+N more".
    private var listedInterfaces: [NetworkInterfaceSample] {
        func rank(_ iface: NetworkInterfaceSample) -> Int {
            if !iface.ipv4.isEmpty { return 0 }
            return Self.isPhysical(iface) ? 1 : 2
        }
        return network.interfaces.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
    }

    private static func isPhysical(_ iface: NetworkInterfaceSample) -> Bool {
        iface.kind == .wifi || iface.kind == .ethernet
    }

    var body: some View {
        DetailPanel {
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
            SlotList(items: listedInterfaces, slots: 6, slotHeight: 26, spacing: 2) { iface in
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
                        if iface.ipv4.isEmpty && Self.isPhysical(iface) {
                            Text("Not connected").font(.system(size: 8.5)).foregroundColor(.secondary)
                        } else {
                            CopyableIPText(ip: iface.ipv4.isEmpty ? "—" : iface.ipv4)
                        }
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
                format: { Fmt.speed($0) }
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

    var body: some View {
        DetailPanel {
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
                format: { Fmt.speed($0) }
            )
        }
    }
}

/// Full sensor list (the compact row only shows CPU/GPU highlights),
/// sectioned by `SensorGroup` in physical order, hottest first within each.
/// Empty groups are hidden; the set of groups is fixed per Mac, so the
/// submenu keeps one height. Safe on demand; some Macs expose ~220 SMC keys.
///
/// Each section (power, fans, one temperature group) is a hover target:
/// hovering it calls `onFocus`, and the history panel charts that section.
/// The section being charted keeps a highlight until another is hovered.
struct SensorsDetail: View {
    static let width: CGFloat = 420
    let sensors: SensorSample
    var focused: HistoryMetric?
    var onFocus: ((HistoryMetric) -> Void)?

    private var groups: [(group: SensorGroup, temps: [TemperatureSample])] {
        let byGroup = Dictionary(grouping: sensors.temperatures) { SensorGroup.of($0.label) }
        return SensorGroup.allCases.compactMap { group in
            guard let temps = byGroup[group], !temps.isEmpty else { return nil }
            return (group, temps.sorted { $0.celsius > $1.celsius })
        }
    }

    private func heatColor(_ celsius: Double) -> Color {
        if celsius < 45 { return DashColors.statusGood }
        if celsius < 65 { return DashColors.statusWarning }
        return DashColors.statusCritical
    }

    var body: some View {
        let groups = groups
        let hasPower = sensors.systemPower > 0
        DetailPanel(width: Self.width) {
            if sensors.fans.isEmpty && groups.isEmpty && !hasPower {
                Text("No sensor data").font(DashStyle.labelFont).foregroundColor(.secondary)
            }
            if hasPower {
                section(.power) {
                    Text("Power").font(.system(size: 9, weight: .semibold)).foregroundColor(.secondary)
                    StatRow(label: "System total", value: Fmt.watts(sensors.systemPower))
                }
            }
            if !sensors.fans.isEmpty {
                if hasPower {
                    Divider()
                }
                section(.fans) {
                    Text("Fans").font(.system(size: 9, weight: .semibold)).foregroundColor(.secondary)
                    ForEach(Array(sensors.fans.enumerated()), id: \.offset) { _, f in
                        StatRow(label: f.label, value: Fmt.rpm(f.rpm))
                    }
                }
            }
            ForEach(Array(groups.enumerated()), id: \.offset) { index, entry in
                if index > 0 || !sensors.fans.isEmpty || hasPower {
                    Divider()
                }
                section(.sensorGroup(entry.group)) {
                    groupHeader(entry.group, temps: entry.temps)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 3) {
                        ForEach(Array(entry.temps.enumerated()), id: \.offset) { _, t in
                            tile(t)
                        }
                    }
                }
            }
        }
    }

    /// The highlight and hover area reach 4 pt past the content, so the
    /// layout is the same as without sections.
    private func section<Content: View>(
        _ metric: HistoryMetric,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.primary.opacity(focused == metric ? 0.07 : 0))
                .padding(-4)
        )
        .contentShape(Rectangle().inset(by: -4))
        .onHover { inside in
            if inside { onFocus?(metric) }
        }
    }

    private func groupHeader(_ group: SensorGroup, temps: [TemperatureSample]) -> some View {
        HStack {
            Text("\(group.title) (\(temps.count))")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
            Spacer()
            if let hottest = temps.first {
                Text("max \(Fmt.temp(hottest.celsius))")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(heatColor(hottest.celsius))
                    .monospacedDigit()
            }
        }
    }

    /// Name and temperature on one line; "°" only, since the group header
    /// already says "°C".
    private func tile(_ t: TemperatureSample) -> some View {
        HStack(spacing: 3) {
            Text(SensorNames.shortName(for: t.label))
                .font(.system(size: 8))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            Text(String(format: "%.0f°", t.celsius))
                .font(.system(size: 9.5, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(heatColor(t.celsius).opacity(0.22))
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
