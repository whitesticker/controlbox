import SwiftUI

/// The grid of modules on the panel's home view. With `editing` on (the
/// settings pane preview), modules stop acting and instead drag to reorder,
/// drag out (or hover → remove badge) to hide, and accept drops from Available.
struct ModuleGrid: View {
    @ObservedObject var store: LabStore
    var editing = false
    let openDetail: (ModuleKind) -> Void

    @State private var dragging: ModuleKind?
    @State private var dragPoint = CGPoint.zero
    @State private var grabOffset = CGSize.zero
    @State private var draggedOut = false
    @State private var lastTarget: ModuleKind?
    @State private var dropTargeted = false

    private static let space = "moduleGrid"

    var body: some View {
        let design = store.design
        let layout = GridLayout(order: store.order, design: design)
        Group {
            if layout.placements.isEmpty {
                Text(editing ? "Drag controls here from Available." : "No controls. Use Edit Controls to add some.")
                    .font(.system(size: design.subtitleSize))
                    .foregroundStyle(.secondary)
                    .frame(width: layout.size.width, height: design.rowHeight)
                    .moduleSurface(design)
            } else {
                GlassEffectContainer(spacing: design.spacing) {
                    ZStack(alignment: .topLeading) {
                        ForEach(layout.placements) { placement in
                            cell(placement, layout: layout)
                        }
                    }
                    .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
                    .coordinateSpace(name: Self.space)
                }
            }
        }
        .overlay {
            if editing && dropTargeted {
                RoundedRectangle(cornerRadius: design.moduleCornerRadius, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    .padding(-4)
            }
        }
        .modifier(AcceptsModuleDrops(enabled: editing, store: store, layout: layout, targeted: $dropTargeted))
    }

    @ViewBuilder
    private func cell(_ placement: Placement, layout: GridLayout) -> some View {
        let frame = layout.frame(placement)
        let kind = placement.kind
        let isDragged = dragging == kind
        let origin = isDragged
            ? CGPoint(x: dragPoint.x - grabOffset.width, y: dragPoint.y - grabOffset.height)
            : frame.origin
        ModuleView(store: store, placement: placement, openDetail: openDetail)
            .allowsHitTesting(!editing)
            .overlay {
                if editing {
                    EditHandle(dragged: isDragged, removing: isDragged && draggedOut, design: store.design) {
                        withAnimation(.snappy) { store.hide(kind) }
                    }
                }
            }
            .frame(width: frame.width, height: frame.height)
            .scaleEffect(isDragged ? 1.05 : 1)
            .shadow(color: .black.opacity(isDragged ? 0.25 : 0), radius: 10, y: 4)
            .opacity(isDragged && draggedOut ? 0.45 : 1)
            .offset(x: origin.x, y: origin.y)
            .zIndex(isDragged ? 1 : 0)
            .gesture(reorder(kind, frame: frame, layout: layout), including: editing ? .all : .subviews)
    }

    private func reorder(_ kind: ModuleKind, frame: CGRect, layout: GridLayout) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.space))
            .onChanged { drag in
                if dragging != kind {
                    dragging = kind
                    grabOffset = CGSize(width: drag.startLocation.x - frame.minX, height: drag.startLocation.y - frame.minY)
                    lastTarget = nil
                }
                dragPoint = drag.location
                let bounds = CGRect(origin: .zero, size: layout.size).insetBy(dx: -28, dy: -28)
                draggedOut = !bounds.contains(drag.location)
                guard !draggedOut else { return }
                let target = layout.placements.first { $0.kind != kind && layout.frame($0).contains(drag.location) }
                guard let target, target.kind != lastTarget,
                      let from = store.order.firstIndex(of: kind),
                      let to = store.order.firstIndex(of: target.kind)
                else {
                    if target == nil { lastTarget = nil }
                    return
                }
                lastTarget = target.kind
                withAnimation(.snappy(duration: 0.22)) {
                    store.order.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
                }
            }
            .onEnded { _ in
                withAnimation(.snappy) {
                    if draggedOut { store.hide(kind) }
                    dragging = nil
                    draggedOut = false
                }
            }
    }
}

/// Drops from the pane's Available list, inserted before the module under
/// the pointer. Only in edit mode: the drop target is an AppKit view.
private struct AcceptsModuleDrops: ViewModifier {
    let enabled: Bool
    @ObservedObject var store: LabStore
    let layout: GridLayout
    @Binding var targeted: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.dropDestination(for: String.self) { items, location in
                guard let raw = items.first, let kind = ModuleKind(rawValue: raw), !store.order.contains(kind) else { return false }
                let target = layout.placements.first { layout.frame($0).contains(location) }
                withAnimation(.snappy) {
                    if let target, let index = store.order.firstIndex(of: target.kind) {
                        store.order.insert(kind, at: index)
                    } else {
                        store.order.append(kind)
                    }
                }
                return true
            } isTargeted: { targeted = $0 }
        } else {
            content
        }
    }
}

/// Edit-mode cover: grab cursor, and a remove badge on hover (the same
/// pattern as System Monitor's quick launch tiles).
private struct EditHandle: View {
    let dragged: Bool
    let removing: Bool
    let design: CCDesign
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        RoundedRectangle(cornerRadius: design.moduleCornerRadius, style: .continuous)
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
            .pointerStyle(dragged ? .grabActive : .grabIdle)
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

struct ModuleView: View {
    @ObservedObject var store: LabStore
    let placement: Placement
    let openDetail: (ModuleKind) -> Void

