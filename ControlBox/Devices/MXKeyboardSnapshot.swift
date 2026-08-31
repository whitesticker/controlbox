import Foundation

enum MXKeyboardBacklightEffect: UInt8, CaseIterable, Identifiable, Equatable, Hashable, Sendable {
    case staticLight = 0
    case none = 1
    case breathing = 2
    case contrast = 3
    case reaction = 4
    case random = 5
    case waves = 6

    var id: UInt8 { rawValue }

    var title: String {
        switch self {
        case .staticLight: return "Static"
        case .none: return "None"
        case .breathing: return "Breathing"
        case .contrast: return "Contrast"
        case .reaction: return "Reaction"
        case .random: return "Random"
        case .waves: return "Waves"
        }
    }

    /// Options+ does not offer “None”; keep it off the picker unless firmware is on it.
    var showsInPicker: Bool { self != .none }
}

struct MXKeyboardSnapshot: Equatable, Sendable {
    var connected = false
    var kind = DeviceKind.logitechMXMechanical
    var name = "MX Mechanical"
    var product = "MX Mechanical"
    var address = ""
    var status = "Looking for an MX Mechanical…"
    var hidppReady = false

    var backlightSupported = false
    var backlightEnabled = false
    var backlightEffect = MXKeyboardBacklightEffect.staticLight
    var supportedEffects: [MXKeyboardBacklightEffect] = MXKeyboardBacklightEffect.allCases.filter(\.showsInPicker)
    var batterySavingSupported = false
    var batterySaving = false

    var batteryAvailable = false
    var batteryPercent: Int?
    var batteryCharging = false
    var batteryFull = false
    var batteryStateDescription = "Unknown"
}
