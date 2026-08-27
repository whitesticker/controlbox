import SwiftUI

enum SidebarItem: Hashable, Identifiable {
    case displays
    case displayArrangement
    case sound
    case systemMonitor
    case pointerScroll
    case windowGrab
    case permissions
    case device(String)

    var id: String {
        switch self {
        case .displays: return "mac.displays"
        case .displayArrangement: return "mac.displayArrangement"
        case .sound: return "mac.sound"
        case .systemMonitor: return "mac.systemMonitor"
        case .pointerScroll: return "mac.pointerScroll"
        case .windowGrab: return "mac.windowGrab"
        case .permissions: return "app.permissions"
        case .device(let id): return "device.\(id)"
        }
    }

    var title: String {
        switch self {
        case .displays: return "Displays"
        case .displayArrangement: return "Display Arrangement"
        case .sound: return "Sound"
        case .systemMonitor: return "System Monitor"
        case .pointerScroll: return "Pointer & Scroll"
        case .windowGrab: return "Window Grab"
        case .permissions: return "Permissions"
        case .device: return "Device"
        }
    }

    var symbol: String {
        switch self {
        case .displays: return "display"
        case .displayArrangement: return "display.2"
        case .sound: return "speaker.wave.2.fill"
        case .systemMonitor: return "chart.xyaxis.line"
        case .pointerScroll: return "computermouse.fill"
        case .windowGrab: return "macwindow.on.rectangle"
        case .permissions: return "lock.shield.fill"
        case .device: return "gamecontroller.fill"
        }
    }

    var tint: Color {
        switch self {
        case .displays: return Color(red: 0.20, green: 0.48, blue: 0.96)
        case .displayArrangement: return Color(red: 0.12, green: 0.40, blue: 0.78)
        case .sound: return Color(red: 0.35, green: 0.34, blue: 0.84)
        case .systemMonitor: return Color(red: 0.15, green: 0.58, blue: 0.72)
        case .pointerScroll: return Color(red: 0.18, green: 0.64, blue: 0.52)
        case .windowGrab: return Color(red: 0.95, green: 0.55, blue: 0.18)
        case .permissions: return Color(red: 0.22, green: 0.55, blue: 0.90)
        case .device: return Color(red: 0.20, green: 0.48, blue: 0.96)
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
