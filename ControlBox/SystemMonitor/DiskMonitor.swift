import Foundation
import IOKit
import IOKit.storage

// MARK: - DiskMonitor
//
// Samples two independent things per tick:
//   1. Volume capacity (name/mount point/total/free/used/internal) via
//      FileManager's volume resource keys — a cheap, synchronous filesystem
//      query, no deltas involved.
//   2. Aggregate disk I/O throughput (bytes/sec read & write) via IOKit,
//      by summing the cumulative "Statistics" byte counters exposed by
//      every IOBlockStorageDriver in the I/O Registry, then differencing
//      against the previous sample using wall-clock elapsed time.
//
// Called ~1/sec from a background queue. The first call has no previous
// reading to diff against, so it reports zero rates.
final class DiskMonitor {

    /// Cumulative bytes read/written, captured at the previous sample.
    private var previousRead: UInt64 = 0
    private var previousWrite: UInt64 = 0

    /// Wall-clock time of the previous sample, used to compute per-second
    /// rates from the byte-count deltas.
    private var previousDate: Date?

    init() {}

    // MARK: Public API

    func sample() -> DiskSample {
        var result = DiskSample()
        result.volumes = fetchVolumes()

        let (totalRead, totalWrite) = fetchCumulativeIOBytes()
        result.totalRead = totalRead
        result.totalWrite = totalWrite

        let now = Date()
        if let previousDate = previousDate {
            let elapsed = now.timeIntervalSince(previousDate)
            if elapsed > 0 {
                // Guard against counters going backwards (e.g. a drive was
                // unplugged/replugged and its stats reset) by clamping
                // negative deltas to zero rather than reporting garbage.
                let deltaRead = totalRead >= previousRead ? totalRead - previousRead : 0
                let deltaWrite = totalWrite >= previousWrite ? totalWrite - previousWrite : 0
                result.readBytesPerSec = Double(deltaRead) / elapsed
                result.writeBytesPerSec = Double(deltaWrite) / elapsed
            }
        }

        previousRead = totalRead
        previousWrite = totalWrite
        previousDate = now

        return result
    }

    // MARK: - Volume capacity

    /// Enumerates mounted, browsable, non-hidden volumes and reads their
    /// capacity/usage via URL resource values. Returns an empty array on
    /// failure rather than throwing.
    private func fetchVolumes() -> [DiskVolumeSample] {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
            .volumeIsInternalKey,
            .volumeIsBrowsableKey
        ]

        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) else {
            return []
        }

        var volumes: [DiskVolumeSample] = []
        // Simple de-duplication: macOS often exposes both a read-only system
        // volume and its writable "Data" counterpart as separate mounts that
        // share the same total capacity (APFS firmlinks). Keeping just one
        // entry per distinct total-capacity value avoids double counting
        // the same physical volume.
        var seenCapacities: Set<UInt64> = []

        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }

            // Skip non-browsable volumes (e.g. hidden system mounts).
            if values.volumeIsBrowsable == false { continue }

            guard let total = values.volumeTotalCapacity, total > 0 else { continue }
            let totalBytes = UInt64(total)

            if seenCapacities.contains(totalBytes) { continue }
            seenCapacities.insert(totalBytes)

            let availableImportant = values.volumeAvailableCapacityForImportantUsage
            let free: UInt64
            if let availableImportant = availableImportant, availableImportant >= 0 {
                free = UInt64(availableImportant)
            } else if let availableBasic = values.volumeAvailableCapacity {
                free = UInt64(availableBasic)
            } else {
                free = 0
            }

            let clampedFree = min(free, totalBytes)

            var sample = DiskVolumeSample()
            sample.name = values.volumeName ?? url.lastPathComponent
            sample.mountPoint = url.path
            sample.total = totalBytes
            sample.free = clampedFree
            sample.used = totalBytes - clampedFree
            sample.isInternal = values.volumeIsInternal ?? true

            volumes.append(sample)
        }

        return volumes
    }

    // MARK: - I/O throughput via IOKit

    /// Sums the cumulative "Bytes (Read)" / "Bytes (Write)" statistics
    /// across every IOBlockStorageDriver in the I/O Registry. Returns
    /// (0, 0) on any failure so callers degrade gracefully.
    private func fetchCumulativeIOBytes() -> (read: UInt64, write: UInt64) {
        guard let matching = IOServiceMatching("IOBlockStorageDriver") else {
            return (0, 0)
        }

        var iterator: io_iterator_t = 0
        let matchResult = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard matchResult == KERN_SUCCESS else {
            return (0, 0)
        }
        defer { IOObjectRelease(iterator) }

        var totalRead: UInt64 = 0
        var totalWrite: UInt64 = 0

        var service: io_object_t = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            guard let propertyRef = IORegistryEntryCreateCFProperty(
                service,
                "Statistics" as CFString,
                kCFAllocatorDefault,
                0
            ) else {
                continue
            }
            let property = propertyRef.takeRetainedValue()

            guard let stats = property as? [String: Any] else { continue }

            if let readValue = stats["Bytes (Read)"] as? Int64, readValue >= 0 {
                totalRead += UInt64(readValue)
            } else if let readValue = stats["Bytes (Read)"] as? UInt64 {
                totalRead += readValue
            }

            if let writeValue = stats["Bytes (Write)"] as? Int64, writeValue >= 0 {
                totalWrite += UInt64(writeValue)
            } else if let writeValue = stats["Bytes (Write)"] as? UInt64 {
                totalWrite += writeValue
            }
        }

        return (totalRead, totalWrite)
    }
}
