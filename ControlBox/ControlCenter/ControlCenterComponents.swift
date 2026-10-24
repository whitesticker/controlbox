import AppKit
import ControlBoxCore
import SwiftUI

/// Module platter: a quiet fill that brightens on hover.
struct ControlCenterSurface: ViewModifier {
    var radius = ControlCenterDesign.moduleCornerRadius
    var highlighted = false

    func body(content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color.primary.opacity(highlighted ? 0.12 : 0.07))
        )
    }
}

extension View {
    func controlCenterSurface(radius: CGFloat = ControlCenterDesign.moduleCornerRadius, highlighted: Bool = false) -> some View {
        modifier(ControlCenterSurface(radius: radius, highlighted: highlighted))
    }
}

/// Control Box line / filled glyph for a module.
struct ControlCenterGlyph: View {
    let module: ControlCenterModule
    var filled = false
    let size: CGFloat

    var body: some View {
        if let base = module.assetName {
            Image("\(base)-\(filled ? "filled" : "line")")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: module.symbol)
                .font(.system(size: size * 0.8, weight: .medium))
                .frame(width: size, height: size)
        }
    }
}

/// The round button: grey when off, the feature's tint with a white glyph when on.
struct ControlCenterIconCircle: View {
    let module: ControlCenterModule
    let active: Bool

    var body: some View {
        let size = ControlCenterDesign.iconSize
        ZStack {
            Circle()
                .fill(active ? AnyShapeStyle(module.tint) : AnyShapeStyle(Color.primary.opacity(0.1)))
            ControlCenterGlyph(module: module, filled: active, size: size * 0.52)
                .foregroundStyle(active ? Color.white : Color.primary)
        }
        .frame(width: size, height: size)
    }
}

/// Chevron hint that a module opens a detail view.
struct ControlCenterChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.secondary)
            .frame(width: 20, height: 20)
            .background(Circle().fill(Color.primary.opacity(0.07)))
    }
}

/// System slider with a leading glyph.
struct ControlCenterSlider: View {
    @Binding var value: Double
    var symbol: String
    var enabled = true
    var onEditingChanged: (Bool) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Slider(value: $value, in: 0...1, onEditingChanged: onEditingChanged)
                .controlSize(.small)
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }
}

/// A full-width hover-highlighted row: the detail views' menu-item feel.
struct ControlCenterRow<Content: View>: View {
    var selected = false
    var enabled = true
    let action: () -> Void
    @ViewBuilder let content: Content
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                content
                Spacer(minLength: 4)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(hovering && enabled ? 0.09 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovering = $0 }
    }
}

struct ControlCenterSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 4)
    }
}

struct ControlCenterNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .fixedSize(horizontal: false, vertical: true)
    }
}

enum ControlCenterSymbols {
    static func speaker(_ volume: Double, muted: Bool = false) -> String {
        if muted { return "speaker.slash.fill" }
        switch volume {
        case ..<0.01: return "speaker.fill"
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }
}

/// The Display module's slider: moves every adjustable display, keeping
/// their mix (each panel's share of the brightest), or the linked slider
/// when One slider for all displays is on.
@MainActor
final class ControlCenterBrightness {
    private var mix: [String: Double]?

    func value(_ catalog: DisplayCatalog) -> Double {
        if catalog.unifiedEnabled { return catalog.unifiedBrightness }
        return catalog.adjustableDisplays.map(\.brightness).max() ?? 0
    }

    func set(_ value: Double, catalog: DisplayCatalog) {
        if catalog.unifiedEnabled {
            catalog.setUnifiedBrightness(value)
            return
        }
        let mix = self.mix ?? capture(catalog)
        self.mix = mix
        for (id, ratio) in mix {
            catalog.setBrightness(min(max(value * ratio, 0), 1), id: id)
        }
    }

    func editingChanged(_ editing: Bool, catalog: DisplayCatalog) {
        mix = editing ? capture(catalog) : nil
    }

    private func capture(_ catalog: DisplayCatalog) -> [String: Double] {
        let adjustable = catalog.adjustableDisplays
        let peak = adjustable.map(\.brightness).max() ?? 0
        return Dictionary(uniqueKeysWithValues: adjustable.map { display in
            (display.id, peak > 0.001 ? display.brightness / peak : 1)
        })
    }
}

enum ControlCenterAppIcon {
    private static var cache: [String: NSImage] = [:]

    /// Best-effort icon for an audio app id (a bundle id when it is one).
    static func image(id: String, name: String) -> NSImage? {
        if let hit = cache[id] { return hit }
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
            ?? NSWorkspace.shared.runningApplications.first { $0.localizedName == name }?.bundleURL
        guard let url else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache[id] = image
        return image
    }
}
