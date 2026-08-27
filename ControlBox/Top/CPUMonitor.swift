import Foundation
import Darwin

// MARK: - CPUMonitor
//
// Samples per-core CPU tick counters via host_processor_info and converts
// consecutive samples into instantaneous usage fractions (0...1). Also
// reports system load averages and, on Apple Silicon, splits per-core
// usage into performance (P) and efficiency (E) core buckets.
final class CPUMonitor {

    /// Raw tick counts for one core at one point in time.
    private struct CoreTicks {
        var user: UInt32 = 0
        var system: UInt32 = 0
        var idle: UInt32 = 0
        var nice: UInt32 = 0
    }

    /// Ticks captured from the previous `sample()` call, one per logical core.
    private var previousTicks: [CoreTicks] = []

    /// Number of performance / efficiency cores, resolved once at init via sysctl.
    private let pCoreCount: Int
    private let eCoreCount: Int

    init() {
        // hw.perflevel0 = performance cores, hw.perflevel1 = efficiency cores.
        // On Intel Macs (or any host without heterogeneous cores) these
        // sysctls are absent; sysctlIntValue returns 0 in that case, and we
        // simply won't populate performanceCoreUsage/efficiencyCoreUsage.
        self.pCoreCount = CPUMonitor.sysctlIntValue("hw.perflevel0.logicalcpu") ?? 0
        self.eCoreCount = CPUMonitor.sysctlIntValue("hw.perflevel1.logicalcpu") ?? 0
    }

    /// Reads an integer sysctl by name. Returns nil if the sysctl doesn't
    /// exist or the call fails.
    private static func sysctlIntValue(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname(name, &value, &size, nil, 0)
        guard result == 0 else { return nil }
        return Int(value)
    }

    /// Fetches current per-core tick counts from the kernel. Returns nil on
    /// any failure so callers can gracefully degrade rather than crash.
    private func fetchCoreTicks() -> [CoreTicks]? {
        var numCPUsU: natural_t = 0
        var info: processor_info_array_t?
        var numInfo: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUsU,
            &info,
            &numInfo
        )

        guard result == KERN_SUCCESS, let info = info else {
            return nil
        }

        // Ensure we always release the kernel-allocated array, even if we
        // bail out early below.
        defer {
            let size = vm_size_t(Int(numInfo) * MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)
        }

        let numCPUs = Int(numCPUsU)
        guard numCPUs > 0 else { return nil }

        // info is laid out as numCPUs consecutive groups of CPU_STATE_MAX
        // integer_t values, ordered CPU_STATE_USER/SYSTEM/IDLE/NICE.
        let expectedCount = numCPUs * Int(CPU_STATE_MAX)
        guard Int(numInfo) >= expectedCount else { return nil }

        let ticks: [CoreTicks] = info.withMemoryRebound(to: integer_t.self, capacity: expectedCount) { ptr in
            var result: [CoreTicks] = []
            result.reserveCapacity(numCPUs)
            for core in 0..<numCPUs {
                let base = core * Int(CPU_STATE_MAX)
                var t = CoreTicks()
                t.user = UInt32(ptr[base + Int(CPU_STATE_USER)])
                t.system = UInt32(ptr[base + Int(CPU_STATE_SYSTEM)])
                t.idle = UInt32(ptr[base + Int(CPU_STATE_IDLE)])
                t.nice = UInt32(ptr[base + Int(CPU_STATE_NICE)])
                result.append(t)
            }
            return result
        }

        return ticks
    }

    /// Reads the 1/5/15-minute load averages via getloadavg(3).
    private func loadAverages() -> (Double, Double, Double) {
        var l = [Double](repeating: 0, count: 3)
        let n = getloadavg(&l, 3)
        guard n == 3 else { return (0, 0, 0) }
        return (l[0], l[1], l[2])
    }

    /// Computes a fresh CPUSample from the delta between this call's tick
    /// counts and the previous call's. On the first call (no previous
    /// reading) returns an idle-only sample.
    func sample() -> CPUSample {
        var result = CPUSample()
        result.pCoreCount = pCoreCount
        result.eCoreCount = eCoreCount

        let (l1, l5, l15) = loadAverages()
        result.load1 = l1
        result.load5 = l5
        result.load15 = l15

        guard let currentTicks = fetchCoreTicks(), !currentTicks.isEmpty else {
            // Kernel call failed; return safe defaults (idle=1, everything else 0).
            previousTicks = []
            return result
        }

        defer { previousTicks = currentTicks }

        guard previousTicks.count == currentTicks.count, !previousTicks.isEmpty else {
            // First sample ever (or core count changed) — no delta available yet.
            result.perCore = [Double](repeating: 0, count: currentTicks.count)
            return result
        }

        var perCore: [Double] = []
        perCore.reserveCapacity(currentTicks.count)

        var sumUsage = 0.0
        var sumUser = 0.0
        var sumSystem = 0.0
        var sumIdle = 0.0
        var validCores = 0

        for i in 0..<currentTicks.count {
            let prev = previousTicks[i]
            let cur = currentTicks[i]

            let deltaUser = subtractTicks(cur.user, prev.user)
            let deltaSystem = subtractTicks(cur.system, prev.system)
            let deltaIdle = subtractTicks(cur.idle, prev.idle)
            let deltaNice = subtractTicks(cur.nice, prev.nice)

            let deltaTotal = deltaUser + deltaSystem + deltaIdle + deltaNice

            guard deltaTotal > 0 else {
                perCore.append(0)
                continue
            }

            let busy = Double(deltaUser + deltaSystem + deltaNice) / Double(deltaTotal)
            let idleFrac = Double(deltaIdle) / Double(deltaTotal)
            let userFrac = Double(deltaUser + deltaNice) / Double(deltaTotal)
            let systemFrac = Double(deltaSystem) / Double(deltaTotal)

            let clampedBusy = min(max(busy, 0), 1)
            perCore.append(clampedBusy)

            sumUsage += clampedBusy
            sumUser += min(max(userFrac, 0), 1)
            sumSystem += min(max(systemFrac, 0), 1)
            sumIdle += min(max(idleFrac, 0), 1)
            validCores += 1
        }

        result.perCore = perCore

        if validCores > 0 {
            result.totalUsage = sumUsage / Double(validCores)
            result.user = sumUser / Double(validCores)
            result.system = sumSystem / Double(validCores)
            result.idle = sumIdle / Double(validCores)
        }

        // Apple Silicon: efficiency cores occupy the low indices, performance
        // cores occupy the remainder. Guard bounds in case core counts are
        // unavailable or don't match perCore's length (e.g. Intel Macs).
        if eCoreCount > 0 || pCoreCount > 0 {
            let coreCount = perCore.count

            let eEnd = min(eCoreCount, coreCount)
            if eEnd > 0 {
                let eSlice = perCore[0..<eEnd]
                result.efficiencyCoreUsage = eSlice.reduce(0, +) / Double(eSlice.count)
            }

            let pStart = min(eCoreCount, coreCount)
            let pEnd = min(eCoreCount + pCoreCount, coreCount)
            if pEnd > pStart {
                let pSlice = perCore[pStart..<pEnd]
                result.performanceCoreUsage = pSlice.reduce(0, +) / Double(pSlice.count)
            }
        }

        return result
    }

    /// Subtracts two tick counters, guarding against wraparound (unlikely,
    /// but tick counters are unsigned and could theoretically decrease if
    /// the core set changes between samples).
    private func subtractTicks(_ current: UInt32, _ previous: UInt32) -> UInt64 {
        guard current >= previous else { return 0 }
        return UInt64(current - previous)
    }
}
