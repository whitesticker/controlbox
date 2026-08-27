import Foundation
import IOKit

// MARK: - Human-readable sensor names
//
// SMC temperature keys are raw 4-character codes (e.g. "TC0P", "Ts0P")
// meaningless to anyone who hasn't memorized Apple's internal naming
// convention. This maps the well-documented ones (used across every
// open-source SMC reader) to plain names, and falls back to a best-effort
// category (still keeping the raw key visible) for newer/undocumented
// Apple Silicon keys we can't map with full confidence.
enum SensorNames {
    private static let known: [String: String] = [
        "TA0P": "Ambient",
        "TA1P": "Ambient 2",
        "TC0P": "CPU Proximity",
        "TC0D": "CPU Die",
        "TC0E": "CPU",
        "TC0F": "CPU",
        "TCGC": "GPU (PECI)",
        "TG0P": "GPU Proximity",
        "TG0D": "GPU Die",
        "TH0P": "Heatsink",
        "TM0P": "Memory",
        "TN0P": "Northbridge",
        "TP0P": "Power Supply",
        "TW0P": "Wireless",
        "Ts0P": "Palm Rest",
        "Ts1P": "Palm Rest 2",
        "TB0T": "Battery",
        "TB1T": "Battery 2",
        "TB2T": "Battery 3",
    ]

    /// A human-readable name for a raw SMC key. Exact matches use the
    /// documented name above; anything else gets a best-effort category
    /// (CPU/GPU/Battery/etc.) with the raw key kept alongside it, since we
    /// aren't fully certain what it measures.
    static func displayName(for key: String) -> String {
        if let known = known[key] { return known }
        if key.hasPrefix("Ts") { return "Case/Palm Rest (\(key))" }
        if key.hasPrefix("TB") { return "Battery (\(key))" }
        if key.hasPrefix("TA") { return "Ambient (\(key))" }
        if key.hasPrefix("TW") { return "Wireless (\(key))" }
        if key.hasPrefix("TH") { return "Heatsink (\(key))" }
        if key.hasPrefix("TM") { return "Memory (\(key))" }
        if key.hasPrefix("Tp") || key.hasPrefix("Tc") || key.hasPrefix("TC") { return "CPU (\(key))" }
        if key.hasPrefix("Tg") || key.hasPrefix("TG") { return "GPU (\(key))" }
        return key
    }
}

// MARK: - SMC (Apple System Management Controller) access
//
// This file talks directly to the AppleSMC IOKit user client to read
// temperature and fan sensors. There is no public API for this, so we
// reconstruct the classic "SMCParamStruct" wire format used by every
// open-source SMC reader (smcFanControl, iStats, osx-cpu-temp, etc.)
// and drive it via IOConnectCallStructMethod with selector 2
// (kSMCHandleYPCEvent).
//
// Everything here is defensive: if the service can't be opened, or any
// individual read fails, we simply skip that sensor (or return an empty
// sample) rather than crashing the app.

// MARK: - SMC wire structs

/// SMC firmware version info (part of the param struct; unused by us but
/// required for correct memory layout).
private struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

/// Power limit data (part of the param struct; unused by us but required
/// for correct memory layout).
private struct SMCLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

/// Metadata about a key: its data size (in bytes) and its 4-char-code
/// data type (e.g. "flt ", "sp78", "ui8 ").
///
/// NOTE: the C version of this struct is implicitly padded to a 4-byte
/// boundary (its natural alignment) even though it's embedded inside a
/// larger struct, because the C compiler pads *each individual struct
/// type* to a multiple of its own alignment. Swift does not do this for
/// nested structs, so we add explicit padding bytes here to keep our
/// struct's memory layout bit-for-bit compatible with the kernel's
/// expected C layout (verified via clang offsetof against MemoryLayout
/// .offset(of:)).
private struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
    var _pad0: UInt8 = 0
    var _pad1: UInt8 = 0
    var _pad2: UInt8 = 0
}

/// The full parameter block passed to/from the AppleSMC user client.
/// Layout must match the kernel's expectation exactly (this is the
/// well-known reverse-engineered layout used across the community).
private struct SMCParamStruct {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCLimitData()
    var keyInfo = SMCKeyInfoData()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    // Explicit padding: C aligns the following UInt32 (`data32`) to a
    // 4-byte boundary, which leaves one byte of padding after `data8`.
    var _pad0: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
        (0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0)
}

