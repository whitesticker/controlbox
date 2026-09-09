import Foundation
import Darwin

// Collects physical memory usage, memory pressure, and swap statistics using
// low-level Mach/BSD APIs, mirroring the semantics Activity Monitor uses for
// its "Memory" tab (App Memory / Wired / Compressed / Cached Files / Free).
//
// Contract: final class MemoryMonitor { init(); func sample() -> MemorySample }
// Called ~1/sec. Never crashes; returns safe (zeroed) defaults on failure.
final class MemoryMonitor {

    init() {}

    func sample() -> MemorySample {
        var result = MemorySample()

        // Total physical RAM.
        let total = ProcessInfo.processInfo.physicalMemory
        result.total = total

        // Page size used by the VM subsystem for the counts below.
        let pageSize = UInt64(vm_kernel_page_size)

        // Host VM statistics (page counts by category).
        if let stats = hostVMStatistics64() {
            let wired = UInt64(stats.wire_count) * pageSize
            let compressed = UInt64(stats.compressor_page_count) * pageSize
            let purgeable = UInt64(stats.purgeable_count) * pageSize
            let external = UInt64(stats.external_page_count) * pageSize
            let free = UInt64(stats.free_count) * pageSize

            // internal_page_count includes purgeable pages; subtract them out
            // so "app" reflects non-purgeable internal (anonymous) memory,
            // matching Activity Monitor's "App Memory".
            let internalPages = UInt64(stats.internal_page_count) * pageSize
            let app = internalPages > purgeable ? internalPages - purgeable : 0

            result.wired = wired
            result.compressed = compressed
            result.app = app
            result.cached = purgeable + external
            result.free = free
            result.used = app + wired + compressed

            // Pressure gauge: fraction of RAM that is NOT immediately
            // reclaimable/free, clamped to 0...1.
            if total > 0 {
                let reclaimableOrFree = Double(free + result.cached)
                let gauge = 1.0 - reclaimableOrFree / Double(total)
                result.pressure = min(1.0, max(0.0, gauge))
            }
        }

        // Kernel-reported memory pressure level: 1 = normal, 2 = warning,
        // 4 = critical. Falls back to the struct default (1) on failure.
        var pressureLevel: Int32 = 1
        var pressureSize = MemoryLayout<Int32>.size
        let pressureResult = sysctlbyname(
            "kern.memorystatus_vm_pressure_level",
            &pressureLevel,
            &pressureSize,
            nil,
            0
        )
        if pressureResult == 0 {
            result.pressureLevel = Int(pressureLevel)
        }

        // Swap usage via vm.swapusage -> struct xsw_usage.
        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        let swapResult = sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0)
        if swapResult == 0 {
            result.swapTotal = swap.xsu_total
            result.swapUsed = swap.xsu_used
        }

        return result
    }

    // Fetches host_statistics64(HOST_VM_INFO64) and returns the raw struct,
    // or nil if the call fails for any reason.
    private func hostVMStatistics64() -> vm_statistics64_data_t? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )

        let result = withUnsafeMutablePointer(to: &stats) { statsPointer -> kern_return_t in
            statsPointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return nil
        }
        return stats
    }
}
