import SwiftUI

enum SidebarItem: Hashable, Identifiable {
    case displays
    case nightShift
    case displayArrangement
    case sound
    case caffeinate
    case systemMonitor
    case pointerScroll
    case windowGrab
    case capsLock
    case dockPreview
    case permissions
    case settings
    case device(String)

    var id: String {
        switch self {
        case .displays: return "mac.displays"
        case .nightShift: return "mac.nightShift"
        case .displayArrangement: return "mac.displayArrangement"
        case .sound: return "mac.sound"
        case .caffeinate: return "mac.caffeinate"
        case .systemMonitor: return "mac.systemMonitor"
        case .pointerScroll: return "mac.pointerScroll"
        case .windowGrab: return "mac.windowGrab"
        case .capsLock: return "mac.capsLock"
        case .dockPreview: return "mac.dockPreview"
        case .permissions: return "app.permissions"
        case .settings: return "app.settings"
        case .device(let id): return "device.\(id)"
        }
    }

    var title: String {
        switch self {
        case .displays: return "Display Brightness"
        case .nightShift: return "Night Shift"
        case .displayArrangement: return "Display Arrangement"
        case .sound: return "Sound"
        case .caffeinate: return "Caffeinate"
        case .systemMonitor: return "System Monitor"
        case .pointerScroll: return "Pointer & Scroll"
        case .windowGrab: return "Window Management"
        case .capsLock: return "Caps Lock"
        case .dockPreview: return "Dock Previews"
        case .permissions: return "Permissions"
        case .settings: return "Settings"
        case .device: return "Device"
        }
    }

    var emoji: String {
        switch self {
        case .displays: return "💡"
        case .nightShift: return "🌖"
        case .displayArrangement: return "🖥️"
        case .sound: return "🔊"
        case .caffeinate: return "☕️"
        case .systemMonitor: return "📟"
        case .pointerScroll: return "🖱️"
        case .windowGrab: return "🧲"
        case .capsLock: return "⬆️"
        case .dockPreview: return "🔎"
        case .permissions: return "🔐"
        case .settings: return "⚙️"
        case .device: return "🎮"
        }
    }

    var tint: Color {
        switch self {
        case .displays: return Color(red: 0.20, green: 0.48, blue: 0.96)
        case .nightShift: return Color(red: 0.96, green: 0.48, blue: 0.18)
        case .displayArrangement: return Color(red: 0.12, green: 0.40, blue: 0.78)
        case .sound: return Color(red: 0.35, green: 0.34, blue: 0.84)
        case .caffeinate: return Color(red: 0.62, green: 0.40, blue: 0.22)
        case .systemMonitor: return Color(red: 0.15, green: 0.58, blue: 0.72)
        case .pointerScroll: return Color(red: 0.18, green: 0.64, blue: 0.52)
        case .windowGrab: return Color(red: 0.95, green: 0.55, blue: 0.18)
        case .capsLock: return Color(red: 0.38, green: 0.36, blue: 0.58)
        case .dockPreview: return Color(red: 0.42, green: 0.36, blue: 0.86)
        case .permissions: return Color(red: 0.22, green: 0.55, blue: 0.90)
        case .settings: return Color(red: 0.45, green: 0.47, blue: 0.52)
        case .device: return Color(red: 0.20, green: 0.48, blue: 0.96)
        }
    }
}

struct SettingsGlyph: View {
    let emoji: String
    let tint: Color

    var body: some View {
        Text(emoji)
            .font(.system(size: 16))
            .shadow(color: .black.opacity(0.28), radius: 0.8, y: 0.6)
            .frame(width: 30, height: 30)
            .modifier(SettingsGlyphGlass(tint: tint))
    }
}

/// Tahoe Liquid Glass tile; painted specular squircle on older macOS.
private struct SettingsGlyphGlass: ViewModifier {
    let tint: Color

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
    }

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular.tint(tint.opacity(0.42)), in: shape)
        } else {
            content
                .background {
                    ZStack {
                        shape.fill(.ultraThinMaterial)
                        shape.fill(tint.opacity(0.34))
                        shape.fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.38),
                                    Color.white.opacity(0.04),
                                    Color.black.opacity(0.16)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        shape.strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.55), Color.white.opacity(0.10)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.6
                        )
                    }
                }
        }
    }
}

func footerBullets(_ lines: String...) -> Text {
    footerBullets(Array(lines))
}

func footerBullets(_ lines: [String]) -> Text {
    if lines.count == 1 {
        return Text(lines[0])
    }
    return Text(lines.map { "• \($0)" }.joined(separator: "\n"))
}

/// Row title with a secondary label under it. Notes about one row go here, not in the section footer.
struct SettingsRowLabel: View {
    private let title: String
    private let subtitle: String?

    init(_ title: String, _ subtitle: String?) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension View {
    /// Caption under a row that has no label of its own, such as a button.
    func rowCaption(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            self
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
