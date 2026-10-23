import SwiftUI
import UniformTypeIdentifiers

/// Pane → Menu Bar Icon. The top row is drawn like the menu bar (same
/// renderer as the status item); the bottom row holds what is left. Drag a
/// tile between the rows, or within the top row to reorder. Changes apply
/// live while dragging, so the real menu bar follows along.
struct MenuBarIconEditor: View {
    @ObservedObject private var store = PreferencesStore.shared
    @State private var dragging: MenuBarItem?
    @State private var hovered: MenuBarItem?
    @State private var snapshot: SystemSnapshot?

    /// Each tile's image carries the renderer's 2 pt edge padding, so this
    /// padding and spacing make tile-to-tile match `itemGap` in the menu bar.
    private static let shownPadding: CGFloat = 3
    private static let shownSpacing: CGFloat = MenuBarIconRenderer.itemGap - 2 * (2 + shownPadding)

    private var available: [MenuBarItem] {
        MenuBarItem.allCases.filter { !store.menuBarItems.contains($0) }
    }

    /// Live values while the extra is running, examples otherwise.
    private var liveSnapshot: SystemSnapshot? {
        store.menuBarEnabled ? snapshot : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            label("In menu bar")
            shownRow
            label("Available")
            availableRow
        }
        .onReceive(SystemMonitor.shared.tickSnapshot) { snapshot = $0 }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
    }

    private var shownRow: some View {
        MenuBarFlowLayout(spacing: Self.shownSpacing, lineSpacing: 4) {
            if store.menuBarItems.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "gauge.with.dots.needle.33percent")
                    Text("Drag items here")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .foregroundStyle(.white)
                .frame(height: MenuBarIconRenderer.height + 6)
                .padding(.horizontal, 6)
            }
            ForEach(store.menuBarItems) { item in
                face(item)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Self.shownPadding)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(.white.opacity(hovered == item ? 0.16 : 0))
                    )
                    .overlay(alignment: .leading) {
                        if item != store.menuBarItems.first {
                            Rectangle()
                                .fill(.white.opacity(0.35))
                                .frame(width: 1, height: 14)
                                .offset(x: -(Self.shownSpacing + 1) / 2)
                        }
                    }
                    .menuBarDrag(item, dragging: $dragging)
                    .onDrop(of: [UTType.text], delegate: MenuBarDropDelegate(
                        action: .show(before: item), store: store, dragging: $dragging
                    ))
                    .tileHover(item, hovered: $hovered)
                    .contextMenu {
                        Button("Remove from Menu Bar") {
                            withAnimation(.snappy) { store.hideMenuBarItem(item) }
                        }
                    }
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(white: 0.13))
        )
        .contentShape(Rectangle())
        .onDrop(of: [UTType.text], delegate: MenuBarDropDelegate(action: .show(before: nil), store: store, dragging: $dragging))
    }

    private var availableRow: some View {
        MenuBarFlowLayout(spacing: 8, lineSpacing: 8) {
            if available.isEmpty {
                Text("Everything is in the menu bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: MenuBarIconRenderer.height + 22)
                    .padding(.horizontal, 4)
            }
            ForEach(available) { item in
                VStack(spacing: 3) {
                    face(item)
                        .foregroundStyle(.primary)
                    Text(item.title)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(hovered == item ? 0.1 : 0.05))
                )
                .menuBarDrag(item, dragging: $dragging)
                .tileHover(item, hovered: $hovered)
                .contextMenu {
                    Button("Add to Menu Bar") {
                        withAnimation(.snappy) { store.showMenuBarItem(item) }
                    }
                }
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
        .contentShape(Rectangle())
        .onDrop(of: [UTType.text], delegate: MenuBarDropDelegate(action: .hide, store: store, dragging: $dragging))
    }

    private func face(_ item: MenuBarItem) -> some View {
        Image(nsImage: MenuBarIconRenderer.render([(item, item.text(liveSnapshot))]))
            .renderingMode(.template)
            .accessibilityLabel(item.title)
    }
}

private extension View {
    func menuBarDrag(_ item: MenuBarItem, dragging: Binding<MenuBarItem?>) -> some View {
        onDrag {
            dragging.wrappedValue = item
            return NSItemProvider(object: item.rawValue as NSString)
        }
    }

    func tileHover(_ item: MenuBarItem, hovered: Binding<MenuBarItem?>) -> some View {
        help(item.title)
            .onHover { inside in
                if inside {
                    hovered.wrappedValue = item
                } else if hovered.wrappedValue == item {
                    hovered.wrappedValue = nil
                }
            }
    }
}

private struct MenuBarDropDelegate: DropDelegate {
    enum Action {
        /// Into the menu bar row, before `item` (nil = at the end).
        case show(before: MenuBarItem?)
        case hide
    }

    let action: Action
    let store: PreferencesStore
    @Binding var dragging: MenuBarItem?

    func dropEntered(info: DropInfo) {
        guard let dragging else { return }
        withAnimation(.snappy) {
            switch action {
            case .show(let target):
                if let target {
                    guard target != dragging, let index = store.menuBarItems.firstIndex(of: target) else { return }
                    store.showMenuBarItem(dragging, at: index)
                } else if !store.menuBarItems.contains(dragging) {
                    store.showMenuBarItem(dragging)
                }
            case .hide:
                store.hideMenuBarItem(dragging)
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

/// Left-to-right rows that wrap at the proposed width.
private struct MenuBarFlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let origins = arrange(width: bounds.width, subviews: subviews).origins
        for (subview, origin) in zip(subviews, origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat?, subviews: Subviews) -> (origins: [CGPoint], size: CGSize) {
        let maxWidth = width ?? .infinity
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            usedWidth = max(usedWidth, x + size.width)
            x += size.width + spacing
        }
        return (origins, CGSize(width: usedWidth, height: y + rowHeight))
    }
}
