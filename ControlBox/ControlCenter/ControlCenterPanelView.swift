import AppKit
import SwiftUI

/// What the Control Box menu bar extra opens: the grid, an icon footer, and
/// each module's detail view in place of the grid.
struct ControlCenterPanelView: View {
    let context: ControlCenterContext
    var editing = false

    @State private var detail: ControlCenterModule?

    var body: some View {
        ZStack(alignment: .top) {
            if let detail {
                ControlCenterDetailView(context: context, module: detail, standalone: false) {
                    self.detail = nil
                }
                .padding(ControlCenterDesign.padding)
                .transition(.opacity)
            } else {
                home.transition(.opacity)
            }
        }
        .frame(width: ControlCenterDesign.panelWidth, alignment: .top)
        .animation(.smooth(duration: 0.24), value: detail)
        .controlCenterWhileOpen(context: context, modules: editing ? [] : ControlCenterSettings.shared.order)
        .onDisappear { detail = nil }
    }

    private var home: some View {
        VStack(spacing: ControlCenterDesign.spacing) {
            ControlCenterModuleGrid(context: context, editing: editing) { detail = $0 }
            ControlCenterFooter(context: context)
                .allowsHitTesting(!editing)
                .opacity(editing ? 0.5 : 1)
        }
        .padding(ControlCenterDesign.padding)
    }
}

/// A module's own menu bar extra (Show in Menu Bar on): its detail view as root.
struct ControlCenterExtraView: View {
    let context: ControlCenterContext
    let module: ControlCenterModule

    var body: some View {
        ControlCenterDetailView(context: context, module: module, standalone: true)
            .padding(ControlCenterDesign.padding)
            .frame(width: ControlCenterDesign.extraWidth, alignment: .top)
            .controlCenterWhileOpen(context: context, modules: [module])
    }
}

/// A module extra's menu bar icon; Caffeinate's cup fills while it is on.
struct ControlCenterExtraLabel: View {
    let context: ControlCenterContext
    let module: ControlCenterModule

    var body: some View {
        let filled = module == .caffeinate && context.caffeinate.isActive
        Image(nsImage: Self.icon("\(module.assetName ?? "")-\(filled ? "filled" : "line")"))
            .accessibilityLabel(module.title)
    }

    private static func icon(_ name: String) -> NSImage {
        let image = (NSImage(named: name)?.copy() as? NSImage) ?? NSImage(size: NSSize(width: 18, height: 18))
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }
}

private extension View {
    /// Re-reads the shown modules' catalogs each time the panel opens. Sound
    /// outputs and per-app streams change under us, so they are re-read every
    /// 1.5 s while it stays open (see dev/polling-loops.md).
    func controlCenterWhileOpen(context: ControlCenterContext, modules: [ControlCenterModule]) -> some View {
        onAppear {
            if modules.contains(.display) { context.displays.refresh(readHardware: false) }
            if modules.contains(.sound) { context.sound.refresh() }
            if modules.contains(.arrangement) { context.arrangement.refresh() }
        }
        .task {
            guard modules.contains(.sound) else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                context.sound.refresh()
            }
        }
    }
}

/// Edit Controls… and Open Control Box on the leading side, Quit trailing.
private struct ControlCenterFooter: View {
    let context: ControlCenterContext

    var body: some View {
        HStack(spacing: 6) {
            FooterIcon(help: "Edit Controls…") {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .semibold))
            } action: {
                context.openPane(.controlCenter)
            }
            FooterIcon(help: "Open Control Box") {
                Image(nsImage: MenuBarRingIcon.image)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 13, height: 13)
            } action: {
                context.openMainWindow()
            }
            Spacer(minLength: 0)
            FooterIcon(help: "Quit Control Box") {
                Image(systemName: "power")
                    .font(.system(size: 12, weight: .semibold))
            } action: {
                AppQuit.quitNow()
            }
        }
    }
}

private struct FooterIcon<Label: View>: View {
    let help: String
    @ViewBuilder let label: Label
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .controlCenterSurface(radius: 14, highlighted: hovering)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}