// Selector for IOConnectCallStructMethod that talks to the SMC.
private let kSMCHandleYPCEvent: UInt32 = 2

// data8 sub-commands understood by the SMC user client.
private let kSMCReadKey: UInt8 = 5
private let kSMCGetKeyFromIndex: UInt8 = 8
private let kSMCGetKeyInfo: UInt8 = 9

// MARK: - FourCC helpers

/// Pack a (max) 4-character string into a big-endian UInt32 SMC key,
/// e.g. "#KEY" -> 0x234B4559.
private func fourCC(_ s: String) -> UInt32 {
    var result: UInt32 = 0
    for byte in s.utf8.prefix(4) {
        result = (result << 8) | UInt32(byte)
    }
    // Pad with spaces if shorter than 4 chars (shouldn't normally happen).
    for _ in s.utf8.count..<4 {
        result = (result << 8) | UInt32(UInt8(ascii: " "))
    }
    return result
}

/// Unpack a big-endian UInt32 SMC key back into its 4-character string
/// form, e.g. for labeling temperature/fan samples with their raw key.
private func fourCCString(_ key: UInt32) -> String {
    let bytes: [UInt8] = [
        UInt8((key >> 24) & 0xFF),
        UInt8((key >> 16) & 0xFF),
        UInt8((key >> 8) & 0xFF),
        UInt8(key & 0xFF)
    ]
    let scalars = bytes.map { b -> Character in
        (b >= 32 && b < 127) ? Character(UnicodeScalar(b)) : " "
    }
    return String(scalars)
}

// MARK: - SensorMonitor

/// Reads CPU/GPU temperatures and fan speeds from the Apple SMC.
///
/// The IOKit connection is opened once (lazily, on first sample) and
/// reused for the lifetime of the monitor to keep per-tick sampling
/// cheap. If the SMC is unavailable for any reason, `sample()` degrades
/// gracefully to an empty `SensorSample` rather than crashing.
final class SensorMonitor {

    /// Connection handle to the AppleSMC IOKit user client. `0` means
    /// "not connected" (either not yet opened, or open failed).
    private var connection: io_connect_t = 0

    /// Whether we've already attempted (successfully or not) to open
    /// the SMC connection. Prevents retry storms if the service is
    /// simply not present on this Mac.
    private var didAttemptOpen = false

    init() {
        // Connection is opened lazily on first sample() call so that
        // constructing a SensorMonitor never itself has side effects
        // that could fail loudly during app startup.
    }

    deinit {
        close()
    }

    // MARK: Connection lifecycle

    private func open() {
        didAttemptOpen = true

        let matching = IOServiceMatching("AppleSMC")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else {
            return
        }
        defer { IOObjectRelease(service) }

        var conn: io_connect_t = 0
        let result = IOServiceOpen(service, mach_task_self_, 0, &conn)
        guard result == kIOReturnSuccess else {
            connection = 0
            return
        }
        connection = conn
    }

    private func close() {
        if connection != 0 {
            IOServiceClose(connection)
            connection = 0
        }
    }

    // MARK: Low-level SMC call

    /// Issue a single SMC call, returning the (possibly mutated) param
    /// struct on success, or nil if the call failed at the IOKit layer.
    /// Callers must still check `result`/`status` in the returned struct.
    private func call(_ input: SMCParamStruct) -> SMCParamStruct? {
        guard connection != 0 else { return nil }

        var input = input
        var output = SMCParamStruct()
        let inputSize = MemoryLayout<SMCParamStruct>.stride
        var outputSize = MemoryLayout<SMCParamStruct>.stride

        let kr = withUnsafeMutablePointer(to: &output) { outPtr -> kern_return_t in
            withUnsafePointer(to: &input) { inPtr -> kern_return_t in
                IOConnectCallStructMethod(
                    connection,
                    kSMCHandleYPCEvent,
                    inPtr,
                    inputSize,
                    outPtr,
                    &outputSize
                )
            }
        }

        guard kr == kIOReturnSuccess else { return nil }
        return output
    }

    /// Fetch dataSize/dataType metadata for a key. Needed before reading
    /// the key's value, since the byte layout depends on the type.
    private func keyInfo(forKey key: UInt32) -> SMCKeyInfoData? {
        var input = SMCParamStruct()
        input.key = key
        input.data8 = kSMCGetKeyInfo

        guard let output = call(input), output.result == 0 else { return nil }
        return output.keyInfo
    }

