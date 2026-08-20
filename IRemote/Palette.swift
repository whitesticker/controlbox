import SwiftUI

enum Palette {
    static let accent = Color.accentColor
    static let good = Color(nsColor: .systemGreen)
    static let bad = Color(nsColor: .systemRed)
    static let cross = Color(red: 0.42, green: 0.52, blue: 0.98)
    static let circle = Color(red: 0.92, green: 0.28, blue: 0.40)
    static let square = Color(red: 0.70, green: 0.42, blue: 0.96)
    static let triangle = Color(red: 0.16, green: 0.72, blue: 0.48)

    static func background(_ scheme: ColorScheme) -> Color {
        Color(nsColor: .windowBackgroundColor)
    }

    static func surface(_ scheme: ColorScheme) -> Color {
        Color(nsColor: .controlBackgroundColor)
    }

    static func controllerBody(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(white: 0.16)
            : Color(white: 0.93)
    }

    static func primaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white : Color(nsColor: .labelColor)
    }

    static func secondaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.88) : Color(nsColor: .secondaryLabelColor)
    }

    static func hairline(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.10)
    }

    static func fill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    static func raised(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.22) : Color.black.opacity(0.18)
    }
}
