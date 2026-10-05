import Foundation

/// Host OS families named by HID++ `0x4531` Multi-Platform descriptor OS masks.
public enum LogitechHostOS: String, CaseIterable, Codable, Sendable {
    case macOS
    case windows
    case iOS
    case linux
    case chromeOS
    case android
    case webOS
    case windowsEmbedded
    case tizen

    /// Picker order and naming priority when one descriptor covers several OSes.
    public static let priority: [LogitechHostOS] = [
        .macOS, .windows, .iOS, .linux, .chromeOS, .android, .webOS, .windowsEmbedded, .tizen
    ]

    public var maskBit: UInt16 {
        switch self {
        case .tizen: return 0x0001
        case .windows: return 0x0100
        case .windowsEmbedded: return 0x0200
        case .linux: return 0x0400
        case .chromeOS: return 0x0800
        case .android: return 0x1000
        case .macOS: return 0x2000
        case .iOS: return 0x4000
        case .webOS: return 0x8000
        }
    }

    public var title: String {
        switch self {
        case .macOS: return "macOS"
        case .windows: return "Windows"
        case .iOS: return "iOS"
        case .linux: return "Linux"
        case .chromeOS: return "ChromeOS"
        case .android: return "Android"
        case .webOS: return "webOS"
        case .windowsEmbedded: return "Windows Embedded"
        case .tizen: return "Tizen"
        }
    }
}

/// One selectable key layout: the firmware platform index plus the OS it is named for.
public struct LogitechPlatformOption: Equatable, Hashable, Identifiable, Sendable {
    public var platformIndex: UInt8
    public var os: LogitechHostOS

    public var id: UInt8 { platformIndex }
    public var title: String { os.title }

    public init(platformIndex: UInt8, os: LogitechHostOS) {
        self.platformIndex = platformIndex
        self.os = os
    }
}

/// HID++ 2.0 Multi-Platform (`0x4531`). Functions: 0 getFeatureInfos,
/// 1 getPlatformDescriptor, 2 getHostPlatform, 3 setHostPlatform.
/// Host `0xFF` is the current Easy-Switch channel.
public enum LogitechMultiPlatform {
    public static let featureID: UInt16 = 0x4531
    public static let currentHost: UInt8 = 0xFF
    private static let canSetPlatformFlag: UInt8 = 0x02

    public struct Info: Equatable, Sendable {
        public var canSetPlatform: Bool
        public var descriptorCount: Int
        public var currentPlatform: UInt8
    }

    public struct Descriptor: Equatable, Sendable {
        public var platformIndex: UInt8
        public var osMask: UInt16
    }

    /// `getFeatureInfos`: capability flags, reserved, descriptor count, platform
    /// count, host count, current host, current host platform.
    public static func info(payload: Data?) -> Info? {
        guard let bytes = payload.map(Array.init), bytes.count >= 7 else { return nil }
        return Info(
            canSetPlatform: bytes[0] & canSetPlatformFlag != 0,
            descriptorCount: Int(bytes[2]),
            currentPlatform: bytes[6]
        )
    }

    /// `getPlatformDescriptor`: platform index, descriptor index, OS mask (big-endian).
    public static func descriptor(payload: Data?) -> Descriptor? {
        guard let bytes = payload.map(Array.init), bytes.count >= 4 else { return nil }
        return Descriptor(
            platformIndex: bytes[0],
            osMask: UInt16(bytes[2]) << 8 | UInt16(bytes[3])
        )
    }

    /// One option per platform index, named by the highest-priority OS in its mask.
    public static func options(from descriptors: [Descriptor]) -> [LogitechPlatformOption] {
        var options: [LogitechPlatformOption] = []
        for os in LogitechHostOS.priority {
            for descriptor in descriptors where descriptor.osMask & os.maskBit != 0 {
                if options.contains(where: { $0.platformIndex == descriptor.platformIndex || $0.os == os }) {
                    continue
                }
                options.append(LogitechPlatformOption(platformIndex: descriptor.platformIndex, os: os))
            }
        }
        return options
    }

    public static func setHostPlatformParameters(_ platformIndex: UInt8) -> [UInt8] {
        [currentHost, platformIndex]
    }
}