    /// Read the raw bytes for a key given its already-known size/type.
    private func readKeyBytes(key: UInt32, info: SMCKeyInfoData) -> [UInt8]? {
        var input = SMCParamStruct()
        input.key = key
        input.keyInfo = info
        input.data8 = kSMCReadKey

        guard let output = call(input), output.result == 0 else { return nil }

        let size = Int(info.dataSize)
        guard size > 0, size <= 32 else { return nil }

        let tuple = output.bytes
        let all: [UInt8] = [
            tuple.0, tuple.1, tuple.2, tuple.3, tuple.4, tuple.5, tuple.6, tuple.7,
            tuple.8, tuple.9, tuple.10, tuple.11, tuple.12, tuple.13, tuple.14, tuple.15,
            tuple.16, tuple.17, tuple.18, tuple.19, tuple.20, tuple.21, tuple.22, tuple.23,
            tuple.24, tuple.25, tuple.26, tuple.27, tuple.28, tuple.29, tuple.30, tuple.31
        ]
        return Array(all.prefix(size))
    }

    /// Look up the key at a given index (0-based) in the SMC's internal
    /// key table. Used to enumerate all available keys.
    private func key(atIndex index: UInt32) -> UInt32? {
        var input = SMCParamStruct()
        input.data8 = kSMCGetKeyFromIndex
        input.data32 = index

        guard let output = call(input), output.result == 0 else { return nil }
        return output.key
    }

    /// Convenience: read + decode a key as a Double, given we already
    /// know (or look up) its type. Returns nil on any failure.
    private func readDouble(key: UInt32) -> Double? {
        guard let info = keyInfo(forKey: key) else { return nil }
        guard let bytes = readKeyBytes(key: key, info: info) else { return nil }
        return decode(bytes: bytes, dataType: info.dataType)
    }

    // MARK: Value decoding

    /// Decode raw SMC bytes into a Double based on the 4CC data type.
    /// Supports the handful of numeric encodings SMC uses for sensors:
    /// "flt " (float32 LE), "sp78"/"sp##" (fixed point), "fpe2"
    /// (fixed point, classic Intel fan RPM), and unsigned ints.
    private func decode(bytes: [UInt8], dataType: UInt32) -> Double? {
        let type = fourCCString(dataType).trimmingCharacters(in: .whitespaces)

        switch type {
        case "flt":
            guard bytes.count >= 4 else { return nil }
            var raw: UInt32 = 0
            for i in 0..<4 {
                raw |= UInt32(bytes[i]) << (8 * i) // little-endian
            }
            return Double(Float(bitPattern: raw))

        case "sp78":
            guard bytes.count >= 2 else { return nil }
            // Big-endian signed 16-bit, fixed point with 8 fractional bits.
            let raw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            let signed = Int16(bitPattern: raw)
            return Double(signed) / 256.0

        case "fpe2":
            guard bytes.count >= 2 else { return nil }
            let raw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            return Double(raw) / 4.0

        case "ui8":
            guard bytes.count >= 1 else { return nil }
            return Double(bytes[0])

        case "ui16":
            guard bytes.count >= 2 else { return nil }
            let raw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            return Double(raw)

        case "ui32":
            guard bytes.count >= 4 else { return nil }
            var raw: UInt32 = 0
            for i in 0..<4 {
                raw = (raw << 8) | UInt32(bytes[i])
            }
            return Double(raw)

        default:
            // Some "sp##" variants (sp1f, sp3c, etc.) exist on various
            // Macs; treat any other 2-byte "sp.." type as sp78-style
            // fixed point since the fractional bit count rarely matters
            // for our plausibility-filtered temperature use case.
            if type.hasPrefix("sp"), bytes.count >= 2 {
                let raw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
                let signed = Int16(bitPattern: raw)
                return Double(signed) / 256.0
            }
            return nil
        }
    }

    // MARK: Public API

