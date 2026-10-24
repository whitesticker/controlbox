import SwiftUI

/// The grid on the panel's home view. With `editing` on (the Control Center
/// pane's preview), controls stop acting and instead drag to reorder, drag
/// out (or hover → remove badge) to hide, and accept drops from Available.
struct ControlCenterModuleGrid: View {
    let context: ControlCenterContext
    var editing = false
    let openDetail: (ControlCenterModule) -> Void

    @Bindable private var settings = ControlCenterSettings.shared
    @State private var dragging: ControlCenterModule?
    @State private var dragPoint = CGPoint.zero
    @State private var grabOffset = CGSize.zero
    @State private var draggedOut = false
    @State private var lastTarget: ControlCenterModule?
    @State private var dropTargeted = false

    private static let space = "controlCenterGrid"

    var body: some View {
        let grid = ControlCenterGrid(order: settings.order)
        Group {
            if grid.placements.isEmpty {
                Text(editing ? "Drag controls here from Available." : "No controls. Click Edit Controls to add some.")
                    .font(.system(size: ControlCenterDesign.subtitleSize))
                    .foregroundStyle(.secondary)
                    .frame(width: grid.size.width, height: ControlCenterDesign.rowHeight)
                    .controlCenterSurface()
            } else {
                ZStack(alignment: .topLeading) {
                    ForEach(grid.placements) { placement in
                        cell(placement, grid: grid)
                    }
                }
                .frame(width: grid.size.width, height: grid.size.height, alignment: .topLeading)
                .coordinateSpace(name: Self.space)
            }
        }
        .overlay {
            if editing && dropTargeted {
                RoundedRectangle(cornerRadius: ControlCenterDesign.moduleCornerRadius, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    .padding(-4)
            }
        }
        .modifier(AcceptsModuleDrops(enabled: editing, grid: grid, targeted: $dropTargeted))
    }

    @ViewBuilder
    private func cell(_ placement: ControlCenterPlacement, grid: ControlCenterGrid) -> some View {
        let frame = grid.frame(placement)
        let module = placement.module
        let isDragged = dragging == module
        let origin = isDragged
            ? CGPoint(x: dragPoint.x - grabOffset.width, y: dragPoint.y - grabOffset.height)
            : frame.origin
        ControlCenterModuleView(context: context, module: module, openDetail: openDetail)
            .allowsHitTesting(!editing)
            .overlay {
                if editing {
                    ModuleEditHandle(dragged: isDragged, removing: isDragged && draggedOut) {
                        withAnimation(.snappy) { settings.hide(module) }
                    }
                }
            }
            .frame(width: frame.width, height: frame.height)
            .scaleEffect(isDragged ? 1.05 : 1)
            .shadow(color: .black.opacity(isDragged ? 0.25 : 0), radius: 10, y: 4)
            .opacity(isDragged && draggedOut ? 0.45 : 1)
            .offset(x: origin.x, y: origin.y)
            .zIndex(isDragged ? 1 : 0)
            .gesture(reorder(module, frame: frame, grid: grid), including: editing ? .all : .subviews)
    }

    private func reorder(_ module: ControlCenterModule, frame: CGRect, grid: ControlCenterGrid) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.space))
            .onChanged { drag in
                if dragging != module {
                    dragging = module
                    grabOffset = CGSize(width: drag.startLocation.x - frame.minX, height: drag.startLocation.y - frame.minY)
                    lastTarget = nil
                }
                dragPoint = drag.location
                let bounds = CGRect(origin: .zero, size: grid.size).insetBy(dx: -28, dy: -28)
                draggedOut = !bounds.contains(drag.location)
                guard !draggedOut else { return }
                let target = grid.placements.first { $0.module != module && grid.frame($0).contains(drag.location) }
                guard let target else {
                    lastTarget = nil
                    return
                }
                guard target.module != lastTarget,
                      let from = settings.order.firstIndex(of: module),
                      let to = settings.order.firstIndex(of: target.module)
                else { return }
                lastTarget = target.module
                withAnimation(.snappy(duration: 0.22)) {
                    settings.order.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
                }
            }
            .onEnded { _ in
                withAnimation(.snappy) {
                    if draggedOut { settings.hide(module) }
                    dragging = nil
                    draggedOut = false
                }
            }
    }
}

/// Drops from the pane's Available list, placed before the control under
/// the pointer. Only in edit mode.
private struct AcceptsModuleDrops: ViewModifier {
    let enabled: Bool
    let grid: ControlCenterGrid
    @Binding var targeted: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.dropDestination(for: String.self) { items, location in
                guard let raw = items.first, let module = ControlCenterModule(rawValue: raw) else { return false }
                let settings = ControlCenterSettings.shared
                guard !settings.order.contains(module) else { return false }
                let target = grid.placements.first { grid.frame($0).contains(location) }
                withAnimation(.snappy) { settings.show(module, before: target?.module) }
                return true
            } isTargeted: { targeted = $0 }
        } else {
            content
        }
    }
}

/// Edit-mode cover: grab cursor, and a remove badge on hover (the same
/// pattern as System Monitor's quick launch tiles).
private struct ModuleEditHandle: View {
    let dragged: Bool
    let removing: Bool
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        RoundedRectangle(cornerRadius: ControlCenterDesign.moduleCornerRadius, style: .continuous)
            .fill(Color.primary.opacity(hovering && !dragged ? 0.06 : 0.001))
            .overlay(alignment: .topLeading) {
                if (hovering && !dragged) || removing {
                    Button(action: remove) {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 16))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color(white: 0.35))
                            .background(Circle().fill(.white).padding(2))
                    }
                    .buttonStyle(.plain)
                    .offset(x: -6, y: -6)
                    .help("Remove from Control Center")
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .onHover { hovering = $0 }
            .modifier(GrabPointer(dragged: dragged))
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

