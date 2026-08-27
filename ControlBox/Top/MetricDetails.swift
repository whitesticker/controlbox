import SwiftUI

/// Cascading submenu content for each metric row. Compact cards live in
/// MenuRows.swift; these are the expanded views behind `.submenu`.

struct CPUDetail: View {
    let cpu: CPUSample
    let history: [Double]

    var body: some View {
        DetailPanel(title: "CPU", systemImage: "cpu") {
            HStack {
                StatRow(label: "Total", value: Fmt.percent(cpu.totalUsage))
            }
            StatRow(label: "User", value: Fmt.percent(cpu.user))
            StatRow(label: "System", value: Fmt.percent(cpu.system))
            StatRow(label: "Idle", value: Fmt.percent(cpu.idle))
            Sparkline(values: history, maxValue: 1.0, color: DashColors.cpuLine)
                .frame(height: 40)
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
            TopProcessList(
                sample: { ProcessMonitor().topCPUProcesses() },
                format: { String(format: "%.0f%%", $0) }
            )
        }
    }
}

struct GPUDetail: View {
    let gpu: GPUSample
    let history: [Double]

    var body: some View {
        DetailPanel(title: "GPU", systemImage: "cube.transparent") {
            if gpu.available {
                StatRow(label: "Name", value: gpu.name.isEmpty ? "GPU" : gpu.name)
                StatRow(label: "Utilization", value: Fmt.percent(gpu.utilization))
                Sparkline(values: history, maxValue: 1.0, color: DashColors.gpuLine)
                    .frame(height: 40)
            } else {
                Text("No GPU data available").font(DashStyle.labelFont).foregroundColor(.secondary)
            }
        }
    }
}

struct MemoryDetail: View {
    let memory: MemorySample
    let history: [Double]
    let pressureColor: Color

    var body: some View {
        DetailPanel(title: "Memory", systemImage: "memorychip") {
            StatRow(label: "Used", value: Fmt.bytesBinary(memory.used))
            StatRow(label: "Total", value: Fmt.bytesBinary(memory.total))
            StatRow(label: "Pressure", value: Fmt.percent(memory.pressure), valueColor: pressureColor)
            Sparkline(values: history, maxValue: 1.0, color: pressureColor)
                .frame(height: 40)
            Divider()
            StatRow(label: "App", value: Fmt.bytesBinary(memory.app))
            StatRow(label: "Wired", value: Fmt.bytesBinary(memory.wired))
            StatRow(label: "Compressed", value: Fmt.bytesBinary(memory.compressed))
            StatRow(label: "Cached", value: Fmt.bytesBinary(memory.cached))
            StatRow(label: "Free", value: Fmt.bytesBinary(memory.free))
            Divider()
            StatRow(label: "Swap used", value: Fmt.bytesBinary(memory.swapUsed))
            StatRow(label: "Swap total", value: Fmt.bytesBinary(memory.swapTotal))
            Divider()
            TopProcessList(
                sample: { ProcessMonitor().topMemoryProcesses() },
                format: { Fmt.bytesBinary($0) }
            )
        }
    }
}

struct NetworkDetail: View {
    let network: NetworkSample