    /// Take one sample of all available temperature and fan sensors.
    /// Never throws or crashes: on any failure this degrades to an
    /// empty (all-zero) SensorSample.
    func sample() -> SensorSample {
        var result = SensorSample()

        if connection == 0 {
            if didAttemptOpen {
                // We already tried once and failed; don't keep retrying
                // every tick.
                return result
            }
            open()
            guard connection != 0 else { return result }
        }

        // --- Temperatures ---------------------------------------------
        // Enumerate all SMC keys via "#KEY" (total count) + GetKeyFromIndex,
        // and keep any "T*"-prefixed key whose decoded value looks like a
        // plausible temperature. This is robust across Intel and Apple
        // Silicon Macs, which expose very different key names.
        var cpuValues: [Double] = []
        var gpuValues: [Double] = []

        if let countKeyInfo = keyInfo(forKey: fourCC("#KEY")),
           let countBytes = readKeyBytes(key: fourCC("#KEY"), info: countKeyInfo),
           let countDouble = decode(bytes: countBytes, dataType: countKeyInfo.dataType) {

            let totalKeys = UInt32(countDouble)
            // Guard against pathological values.
            let cappedTotal = min(totalKeys, 10_000)

            for idx in 0..<cappedTotal {
                guard let key = key(atIndex: idx) else { continue }
                let name = fourCCString(key)

                // Only look at temperature-ish keys: SMC convention is
                // that all temperature sensors start with "T".
                guard name.hasPrefix("T") else { continue }

                guard let info = keyInfo(forKey: key) else { continue }
                guard let bytes = readKeyBytes(key: key, info: info) else { continue }
                guard let value = decode(bytes: bytes, dataType: info.dataType) else { continue }

                // Plausibility filter: real die/board temperatures fall
                // roughly in 5...130 C. This filters out non-temperature
                // "T"-prefixed keys (thresholds, flags, etc.) that don't
                // decode to sane values.
                guard value >= 5, value <= 130 else { continue }

                result.temperatures.append(TemperatureSample(label: name, celsius: value))

                // Bucket into CPU/GPU representative groups by common
                // Apple Silicon / Intel key prefixes.
                if name.hasPrefix("Tp") || name.hasPrefix("Tc") || name.hasPrefix("TC") {
                    cpuValues.append(value)
                } else if name.hasPrefix("Tg") || name.hasPrefix("TG") {
                    gpuValues.append(value)
                }
            }
        }

        if !cpuValues.isEmpty {
            result.cpuTemp = cpuValues.reduce(0, +) / Double(cpuValues.count)
        }
        if !gpuValues.isEmpty {
            result.gpuTemp = gpuValues.reduce(0, +) / Double(gpuValues.count)
        }

        // Fallback: if we couldn't classify anything into CPU/GPU buckets
        // by prefix but we do have plausible temperature readings, use
        // the overall max as a rough "cpuTemp" stand-in so the UI has
        // something non-zero to show.
        if result.cpuTemp == 0, let maxTemp = result.temperatures.map({ $0.celsius }).max() {
            result.cpuTemp = maxTemp
        }

        // --- Fans --------------------------------------------------------
        // "FNum" gives the fan count. Fanless Macs (most Apple Silicon
        // laptops) report 0 here, which is expected and fine.
        if let fNumInfo = keyInfo(forKey: fourCC("FNum")),
           let fNumBytes = readKeyBytes(key: fourCC("FNum"), info: fNumInfo),
           let fanCountDouble = decode(bytes: fNumBytes, dataType: fNumInfo.dataType) {

            let fanCount = min(Int(fanCountDouble), 16) // sanity cap
            for i in 0..<max(fanCount, 0) {
                let rpmKey = fourCC("F\(i)Ac")
                let minKey = fourCC("F\(i)Mn")
                let maxKey = fourCC("F\(i)Mx")

                let rpm = readDouble(key: rpmKey) ?? 0
                let minRPM = readDouble(key: minKey) ?? 0
                let maxRPM = readDouble(key: maxKey) ?? 0

                // Try to fetch a human-readable fan label ("F0ID" on many
                // Macs holds a descriptive string); fall back to a generic
                // "Fan N" label if unavailable.
                var label = "Fan \(i)"
                let idKey = fourCC("F\(i)ID")
                if let idInfo = keyInfo(forKey: idKey),
                   let idBytes = readKeyBytes(key: idKey, info: idInfo) {
                    let printable = idBytes.filter { $0 >= 32 && $0 < 127 }
                    if !printable.isEmpty {
                        let s = String(decoding: printable, as: UTF8.self)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !s.isEmpty { label = s }
                    }
                }

                result.fans.append(FanSample(label: label, rpm: rpm, minRPM: minRPM, maxRPM: maxRPM))
            }
        }

        return result
    }
}
