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
//
// The menu's ~15 NSHostingViews all observe this object, so `objectWillChange`
// only fires while the menu is open (`setPresenting`). While it is closed,
// ticks keep the history buffers filling and feed the menu bar icon through
// `tickSnapshot`, which does not invalidate any SwiftUI view. Ticks that
// arrive while the main thread is busy coalesce into one publish of the
// newest frame instead of queueing one render per second.
final class SystemMonitor: ObservableObject {
    static let shared = SystemMonitor()

    struct History {
        // Oldest first. CPU/GPU/mem are 0...1 fractions; network/disk are
        // bytes-per-second.
        var cpu: [Double] = []
        var gpu: [Double] = []
        var mem: [Double] = []
        var netUp: [Double] = []
        var netDown: [Double] = []
        var diskRead: [Double] = []
        var diskWrite: [Double] = []
    }

    private struct Frame {
        var snapshot: SystemSnapshot
        var history: History
    }

    private(set) var snapshot = SystemSnapshot()
    private(set) var history = History()

    var cpuHistory: [Double] { history.cpu }
    var gpuHistory: [Double] { history.gpu }
    var memHistory: [Double] { history.mem }
    var netUpHistory: [Double] { history.netUp }
    var netDownHistory: [Double] { history.netDown }
    var diskReadHistory: [Double] { history.diskRead }
    var diskWriteHistory: [Double] { history.diskWrite }

    /// Every tick, on the main thread, whether or not the menu is open.
    let tickSnapshot = CurrentValueSubject<SystemSnapshot?, Never>(nil)

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

    // Queue-owned.
    private var pollHistory = History()
    private var lastSensors = SensorSample()
    private var lastPower = PowerSample()

    // Guarded by `lock`.
    private let lock = NSLock()
    private var latestFrame: Frame?
    private var mainDrainPending = false
    private var presentingForPoll = false
    private var refreshSlowMetrics = false

    // Main-thread only.
    private var isPresenting = false

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

    /// Main thread. Call with `true` right before the menu measures its rows
    /// so they lay out against current data, and `false` once it closes.
    func setPresenting(_ presenting: Bool) {
        guard presenting != isPresenting else { return }
        isPresenting = presenting
        lock.lock()
        presentingForPoll = presenting
        if presenting { refreshSlowMetrics = true }
        let frame = latestFrame
        lock.unlock()
        if presenting, let frame { publish(frame) }
    }

    private func poll() {
        lock.lock()
        let presenting = presentingForPoll
        let forceSlow = refreshSlowMetrics
        refreshSlowMetrics = false
        lock.unlock()

        var snap = SystemSnapshot()
        snap.cpu = cpu.sample()
        snap.gpu = gpu.sample()
        snap.memory = memory.sample()
        snap.network = network.sample()
        snap.disk = disk.sample()

        // Sensors (SMC round-trips) and battery have no sparkline, so they
        // slow down further while nobody is looking.
        let sensorsEvery: UInt64 = presenting ? 3 : 10
        let powerEvery: UInt64 = presenting ? 5 : 30
        let sensorsFresh = forceSlow || tick % sensorsEvery == 0
        if sensorsFresh { lastSensors = sensors.sample() }
        snap.sensors = lastSensors
        if forceSlow || tick % powerEvery == 0 { lastPower = power.sample() }
        snap.power = lastPower
        snap.date = Date()
        tick &+= 1

        recordHistory(snap, sensorsFresh: sensorsFresh)

        push(&pollHistory.cpu, snap.cpu.totalUsage)
        push(&pollHistory.gpu, snap.gpu.utilization)
        push(&pollHistory.mem, snap.memory.total > 0 ? Double(snap.memory.used) / Double(snap.memory.total) : 0)
        push(&pollHistory.netUp, snap.network.upBytesPerSec)
        push(&pollHistory.netDown, snap.network.downBytesPerSec)
        push(&pollHistory.diskRead, snap.disk.readBytesPerSec)
        push(&pollHistory.diskWrite, snap.disk.writeBytesPerSec)

        lock.lock()
        latestFrame = Frame(snapshot: snap, history: pollHistory)
        let needsDrain = !mainDrainPending
        mainDrainPending = true
        lock.unlock()

        if needsDrain {
            DispatchQueue.main.async { [weak self] in self?.drain() }
        }
    }

    private func drain() {
        lock.lock()
        let frame = latestFrame
        mainDrainPending = false
        lock.unlock()
        guard let frame else { return }

        tickSnapshot.send(frame.snapshot)
        if isPresenting { publish(frame) }
    }

    private func publish(_ frame: Frame) {
        objectWillChange.send()
        snapshot = frame.snapshot
        history = frame.history
    }

    /// Feeds the history submenus. Temperatures are each group's hottest
    /// sensor, recorded only on ticks that actually read the SMC.
    private func recordHistory(_ snap: SystemSnapshot, sensorsFresh: Bool) {
        let store = HistoryStore.shared
        let date = snap.date
        store.record("cpu", name: "CPU", value: snap.cpu.totalUsage, at: date)
        if snap.gpu.available {
            store.record("gpu", name: "GPU", value: snap.gpu.utilization, at: date)
        }
        store.record("memory", name: "Pressure", value: snap.memory.pressure, at: date)
        store.record("net.down", name: "Download", value: snap.network.downBytesPerSec, at: date)
        store.record("net.up", name: "Upload", value: snap.network.upBytesPerSec, at: date)
        store.record("disk.read", name: "Read", value: snap.disk.readBytesPerSec, at: date)
        store.record("disk.write", name: "Write", value: snap.disk.writeBytesPerSec, at: date)

        guard sensorsFresh else { return }
        var hottest: [SensorGroup: Double] = [:]
        for temp in snap.sensors.temperatures where temp.celsius > 0 {
            let group = SensorGroup.of(temp.label)
            hottest[group] = max(hottest[group] ?? 0, temp.celsius)
        }
        for (group, celsius) in hottest {
            store.record(HistoryStore.temperatureID(group), name: group.shortTitle, value: celsius, at: date)
        }
        if snap.sensors.systemPower > 0 {
            store.record("power.system", name: "System", value: snap.sensors.systemPower, at: date)
        }
        for (index, fan) in snap.sensors.fans.enumerated() {
            store.record("fan.\(index)", name: fan.label.isEmpty ? "Fan \(index)" : fan.label, value: fan.rpm, at: date)
        }
    }

    private func push(_ arr: inout [Double], _ v: Double) {
        arr.append(v)
        if arr.count > historyLength {
            arr.removeFirst(arr.count - historyLength)
        }
    }
}
