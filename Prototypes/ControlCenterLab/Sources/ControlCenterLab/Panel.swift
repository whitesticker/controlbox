import SwiftUI

enum PanelRoute: Equatable {
    case home
    case detail(ModuleKind)
}

/// What the Control Box menu bar extra opens: the module grid, a footer, and
/// each module's detail view in place of the grid.
struct ControlCenterPanel: View {
    @ObservedObject var store: LabStore
    var editing: Bool
    var onEditControls: () -> Void
    var onOpenApp: () -> Void

    @State private var route: PanelRoute
    @State private var homeHeight: Double = 0

    init(
        store: LabStore,
        initialRoute: PanelRoute = .home,
        editing: Bool = false,
        onEditControls: @escaping () -> Void = {},
        onOpenApp: @escaping () -> Void = {}
    ) {
        self.store = store
        self.editing = editing
        self.onEditControls = onEditControls
        self.onOpenApp = onOpenApp
        _route = State(initialValue: initialRoute)
    }

    var body: some View {
        let design = store.design
        PanelChrome(design: design) {
            ZStack(alignment: .top) {
                switch route {
                case .home:
                    home(design)
                        .onGeometryChange(for: Double.self) { $0.size.height } action: { homeHeight = $0 }
                        .transition(homeTransition(design))
                case .detail(let kind):
                    detail(kind, design: design)
                        .transition(detailTransition(design))
                }
            }
            .frame(width: design.panelWidth, alignment: .top)
            .modifier(ClipUnlessEditing(editing: editing))
            .overlay(alignment: .bottom) { ToastView(text: store.toast) }
        }
        .animation(design.transition == .none ? nil : .smooth(duration: 0.28), value: route)
    }

    private func home(_ design: CCDesign) -> some View {
        VStack(spacing: design.spacing) {
            ModuleGrid(store: store, editing: editing) { route = .detail($0) }
            if design.footer {
                PanelFooter(store: store, onEditControls: onEditControls, onOpenApp: onOpenApp)
                    .allowsHitTesting(!editing)
                    .opacity(editing ? 0.5 : 1)
            }
        }
        .padding(design.panelPadding)
    }

    @ViewBuilder
    private func detail(_ kind: ModuleKind, design: CCDesign) -> some View {
        let content = DetailView(store: store, kind: kind, standalone: false) { route = .home }
            .padding(design.panelPadding)
        if design.stableHeight && homeHeight > 0 {
            ScrollView { content }
                .scrollIndicators(.never)
                .frame(height: homeHeight)
        } else {
            content
        }
    }

    private func homeTransition(_ design: CCDesign) -> AnyTransition {
        switch design.transition {
        case .slide: .move(edge: .leading).combined(with: .opacity)
        case .crossfade: .opacity
        case .none: .identity
        }
    }

    private func detailTransition(_ design: CCDesign) -> AnyTransition {
        switch design.transition {
        case .slide: .move(edge: .trailing).combined(with: .opacity)
        case .crossfade: .opacity
        case .none: .identity
        }
    }
}

/// Detail transitions slide past the panel edge, so clip them; a module
/// dragged in edit mode must be able to leave the panel to be removed.
private struct ClipUnlessEditing: ViewModifier {
    let editing: Bool

    func body(content: Content) -> some View {
        if editing { content } else { content.clipped() }
    }
}

/// A module's own menu bar extra (Show in Menu Bar on): the detail view as root.
struct ExtraPanel: View {
    @ObservedObject var store: LabStore
    let kind: ModuleKind

    var body: some View {
        let design = store.design
        PanelChrome(design: design) {
            DetailView(store: store, kind: kind, standalone: true)
                .padding(design.panelPadding)
                .frame(width: design.extraWidth, alignment: .top)
                .overlay(alignment: .bottom) { ToastView(text: store.toast) }
        }
    }
}

/// Edit Controls… and Open Control Box on the leading side, Quit trailing.
struct PanelFooter: View {
    @ObservedObject var store: LabStore
    let onEditControls: () -> Void
    let onOpenApp: () -> Void

    var body: some View {
        let design = store.design
        HStack(spacing: 6) {
            switch design.footerStyle {
            case .capsules:
                FooterButton(title: "Edit Controls…", design: design, action: onEditControls)
                FooterButton(title: "Open Control Box", design: design, action: onOpenApp)
                Spacer(minLength: 0)
                FooterButton(title: "Quit", design: design) { store.flash("Would quit Control Box") }
            case .text:
                TextFooterButton(title: "Edit Controls…", action: onEditControls)
                TextFooterButton(title: "Open Control Box", action: onOpenApp)
                Spacer(minLength: 0)
                TextFooterButton(title: "Quit") { store.flash("Would quit Control Box") }
            case .icons:
                FooterIcon(symbol: "slider.horizontal.3", help: "Edit Controls…", design: design, action: onEditControls)
                FooterIcon(ring: true, help: "Open Control Box", design: design, action: onOpenApp)
                Spacer(minLength: 0)
                FooterIcon(symbol: "power", help: "Quit Control Box", design: design) { store.flash("Would quit Control Box") }
            }
        }
    }
}

private struct FooterButton: View {
    let title: String
    let design: CCDesign
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 11)
                .frame(height: 26)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .moduleSurface(design, radius: 13, highlighted: hovering)
        .onHover { hovering = $0 }
    }
}

private struct TextFooterButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(hovering ? .primary : .secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct FooterIcon: View {
    var symbol: String? = nil
    var ring = false
    let help: String
    let design: CCDesign
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Group {
                if ring, let image = LabIcons.ring {
                    Image(nsImage: image).renderingMode(.template).resizable().scaledToFit().frame(width: 13, height: 13)
                } else if let symbol {
                    Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                }
            }
            .frame(width: 28, height: 28)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .moduleSurface(design, radius: 14, highlighted: hovering)
        .onHover { hovering = $0 }
        .help(help)
    }
}

struct ToastView: View {
    let text: String?

    var body: some View {
        Group {
            if let text {
                Text(text)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.black.opacity(0.75)))
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeOut(duration: 0.18), value: text)
        .allowsHitTesting(false)
    }
}
