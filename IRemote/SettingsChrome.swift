import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case profiles
    case devices
    case calibration
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .profiles: return "Profiles"
        case .devices: return "Devices"
        case .calibration: return "Calibration"
        case .privacy: return "Privacy & Security"
        }
    }

    var symbol: String {
        switch self {
        case .profiles: return "rectangle.stack.fill"
        case .devices: return "appletvremote.gen4.fill"
        case .calibration: return "viewfinder"
        case .privacy: return "hand.raised.fill"
        }
    }

    var tint: Color {
        switch self {
        case .profiles: return Color(red: 0.20, green: 0.48, blue: 0.96)
        case .devices: return Color(red: 0.35, green: 0.34, blue: 0.84)
        case .calibration: return Color(red: 0.18, green: 0.64, blue: 0.52)
        case .privacy: return Color(red: 0.22, green: 0.55, blue: 0.90)
        }
    }

    var group: SettingsGroup {
        switch self {
        case .profiles, .devices: return .control
        case .calibration: return .input
        case .privacy: return .privacy
        }
    }
}

enum SettingsGroup: String, CaseIterable, Hashable {
    case control
    case input
    case privacy

    var title: String? {
        switch self {
        case .control: return nil
        case .input: return "Input"
        case .privacy: return "Privacy"
        }
    }
}

struct SettingsGlyph: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(tint, in: RoundedRectangle(cornerRadius: 6.5, style: .continuous))
    }
}