    var body: some View {
        switch placement.kind.size {
        case .small:
            SmallModule(store: store, kind: placement.kind, tall: placement.height > 1)
        case .large:
            LargeModule(store: store, kind: placement.kind, tall: placement.height > 1, openDetail: openDetail)
        case .slider:
            SliderModule(store: store, kind: placement.kind, openDetail: openDetail)
        }
    }
}

/// Night Shift / Sleep: a round button with its label.
struct SmallModule: View {
    @ObservedObject var store: LabStore
    let kind: ModuleKind
    let tall: Bool
    @State private var hovering = false

    private var active: Bool { kind == .nightShift && store.nightShift }

    private var detail: String? {
        switch kind {
        case .nightShift: store.nightShift ? "\(Int(store.nightShiftKelvin)) K" : "Off"
        default: nil
        }
    }

    var body: some View {
        let design = store.design
        Button(action: tap) {
            VStack(spacing: tall ? 8 : 4) {
                IconCircle(kind: kind, active: active, design: design)
                if design.smallLabels {
                    VStack(spacing: 1) {
                        Text(kind.title)
                            .font(.system(size: design.subtitleSize, weight: .medium))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                        if tall, let detail {
                            Text(detail)
                                .font(.system(size: design.subtitleSize - 1))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .moduleSurface(design, highlighted: hovering)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("\(kind.paneTitle) Settings…") { store.openPane(kind.paneTitle) }
        }
        .help(kind == .sleepNow ? "Stop Caffeinate and sleep this Mac" : kind.title)
    }

    private func tap() {
        switch kind {
        case .nightShift: store.nightShift.toggle()
        case .sleepNow: store.sleepNow()
        default: break
        }
    }
}

/// Caffeinate / Arrangement: icon, title, status, and a chevron to details.
struct LargeModule: View {
    @ObservedObject var store: LabStore
    let kind: ModuleKind
    let tall: Bool
    let openDetail: (ModuleKind) -> Void
    @State private var hovering = false

    private var active: Bool {
        switch kind {
        case .caffeinate: store.caffeinateActive
        case .arrangement: store.presetsMatch && store.currentPreset != nil
        default: false
        }
    }

    var body: some View {
        let design = store.design
        Button(action: tap) {
            Group {
                if tall {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .top) {
                            IconCircle(kind: kind, active: active, design: design)
                            Spacer()
                            DetailChevron { openDetail(kind) }
                        }
                        Spacer(minLength: 4)
                        labels(design)
                    }
                    .padding(12)
                } else {
                    HStack(spacing: 8) {
                        IconCircle(kind: kind, active: active, design: design)
                        labels(design)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if design.largeChevron == .always || hovering {
                            DetailChevron { openDetail(kind) }
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 10)
                    .animation(.easeOut(duration: 0.12), value: hovering)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .moduleSurface(design, highlighted: hovering)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("\(kind.paneTitle) Settings…") { store.openPane(kind.paneTitle) }
        }
    }

    private func labels(_ design: CCDesign) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(kind.title)
                .font(.system(size: design.titleSize, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(subtitle(now: context.date))
                    .font(.system(size: design.subtitleSize))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
    }

    private func subtitle(now: Date) -> String {
        switch kind {
        case .caffeinate:
            return store.caffeinateStatus(now: now)
        case .arrangement:
            guard store.presetsMatch else { return "No layout for these displays" }
            return store.presets.first { $0.id == store.currentPreset }?.name ?? "Not applied"
        default:
            return ""
        }
    }

    private func tap() {
        switch kind {
        case .caffeinate: store.toggleCaffeinate()
        default: openDetail(kind)
        }
    }
}

/// Display / Sound: title and the master slider. Clicking anywhere but the
/// slider opens the detail view; the chevron is only a hint.
struct SliderModule: View {
    @ObservedObject var store: LabStore
    let kind: ModuleKind
    let openDetail: (ModuleKind) -> Void
    @State private var hovering = false

    var body: some View {
        let design = store.design
        let showChevron = design.largeChevron == .always || hovering
        VStack(alignment: .leading, spacing: 7) {
            if design.sliderTitles {
                HStack {
                    Text(kind.title)
                        .font(.system(size: design.titleSize, weight: .semibold))
                    Spacer()
                    chevron.opacity(showChevron ? 1 : 0)
                }
            }
            HStack(spacing: 8) {
                CCSlider(value: binding, symbol: symbol, design: design)
                if !design.sliderTitles && showChevron {
                    chevron.transition(.opacity)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(RoundedRectangle(cornerRadius: design.moduleCornerRadius, style: .continuous))
        .onTapGesture { openDetail(kind) }
        .moduleSurface(design, highlighted: hovering)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .contextMenu {
            Button("\(kind.paneTitle) Settings…") { store.openPane(kind.paneTitle) }
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.secondary)
            .frame(width: 20, height: 20)
            .background(Circle().fill(Color.primary.opacity(0.07)))
    }

    private var binding: Binding<Double> {
        kind == .display ? store.masterBrightness : $store.volume
    }

    private var symbol: String {
        kind == .display ? "sun.max.fill" : SoundSymbol.name(store.volume)
    }
}

enum SoundSymbol {
    static func name(_ volume: Double) -> String {
        switch volume {
        case ..<0.01: "speaker.slash.fill"
        case ..<0.34: "speaker.wave.1.fill"
        case ..<0.67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }
}
