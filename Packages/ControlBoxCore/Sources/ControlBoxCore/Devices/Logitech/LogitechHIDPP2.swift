import Foundation

/// Pure HID++ 2.0 wire helpers shared by Logitech device families.
///
/// Transport policy stays with each device session: callers decide whether a
/// pipe accepts short reports, how replies are correlated, and how timeouts
/// affect recovery.
public enum LogitechHIDPP2 {
    public static let shortReportID: UInt8 = 0x10
    public static let longReportID: UInt8 = 0x11
    public static let shortParameterCount = 3
    public static let longParameterCount = 16
    public static let knownReceiverProductIDs: Set<Int> = [
        0xC52B, 0xC52F, 0xC531, 0xC532, 0xC534, 0xC537, 0xC539,
        0xC53A, 0xC53F, 0xC547, 0xC548, 0xC54D
    ]

    /// Control Box reserves software IDs `0x08...0x0F` for queued HID++ calls.
    public static func nextSoftwareID(after current: UInt8) -> UInt8 {
        current == 0x0F ? 0x08 : current + 1
    }

    public static func longReport(
        deviceIndex: UInt8,
        featureIndex: UInt8,
        function: UInt8,
        softwareID: UInt8,
        parameters: [UInt8]
    ) -> [UInt8] {
        report(
            id: longReportID,
            length: 20,
            parameterCount: longParameterCount,
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            function: function,
            softwareID: softwareID,
            parameters: parameters
        )
    }

    public static func shortReport(
        deviceIndex: UInt8,
        featureIndex: UInt8,
        function: UInt8,
        softwareID: UInt8,
        parameters: [UInt8]
    ) -> [UInt8] {
        report(
            id: shortReportID,
            length: 7,
            parameterCount: shortParameterCount,
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            function: function,
            softwareID: softwareID,
            parameters: parameters
        )
    }

    public static func featureLookupParameters(_ featureID: UInt16) -> [UInt8] {
        [UInt8(featureID >> 8), UInt8(featureID & 0xFF)]
    }

    public static func featureSetIndices(count: Int, limit: Int = 48) -> [UInt8] {
        let upper = min(max(count, 0), max(limit, 0), Int(UInt8.max))
        guard upper > 0 else { return [] }
        return (1...upper).map(UInt8.init)
    }

    public static func cidReportingParameters(
        cid: UInt16,
        flags: UInt8,
        remap: UInt16 = 0,
        highFlags: UInt8 = 0
    ) -> [UInt8] {
        var parameters = [
            UInt8(cid >> 8),
            UInt8(cid & 0xFF),
            flags,
            UInt8(remap >> 8),
            UInt8(remap & 0xFF)
        ]
        if highFlags != 0 {
            parameters.append(highFlags)
        }
        return parameters
    }

    private static func report(
        id: UInt8,
        length: Int,
        parameterCount: Int,
        deviceIndex: UInt8,
        featureIndex: UInt8,
        function: UInt8,
        softwareID: UInt8,
        parameters: [UInt8]
    ) -> [UInt8] {
        var report = [UInt8](repeating: 0, count: length)
        report[0] = id
        report[1] = deviceIndex
        report[2] = featureIndex
        report[3] = (function << 4) | (softwareID & 0x0F)
        for (offset, byte) in parameters.prefix(parameterCount).enumerated() {
            report[4 + offset] = byte
        }
        return report
    }
}

public struct LogitechUnifiedBatteryReading: Equatable, Sendable {
    public var percentage: Int
    public var isCharging: Bool
    public var isFull: Bool
    public var stateDescription: String

    public init?(payload: Data?) {
        guard let payload, !payload.isEmpty else { return nil }
        percentage = Int(payload[0])
        let status = payload.count > 2 ? payload[2] : 0
        isCharging = status == 1 || status == 4
        isFull = status == 3 || (percentage >= 95 && (status == 2 || status == 3))
        switch status {
        case 1, 4:
            stateDescription = "Charging"
        case 2:
            stateDescription = "Almost full"
        case 3:
            stateDescription = isFull ? "Full" : "Almost full"
        default:
            stateDescription = "Discharging"
        }
    }
}

public struct LogitechHIDPPCIDReportingState: Equatable, Sendable {
    public var cid: UInt16
    public var diverted: Bool
    public var rawXY: Bool
    public var remap: UInt16
    public var analytics: Bool

    public init?(payload: Data?) {
        guard let payload, payload.count >= 6 else { return nil }
        cid = UInt16(payload[0]) << 8 | UInt16(payload[1])
        diverted = payload[2] & 0x01 != 0
        rawXY = payload[2] & 0x10 != 0
        remap = UInt16(payload[3]) << 8 | UInt16(payload[4])
        analytics = payload[5] & 0x01 != 0
    }

    /// Restores only temporary diversion, raw XY, remap, and analytics.
    /// Persistent diversion and force-raw-XY valid bits are never sent.
    public var restoreParameters: [UInt8] {
        LogitechHIDPP2.cidReportingParameters(
            cid: cid,
            flags: 0x22 | (diverted ? 0x01 : 0) | (rawXY ? 0x10 : 0),
            remap: remap,
            highFlags: 0x02 | (analytics ? 0x01 : 0)
        )
    }
}
