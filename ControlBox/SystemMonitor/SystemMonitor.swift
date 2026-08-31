import Foundation
import Combine

// Central polling engine. Owns every collector, ticks them on a background
// queue, and publishes an immutable snapshot (plus short history buffers for
// sparklines) to the main thread for the UI.
//
// Contract each collector must satisfy:
//   final class XMonitor { init(); func sample() -> XSample }
// Rate-based collectors (network, disk) track their own previous readings and
// return per-second rates.
final class SystemMonitor: ObservableObject {
    static let shared = SystemMonitor()

    @Published private(set) var snapshot = SystemSnapshot()

    // Ring buffers (oldest first) for sparklines. CPU/GPU/mem are 0...1
    // fractions; network/disk are bytes-per-second.
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var gpuHistory: [Double] = []
    @Published private(set) var memHistory: [Double] = []
    @Published private(set) var netUpHistory: [Double] = []
    @Published private(set) var netDownHistory: [Double] = []
    @Published private(set) var diskReadHistory: [Double] = []
    @Published private(set) var diskWriteHistory: [Double] = []

    let historyLength = 60
    var interval: TimeInterval = 1.0

    private let cpu = CPUMonitor()
    private let gpu = GPUMonitor()
    private let memory = MemoryMonitor()
    private let network = NetworkMonitor()
    private let disk = DiskMonitor()
    private let sensors = SensorMonitor()
    private let power = PowerMonitor()

    private let queue = DispatchQueue(label: "com.local.top.monitor", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var tick: UInt64 = 0

    // Slow-moving metrics are throttled to reduce overhead; cache last value.
    private var lastSensors = SensorSample()
    private var lastPower = PowerSample()

    private init() {}

    func start() {
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 0.15, repeating: interval, leeway: .milliseconds(100))
        t.setEventHandler { [weak self] in self?.poll() }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func poll() {
        var snap = SystemSnapshot()
        snap.cpu = cpu.sample()
        snap.gpu = gpu.sample()
        snap.memory = memory.sample()
        snap.network = network.sample()
        snap.disk = disk.sample()

        // Sensors are relatively expensive (SMC round-trips): every 3s.
        if tick % 3 == 0 { lastSensors = sensors.sample() }
        snap.sensors = lastSensors
        // Battery changes slowly: every 5s.
        if tick % 5 == 0 { lastPower = power.sample() }
        snap.power = lastPower
        snap.date = Date()
        tick &+= 1

        let cpuV = snap.cpu.totalUsage
        let gpuV = snap.gpu.utilization
        let memV = snap.memory.total > 0 ? Double(snap.memory.used) / Double(snap.memory.total) : 0
        let up = snap.network.upBytesPerSec
        let down = snap.network.downBytesPerSec
        let dr = snap.disk.readBytesPerSec
        let dw = snap.disk.writeBytesPerSec

        DispatchQueue.main.async {
            self.snapshot = snap
            self.push(&self.cpuHistory, cpuV)
            self.push(&self.gpuHistory, gpuV)
            self.push(&self.memHistory, memV)
            self.push(&self.netUpHistory, up)
            self.push(&self.netDownHistory, down)
            self.push(&self.diskReadHistory, dr)
            self.push(&self.diskWriteHistory, dw)
        }
    }

    private func push(_ arr: inout [Double], _ v: Double) {
        arr.append(v)
        if arr.count > historyLength {
            arr.removeFirst(arr.count - historyLength)
        }
    }
}
