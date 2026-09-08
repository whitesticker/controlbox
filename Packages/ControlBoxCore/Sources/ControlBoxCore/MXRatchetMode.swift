import Foundation

/// MagSpeed / SmartShift wheel detent. Firmware `0x2111` (fallback `0x2110`).
/// Wire bytes: 1 = free-spin, 2 = ratchet. 0 means “do not change” on write.
public enum MXRatchetMode: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case freeSpin
    case ratchet

    public var title: String {
        switch self {
        case .freeSpin: return "Free Spin"
        case .ratchet: return "Ratchet"
        }
    }

    public var hidppByte: UInt8 {
        switch self {
        case .freeSpin: return 1
        case .ratchet: return 2
        }
    }

    public static func fromHIDPP(_ byte: UInt8) -> MXRatchetMode? {
        switch byte {
        case 1: return .freeSpin
        case 2: return .ratchet
        default: return nil
        }
    }
}