    var body: some View {
        DetailPanel(title: "Network", systemImage: "network") {
            StatRow(label: "Download", value: Fmt.speed(network.downBytesPerSec))
            StatRow(label: "Upload", value: Fmt.speed(network.upBytesPerSec))
            Divider()
            StatRow(label: "Session ↓", value: Fmt.bytes(network.sessionDown))
            StatRow(label: "Session ↑", value: Fmt.bytes(network.sessionUp))
            StatRow(label: "Total ↓ (boot)", value: Fmt.bytes(network.totalDown))
            StatRow(label: "Total ↑ (boot)", value: Fmt.bytes(network.totalUp))
            if !network.interfaces.isEmpty {
                Divider()
                Text("Interfaces").font(.system(size: 9, weight: .semibold)).foregroundColor(.secondary)
                ForEach(Array(network.interfaces.enumerated()), id: \.offset) { _, iface in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(iface.name).font(.system(size: 10, weight: .medium))
                            Spacer()
                            CopyableIPText(ip: iface.ipv4.isEmpty ? "—" : iface.ipv4)
                        }
                        Text("↓\(Fmt.speed(iface.downBytesPerSec)) ↑\(Fmt.speed(iface.upBytesPerSec))")
                            .font(.system(size: 8.5))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            Divider()
            TopProcessList(
                label: "Top processes (total data)",
                sample: { ProcessMonitor().topNetworkProcesses() },
                format: { Fmt.bytes($0) }
            )
        }
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
    let readHistory: [Double]
    let writeHistory: [Double]

    var body: some View {
        DetailPanel(title: "Disk", systemImage: "internaldrive") {
            StatRow(label: "Read", value: Fmt.speed(disk.readBytesPerSec))
            StatRow(label: "Write", value: Fmt.speed(disk.writeBytesPerSec))
            HStack(spacing: 8) {
                Sparkline(values: readHistory, color: DashColors.diskRead).frame(height: 30)
                Sparkline(values: writeHistory, color: DashColors.diskWrite).frame(height: 30)
            }
            if disk.volumes.isEmpty {
                Text("No volumes found").font(DashStyle.labelFont).foregroundColor(.secondary)
            } else {
                Divider()
                Text("Volumes (\(disk.volumes.count))").font(.system(size: 9, weight: .semibold)).foregroundColor(.secondary)
                ForEach(Array(disk.volumes.enumerated()), id: \.offset) { _, vol in
                    VolumeRow(volume: vol)
                }
            }
            Divider()
            TopProcessList(
                sample: { ProcessMonitor().topDiskProcesses() },
                format: { Fmt.speed($0) }
            )
        }
    }
}

/// Full sensor list (the compact row only shows CPU/GPU highlights). Safe
/// on demand; some Macs expose ~186 SMC keys.
struct SensorsDetail: View {
    let sensors: SensorSample

    private var sortedTemps: [TemperatureSample] {
        sensors.temperatures.sorted { $0.celsius > $1.celsius }
    }

    private func heatColor(_ celsius: Double) -> Color {
        if celsius < 45 { return DashColors.statusGood }
        if celsius < 65 { return DashColors.statusWarning }
        return DashColors.statusCritical
    }

    var body: some View {
        DetailPanel(title: "Sensors", systemImage: "thermometer.medium", width: 420) {
            if sensors.fans.isEmpty && sortedTemps.isEmpty {
                Text("No sensor data").font(DashStyle.labelFont).foregroundColor(.secondary)
            }
            if !sensors.fans.isEmpty {
                Text("Fans").font(.system(size: 9, weight: .semibold)).foregroundColor(.secondary)
                ForEach(Array(sensors.fans.enumerated()), id: \.offset) { _, f in
                    StatRow(label: f.label, value: Fmt.rpm(f.rpm))
                }
                Divider()
            }
            if !sortedTemps.isEmpty {
                Text("Temperatures (\(sortedTemps.count))").font(.system(size: 9, weight: .semibold)).foregroundColor(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8), spacing: 4) {
                    ForEach(Array(sortedTemps.enumerated()), id: \.offset) { _, t in
                        VStack(spacing: 1) {
                            Text(SensorNames.displayName(for: t.label))
                                .font(.system(size: 7.5))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(Fmt.temp(t.celsius))
                                .font(.system(size: 10.5, weight: .semibold))
                                .monospacedDigit()
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 2)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(heatColor(t.celsius).opacity(0.22))
                        )
                    }
                }
            }
        }
    }
}

struct HighlightStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 8.5))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
        }
        .padding(.trailing, 10)
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
                Divider()
                // macOS has no public per-process energy-impact API; CPU
                // usage is the closest proxy for battery drain.
                TopProcessList(
                    label: "Heaviest CPU users (energy proxy)",
                    sample: { ProcessMonitor().topCPUProcesses() },
                    format: { String(format: "%.0f%%", $0) }
                )
            } else {
                Text("On AC power / no battery").font(DashStyle.labelFont).foregroundColor(.secondary)
            }
        }
    }
}
