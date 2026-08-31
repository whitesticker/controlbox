import Foundation

// MARK: - Top-level snapshot
//
// One immutable snapshot of every metric at a single instant. The
// SystemMonitor produces one of these per tick and publishes it to the UI.
struct SystemSnapshot: Codable {
    var cpu = CPUSample()
    var gpu = GPUSample()
    var memory = MemorySample()
    var network = NetworkSample()
    var disk = DiskSample()
    var sensors = SensorSample()
    var power = PowerSample()
    var date = Date()
}

// MARK: - CPU
struct CPUSample: Codable {
    var totalUsage: Double = 0        // 0...1  (user + system)
    var user: Double = 0              // 0...1
    var system: Double = 0           // 0...1
    var idle: Double = 1             // 0...1
    var perCore: [Double] = []       // one entry per logical core, each 0...1
    var performanceCoreUsage: Double = 0  // 0...1 average across P-cores (Apple Silicon)
    var efficiencyCoreUsage: Double = 0   // 0...1 average across E-cores (Apple Silicon)
    var pCoreCount: Int = 0
    var eCoreCount: Int = 0
    var load1: Double = 0            // 1-minute load average
    var load5: Double = 0
    var load15: Double = 0
}

// MARK: - GPU
struct GPUSample: Codable {
    var available: Bool = false
    var name: String = ""
    var utilization: Double = 0      // 0...1 device utilization
}

// MARK: - Memory
struct MemorySample: Codable {
    var total: UInt64 = 0            // bytes of physical RAM
    var used: UInt64 = 0            // bytes considered "used" (total - free - purgeable)
    var app: UInt64 = 0            // app memory
    var wired: UInt64 = 0
    var compressed: UInt64 = 0
    var free: UInt64 = 0
    var cached: UInt64 = 0          // cached files / purgeable
    var pressure: Double = 0        // 0...1 memory pressure gauge
    var pressureLevel: Int = 1      // 1 = normal, 2 = warning, 4 = critical
    var swapUsed: UInt64 = 0
    var swapTotal: UInt64 = 0
}

// MARK: - Network
struct NetworkInterfaceSample: Codable {
    var name: String = ""
    var displayName: String = ""
    var upBytesPerSec: Double = 0
    var downBytesPerSec: Double = 0
    var ipv4: String = ""
}

struct NetworkSample: Codable {
    var upBytesPerSec: Double = 0        // aggregate over active interfaces (icon value)
    var downBytesPerSec: Double = 0
    var totalUp: UInt64 = 0              // cumulative bytes since boot
    var totalDown: UInt64 = 0
    var sessionUp: UInt64 = 0            // cumulative bytes since app launch
    var sessionDown: UInt64 = 0
    var primaryInterface: String = ""
    var primaryIP: String = ""
    var interfaces: [NetworkInterfaceSample] = []
}

// MARK: - Disk
struct DiskVolumeSample: Codable {
    var name: String = ""
    var mountPoint: String = ""
    var total: UInt64 = 0
    var free: UInt64 = 0
    var used: UInt64 = 0
    var isInternal: Bool = true
}

struct DiskSample: Codable {
    var volumes: [DiskVolumeSample] = []
    var readBytesPerSec: Double = 0
    var writeBytesPerSec: Double = 0
    var totalRead: UInt64 = 0            // cumulative bytes since boot
    var totalWrite: UInt64 = 0
}

// MARK: - Sensors
struct TemperatureSample: Codable {
    var label: String = ""
    var celsius: Double = 0
}

struct FanSample: Codable {
    var label: String = ""
    var rpm: Double = 0
    var minRPM: Double = 0
    var maxRPM: Double = 0
}

struct SensorSample: Codable {
    var temperatures: [TemperatureSample] = []
    var fans: [FanSample] = []
    var cpuTemp: Double = 0           // best-effort representative CPU die temp, °C
    var gpuTemp: Double = 0           // best-effort representative GPU temp, °C
}

// MARK: - Power / Battery
struct PowerSample: Codable {
    var hasBattery: Bool = false
    var percentage: Double = 0        // 0...1
    var isCharging: Bool = false
    var isPluggedIn: Bool = false
    var timeToEmptyMinutes: Int = -1  // -1 = unknown / calculating
    var timeToFullMinutes: Int = -1   // -1 = unknown / calculating
    var cycleCount: Int = 0
    var health: Double = 0            // maxCapacity / designCapacity, 0...1
    var powerWatts: Double = 0        // instantaneous system power draw (best effort)
    var temperature: Double = 0       // battery temperature, °C
}
