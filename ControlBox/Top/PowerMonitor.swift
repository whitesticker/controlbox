import Foundation
import IOKit
import IOKit.ps

// MARK: - PowerMonitor
//
// Reads battery / power state from two IOKit APIs:
//   1. IOPSCopyPowerSourcesInfo / IOPSCopyPowerSourcesList — the same data
//      backing macOS's own battery menu (percentage, charging, AC state,
//      time remaining). Works even when no battery is present (desktop Macs
//      simply report zero power sources).
//   2. The "AppleSmartBattery" IOService — richer detail (cycle count,
//      design vs. max capacity, temperature, voltage/amperage for wattage)
//      that isn't exposed via IOPowerSources.
//
// Every read is defensive: any missing key, failed lookup, or absent
// service just leaves the corresponding PowerSample field at its default
// (see Models.swift). Nothing here should ever crash, even on a desktop
// Mac with no battery hardware at all.
final class PowerMonitor {

    init() {}

    func sample() -> PowerSample {
        var result = PowerSample()

        readPowerSourcesInfo(into: &result)
        readSmartBatteryInfo(into: &result)

        return result
    }

    // MARK: - IOPowerSources (percentage, charging, AC, time remaining)

    private func readPowerSourcesInfo(into result: inout PowerSample) {
        guard let snapshot = IOPSCopyPowerSourcesInfo() else {
            // No power source info available at all (shouldn't normally
            // happen, but treat as a desktop with no battery).
            result.hasBattery = false
            result.isPluggedIn = true
            result.percentage = 0
            return
        }
        let blob = snapshot.takeRetainedValue()

        guard let sourcesRef = IOPSCopyPowerSourcesList(blob) else {
            result.hasBattery = false
            result.isPluggedIn = true
            result.percentage = 0
            return
        }
        let sources = sourcesRef.takeRetainedValue() as [CFTypeRef]

        // Find the first battery-backed power source, if any.
        var foundBattery = false

        for source in sources {
            guard let descRef = IOPSGetPowerSourceDescription(blob, source) else { continue }
            let desc = descRef.takeUnretainedValue() as NSDictionary

            foundBattery = true
            result.hasBattery = true

            // Percentage: prefer explicit current/max capacity.
            let current = (desc[kIOPSCurrentCapacityKey] as? NSNumber)?.doubleValue
            let max = (desc[kIOPSMaxCapacityKey] as? NSNumber)?.doubleValue
            if let current, let max, max > 0 {
                result.percentage = clamp01(current / max)
            }

            if let charging = desc[kIOPSIsChargingKey] as? Bool {
                result.isCharging = charging
            }

            if let state = desc[kIOPSPowerSourceStateKey] as? String {
                result.isPluggedIn = (state == kIOPSACPowerValue)
            }

            if let timeToEmpty = (desc[kIOPSTimeToEmptyKey] as? NSNumber)?.intValue {
                result.timeToEmptyMinutes = timeToEmpty
            }
            if let timeToFull = (desc[kIOPSTimeToFullChargeKey] as? NSNumber)?.intValue {
                result.timeToFullMinutes = timeToFull
            }

            // Typically there is only one internal battery; stop at the
            // first one we successfully parse.
            break
        }

        if !foundBattery {
            // Desktop Mac (Studio / mini / Pro) or any machine reporting no
            // battery power source: treat as always plugged into AC.
            result.hasBattery = false
            result.isPluggedIn = true
            result.percentage = 0
        }
    }

    // MARK: - AppleSmartBattery IORegistry service (detailed stats)

    private func readSmartBatteryInfo(into result: inout PowerSample) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else {
            // No smart battery service — nothing more to read (desktop Mac).
            return
        }
        defer { IOObjectRelease(service) }

        if let cycleCount = intProperty(service, "CycleCount") {
            result.cycleCount = cycleCount
        }

        // Health = maxCapacity / designCapacity. Try the modern key first,
        // falling back to older ones for compatibility across macOS/HW
        // generations.
        let designCapacity = doubleProperty(service, "DesignCapacity")
        let maxCapacity = doubleProperty(service, "AppleRawMaxCapacity")
            ?? doubleProperty(service, "NominalChargeCapacity")
            ?? doubleProperty(service, "MaxCapacity")

        if let designCapacity, designCapacity > 0, let maxCapacity {
            result.health = clamp01(maxCapacity / designCapacity)
        }

        // Temperature is reported in hundredths of a degree Celsius.
        if let temp = doubleProperty(service, "Temperature") {
            result.temperature = temp / 100.0
        }

        // Instantaneous power draw: |Voltage(mV)/1000 * Amperage(mA)/1000|.
        // Amperage is negative while discharging on most Macs; magnitude is
        // what we want for a "power draw" reading.
        let voltage = doubleProperty(service, "Voltage")
        let amperage = doubleProperty(service, "InstantAmperage") ?? doubleProperty(service, "Amperage")
        if let voltage, let amperage {
            let volts = voltage / 1000.0
            let amps = amperage / 1000.0
            result.powerWatts = abs(volts * amps)
        }
    }

    // MARK: - IORegistry property helpers

    private func intProperty(_ service: io_service_t, _ key: String) -> Int? {
        guard let ref = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }
        let value = ref.takeRetainedValue()
        return (value as? NSNumber)?.intValue
    }

    private func doubleProperty(_ service: io_service_t, _ key: String) -> Double? {
        guard let ref = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }
        let value = ref.takeRetainedValue()
        return (value as? NSNumber)?.doubleValue
    }

    private func clamp01(_ value: Double) -> Double {
        if value.isNaN || value.isInfinite { return 0 }
        return min(1, max(0, value))
    }
}