private struct GrabPointer: ViewModifier {
    let dragged: Bool

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.pointerStyle(dragged ? .grabActive : .grabIdle)
        } else {
            content
        }
    }
}

struct ControlCenterModuleView: View {
    let context: ControlCenterContext
    let module: ControlCenterModule
    let openDetail: (ControlCenterModule) -> Void

    var body: some View {
        switch module.size {
        case .small:
            SmallControlCenterModule(context: context, module: module)
        case .large:
            LargeControlCenterModule(context: context, module: module, openDetail: openDetail)
        case .slider:
            SliderControlCenterModule(context: context, module: module, openDetail: openDetail)
        }
    }
}

/// Night Shift / Sleep Now: one round button, name in the tooltip.
private struct SmallControlCenterModule: View {
    let context: ControlCenterContext
    let module: ControlCenterModule
    @State private var hovering = false

    private var active: Bool { module == .nightShift && context.nightShift.enabled }

    private var enabled: Bool { module != .nightShift || context.nightShift.isSupported }

    private var help: String {
        switch module {
        case .nightShift:
            if !context.nightShift.isSupported { return "Night Shift is not available on this Mac" }
            return context.nightShift.enabled ? "Night Shift: On" : "Night Shift: Off"
        case .sleepNow:
            return "Sleep Now"
        default:
            return module.title
        }
    }

    var body: some View {
        Button(action: tap) {
            ControlCenterIconCircle(module: module, active: active)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .controlCenterSurface(highlighted: hovering && enabled)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(module.title)
        .contextMenu {
            Button("\(module.pane.title) Settings…") { context.openPane(module.pane) }
        }
    }

    private func tap() {
        switch module {
        case .nightShift: context.nightShift.setEnabled(!context.nightShift.enabled)
        case .sleepNow: context.sleepNow()
        default: break
        }
    }
}

/// Caffeinate / Arrangement: icon, title, status; chevron on hover.
private struct LargeControlCenterModule: View {
    let context: ControlCenterContext
    let module: ControlCenterModule
    let openDetail: (ControlCenterModule) -> Void
    @State private var hovering = false

    private var active: Bool {
        switch module {
        case .caffeinate: context.caffeinate.isActive
        case .arrangement: context.liveArrangement != nil
        default: false
        }
    }

    var body: some View {
        Button(action: tap) {
            HStack(spacing: 8) {
                ControlCenterIconCircle(module: module, active: active)
                VStack(alignment: .leading, spacing: 1) {
                    Text(module.title)
                        .font(.system(size: ControlCenterDesign.titleSize, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        Text(subtitle(now: timeline.date))
                            .font(.system(size: ControlCenterDesign.subtitleSize))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if hovering {
                    Button { openDetail(module) } label: { ControlCenterChevron() }
                        .buttonStyle(.plain)
                        .help("Show details")
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .controlCenterSurface(highlighted: hovering)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .contextMenu {
            Button("\(module.pane.title) Settings…") { context.openPane(module.pane) }
        }
    }

    private func subtitle(now: Date) -> String {
        switch module {
        case .caffeinate:
            return context.caffeinateStatus(now: now)
        case .arrangement:
            if let live = context.liveArrangement { return live.name }
            return context.arrangement.applicablePresets.isEmpty ? "No layout for these displays" : "Not applied"
        default:
            return ""
        }
    }

    private func tap() {
        switch module {
        case .caffeinate: context.toggleCaffeinate()
        default: openDetail(module)
        }
    }
}

/// Display / Sound: title and the master slider. Clicking anywhere but the
/// slider opens the detail view; the chevron is only a hint.
private struct SliderControlCenterModule: View {
    let context: ControlCenterContext
    let module: ControlCenterModule
    let openDetail: (ControlCenterModule) -> Void
    @State private var hovering = false
    @State private var brightness = ControlCenterBrightness()

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(module.title)
                    .font(.system(size: ControlCenterDesign.titleSize, weight: .semibold))
                Spacer()
                ControlCenterChevron().opacity(hovering ? 1 : 0)
            }
            slider
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(RoundedRectangle(cornerRadius: ControlCenterDesign.moduleCornerRadius, style: .continuous))
        .onTapGesture { openDetail(module) }
        .controlCenterSurface(highlighted: hovering)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .contextMenu {
            Button("\(module.pane.title) Settings…") { context.openPane(module.pane) }
        }
    }

    @ViewBuilder
    private var slider: some View {
        if module == .display {
            let catalog = context.displays
            ControlCenterSlider(
                value: Binding(
                    get: { brightness.value(catalog) },
                    set: { brightness.set($0, catalog: catalog) }
                ),
                symbol: "sun.max.fill",
                enabled: !catalog.adjustableDisplays.isEmpty,
                onEditingChanged: { brightness.editingChanged($0, catalog: catalog) }
            )
        } else {
            let catalog = context.sound
            ControlCenterSlider(
                value: Binding(
                    get: { catalog.volume },
                    set: { catalog.setVolume($0) }
                ),
                symbol: ControlCenterSymbols.speaker(catalog.volume, muted: catalog.isMuted),
                enabled: !catalog.outputs.isEmpty
            )
        }
    }
}
