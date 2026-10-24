import AppKit
import SwiftUI

extension EnvironmentValues {
    /// Offscreen renders cannot draw Liquid Glass; swap it for a fill.
    @Entry var labSnapshot = false
    /// Hosted in a real panel whose window already draws the glass chrome.
    @Entry var inWindowChrome = false
}

/// Module platter: glass, clear glass, a plain fill, or nothing.
struct ModuleSurface: ViewModifier {
    let design: CCDesign
    var radius: Double? = nil
    var highlighted = false
    @Environment(\.labSnapshot) private var snapshot

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius ?? design.moduleCornerRadius, style: .continuous)
        let surface = snapshot && design.surface != .none ? .fill : design.surface
        switch surface {
        case .glass:
            content.glassEffect(.regular.interactive(), in: shape)
        case .clearGlass:
            content.glassEffect(.clear.interactive(), in: shape)
        case .fill:
            content.background(shape.fill(Color.primary.opacity(highlighted ? 0.12 : 0.07)))
        case .none:
            content.background(shape.fill(Color.primary.opacity(highlighted ? 0.08 : 0)))
        }
    }
}

extension View {
    func moduleSurface(_ design: CCDesign, radius: Double? = nil, highlighted: Bool = false) -> some View {
        modifier(ModuleSurface(design: design, radius: radius, highlighted: highlighted))
    }
}

/// Control Box line / filled icon, or the SF Symbol fallback.
struct ModuleIcon: View {
    let kind: ModuleKind
    var filled = false
    let size: Double

    var body: some View {
        if let base = kind.assetName, let image = LabIcons.image("\(base)-\(filled ? "filled" : "line")") {
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: filled ? "\(kind.symbol).fill" : kind.symbol)
                .font(.system(size: size * 0.8, weight: .medium))
                .frame(width: size, height: size)
        }
    }
}

/// The round Control Center button: grey when off, tinted with a white
/// glyph when on.
struct IconCircle: View {
    let kind: ModuleKind
    let active: Bool
    let design: CCDesign

    var body: some View {
        let tint = design.activeTint == .accent ? Color.accentColor : kind.tint
        ZStack {
            Circle()
                .fill(active ? AnyShapeStyle(tint) : AnyShapeStyle(Color.primary.opacity(0.1)))
            ModuleIcon(kind: kind, filled: active, size: design.iconSize * 0.52)
                .foregroundStyle(active ? Color.white : Color.primary)
        }
        .frame(width: design.iconSize, height: design.iconSize)
    }
}

/// Small round chevron that opens a module's detail view.
struct DetailChevron: View {
    var size = 22.0
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.right")
                .font(.system(size: size * 0.45, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.primary.opacity(hovering ? 0.14 : 0.07)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Show details")
    }
}

/// Thick capsule slider with a leading glyph, like Control Center's Display
/// and Sound sliders. Falls back to the system slider.
struct CCSlider: View {
    @Binding var value: Double
    var symbol: String
    let design: CCDesign
    var enabled = true

    var body: some View {
        switch design.sliderStyle {
        case .controlCenter:
            capsule
        case .system:
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Slider(value: $value)
                    .controlSize(.small)
            }
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.45)
        }
    }

    private var capsule: some View {
        let height = design.sliderHeight
        return GeometryReader { geometry in
            let width = geometry.size.width
            let fill = height + (width - height) * min(max(value, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(Color.white)
                    .frame(width: fill)
                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.28), radius: 2, y: 0.5)
                    .frame(width: height, height: height)
                    .offset(x: fill - height)
                Image(systemName: symbol)
                    .font(.system(size: height * 0.46, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.55))
                    .frame(width: height, height: height)
                    .allowsHitTesting(false)
            }
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard enabled else { return }
                        value = min(max((drag.location.x - height / 2) / max(width - height, 1), 0), 1)
                    }
            )
        }
        .frame(height: height)
        .opacity(enabled ? 1 : 0.45)
    }
}

/// A full-width hover-highlighted row, the detail views' menu-item feel.
struct HoverRow<Content: View>: View {
    var selected = false
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
                    .fill(Color.primary.opacity(hovering ? 0.09 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// The panel's own chrome when drawn on the canvas (a real panel window
/// draws it with `NSGlassEffectView` instead).
struct PanelChrome<Content: View>: View {
    let design: CCDesign
    @ViewBuilder let content: Content
    @Environment(\.inWindowChrome) private var inWindow
    @Environment(\.labSnapshot) private var snapshot

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: design.panelCornerRadius, style: .continuous)
        if inWindow {
            content
        } else if snapshot {
            content
                .background(shape.fill(.regularMaterial))
                .background(shape.fill(Color(nsColor: .windowBackgroundColor).opacity(0.6)))
                .clipShape(shape)
        } else {
            content
                .glassEffect(.regular, in: shape)
                .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
        }
    }
}

/// Section header inside a detail view.
struct DetailSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 4)
    }
}
