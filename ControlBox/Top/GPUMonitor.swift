import Foundation
import IOKit

// MARK: - GPUMonitor
//
// Samples GPU utilization on Apple Silicon by querying the IOKit registry
// for accelerator services (class "IOAccelerator", which the integrated
// AGX GPU publishes itself under). Each such service exposes a
// "PerformanceStatistics" dictionary property containing (among other
// things) a "Device Utilization %" entry that reports 0...100.
//
// This deliberately avoids Metal/MetalKit — we only need a coarse
// utilization percentage and a display name, and IOKit gives us that
// without spinning up a GPU context.
final class GPUMonitor {

    init() {
        // No persistent state needed: each sample() call performs a fresh,
        // cheap IOKit registry walk.
    }

    // MARK: - Public API

    /// Takes one snapshot of GPU utilization. Safe to call ~1/sec from a
    /// background queue. Never throws/crashes — on any failure this
    /// returns a default (unavailable) GPUSample.
    func sample() -> GPUSample {
        var iterator: io_iterator_t = IO_OBJECT_NULL
        let matchResult = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOAccelerator"),
            &iterator
        )
        guard matchResult == KERN_SUCCESS, iterator != IO_OBJECT_NULL else {
            return GPUSample()
        }
        defer { IOObjectRelease(iterator) }

        var best: GPUSample? = nil

        while case let service = IOIteratorNext(iterator), service != IO_OBJECT_NULL {
            defer { IOObjectRelease(service) }

            guard let candidate = readSample(from: service) else { continue }

            // Prefer the first accelerator that actually reports a
            // non-zero utilization figure; otherwise keep the first
            // valid accelerator we found as a fallback.
            if best == nil {
                best = candidate
            } else if candidate.utilization > 0 && (best?.utilization ?? 0) == 0 {
                best = candidate
            }
        }

        return best ?? GPUSample()
    }

    // MARK: - Private helpers

    /// Attempts to build a GPUSample from a single IOAccelerator service.
    /// Returns nil if the service doesn't look like a usable GPU entry.
    private func readSample(from service: io_object_t) -> GPUSample? {
        var sample = GPUSample()

        // --- Name -----------------------------------------------------
        sample.name = gpuName(for: service)

        // --- Utilization -----------------------------------------------
        guard let statsRaw = IORegistryEntryCreateCFProperty(
            service,
            "PerformanceStatistics" as CFString,
            kCFAllocatorDefault,
            0
        ) else {
            // No performance statistics; still might be a valid GPU, but
            // without utilization data it's not very useful. Report it as
            // available with zero utilization rather than dropping it,
            // so a system with an unusual driver still shows *something*.
            sample.available = true
            return sample
        }

        let stats = statsRaw.takeRetainedValue()
        guard let dict = stats as? [String: Any] else {
            sample.available = true
            return sample
        }

        let utilizationKeys = [
            "Device Utilization %",
            "GPU Activity(%)",
            "Renderer Utilization %"
        ]

        var foundUtilization: Double? = nil
        for key in utilizationKeys {
            if let value = dict[key] {
                if let number = value as? NSNumber {
                    foundUtilization = number.doubleValue / 100.0
                    break
                }
            }
        }

        if let util = foundUtilization {
            sample.utilization = min(max(util, 0), 1)
        }

        sample.available = true
        return sample
    }

    /// Best-effort GPU display name lookup: tries the "model" property
    /// (which may be raw Data containing a C string, or a CFString),
    /// then falls back to the IORegistry entry's own class/name.
    private func gpuName(for service: io_object_t) -> String {
        if let modelRaw = IORegistryEntryCreateCFProperty(
            service,
            "model" as CFString,
            kCFAllocatorDefault,
            0
        ) {
            let model = modelRaw.takeRetainedValue()

            if let str = model as? String, !str.isEmpty {
                return str
            }

            if let data = model as? Data, !data.isEmpty {
                // Model strings from IOKit are frequently NUL-terminated
                // C strings stored as raw Data.
                let trimmed = data.split(separator: 0).first ?? data[...]
                if let str = String(data: trimmed, encoding: .utf8), !str.isEmpty {
                    return str
                }
            }
        }

        // Fallback: the registry entry's own name (e.g. "AGXAcceleratorG13").
        var nameBuf = [CChar](repeating: 0, count: 128)
        let result = IORegistryEntryGetName(service, &nameBuf)
        if result == KERN_SUCCESS {
            let name = String(cString: nameBuf)
            if !name.isEmpty {
                return name
            }
        }

        return "GPU"
    }
}
