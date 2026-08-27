import Foundation

// Shared formatting helpers used by both the menu bar drawing and the panel UI.
enum Fmt {
    // "1.2 GB", "512 MB", "0 B" — base-1000 (decimal) like Finder/iStat.
    static func bytes(_ value: UInt64) -> String {
        bytes(Double(value))
    }

    static func bytes(_ value: Double) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var v = max(value, 0)
        var i = 0
        while v >= 1000 && i < units.count - 1 {
            v /= 1000
            i += 1
        }
        if i == 0 { return "\(Int(v)) \(units[i])" }
        return String(format: v >= 100 ? "%.0f %@" : "%.1f %@", v, units[i])
    }

    // Full speed label: "1.2 MB/s".
    static func speed(_ bytesPerSec: Double) -> String {
        bytes(bytesPerSec) + "/s"
    }

    // "48 GB" -- base-1024 (binary), matching Activity Monitor's convention
    // for RAM specifically (unlike disk/network, which use decimal like
    // Finder). RAM capacity is manufactured/reported in binary GiB even
    // though labeled "GB", so `ProcessInfo.physicalMemory`'s raw byte count
    // for e.g. 48 GB of RAM is 48 * 1024^3 -- formatting that with the
    // decimal `bytes()` above would print "51.5 GB" and not match what the
    // user knows their machine has installed.
    static func bytesBinary(_ value: UInt64) -> String {
        bytesBinary(Double(value))
    }

    static func bytesBinary(_ value: Double) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var v = max(value, 0)
        var i = 0
        while v >= 1024 && i < units.count - 1 {
            v /= 1024
            i += 1
        }
        if i == 0 { return "\(Int(v)) \(units[i])" }
        return String(format: v >= 100 ? "%.0f %@" : "%.1f %@", v, units[i])
    }

    // Compact speed for the tight menu bar (value + single-letter unit),
    // returned as (number, unit) so the caller can align them.
    static func speedCompact(_ bytesPerSec: Double) -> (String, String) {
        let units = ["B", "K", "M", "G", "T"]
        var v = max(bytesPerSec, 0)
        var i = 0
        while v >= 1000 && i < units.count - 1 {
            v /= 1000
            i += 1
        }
        let num: String
        if i == 0 {
            num = String(format: "%.0f", v)
        } else if v >= 100 {
            num = String(format: "%.0f", v)
        } else if v >= 10 {
            num = String(format: "%.1f", v)
        } else {
            num = String(format: "%.1f", v)
        }
        return (num, units[i] + "/s")
    }

    // "45%" style.
    static func percent(_ fraction: Double, decimals: Int = 0) -> String {
        String(format: "%.\(decimals)f%%", max(0, min(1, fraction)) * 100)
    }

    // "45 °C".
    static func temp(_ celsius: Double) -> String {
        celsius <= 0 ? "—" : String(format: "%.0f °C", celsius)
    }

    // "1234 rpm".
    static func rpm(_ value: Double) -> String {
        value <= 0 ? "—" : String(format: "%.0f rpm", value)
    }

    // "2:35" from minutes, or "—" when unknown.
    static func minutes(_ minutes: Int) -> String {
        guard minutes >= 0 else { return "—" }
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    // "3.4 W".
    static func watts(_ value: Double) -> String {
        value <= 0 ? "—" : String(format: "%.1f W", value)
    }
}
