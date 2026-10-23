import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Name, icon, and launch for the quick-launch row's bundle IDs. Control Box
/// itself never goes through `NSWorkspace`: another copy of the same bundle
/// ID (a Debug build, or `/Applications`) would launch instead of showing
/// this window.
enum QuickLauncher {
    private static var iconCache: [String: NSImage] = [:]

    static func isSelf(_ bundleID: String) -> Bool {
        bundleID == Bundle.main.bundleIdentifier
    }

    static func url(for bundleID: String) -> URL? {
        isSelf(bundleID) ? Bundle.main.bundleURL : NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    static func name(for bundleID: String) -> String {
        guard let url = url(for: bundleID), let bundle = Bundle(url: url) else { return bundleID }
        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
        if let name, !name.isEmpty { return name }
        return url.deletingPathExtension().lastPathComponent
    }

    static func icon(for bundleID: String) -> NSImage? {
        if let cached = iconCache[bundleID] { return cached }
        let icon: NSImage?
        if isSelf(bundleID) {
            icon = NSApp.applicationIconImage
        } else {
            icon = url(for: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
        }
        if let icon { iconCache[bundleID] = icon }
        return icon
    }

    @MainActor
    static func launch(_ bundleID: String) {
        if isSelf(bundleID) {
            WindowActions.openMain?("main")
            NSApp.activate()
            return
        }
        guard let url = url(for: bundleID) else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

// MARK: - Shared look

/// The card both the menu row and the System Monitor pane editor draw, so
/// the pane shows exactly what the menu will.
struct QuickLauncherCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 0) {
            content
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .frame(width: menuRowWidth - 16)
        .background(
            RoundedRectangle(cornerRadius: DashStyle.cardCorner, style: .continuous)
                .fill(DashColors.cardBackground)
        )
    }
}

/// One **tile**: the app icon with a hover highlight.
struct QuickLauncherTileFace: View {
    let bundleID: String
    var highlighted = false

    var body: some View {
        Group {
            if let icon = QuickLauncher.icon(for: bundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 20))
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 26, height: 26)
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(highlighted ? 0.1 : 0))
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Menu row

/// Bottom card of the System Monitor menu. `StatusItemController` sets
/// `apps` directly whenever the list changes rather than having the row
/// observe the store.
struct QuickLauncherRow: View {
    var apps: [String]
    var launch: (String) -> Void

    var body: some View {
        QuickLauncherCard {
            ForEach(apps, id: \.self) { bundleID in
                QuickLauncherMenuTile(bundleID: bundleID) { launch(bundleID) }
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(width: menuRowWidth)
    }
}

private struct QuickLauncherMenuTile: View {
    let bundleID: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            QuickLauncherTileFace(bundleID: bundleID, highlighted: hovering)
        }
        .buttonStyle(.plain)
        .help(QuickLauncher.name(for: bundleID))
        .onHover { hovering = $0 }
    }
}

// MARK: - Pane editor

/// The same card as the menu, editable: drag a tile onto another to reorder
/// (tiles slide aside while dragging), hover a tile for its remove badge.
struct QuickLauncherEditor: View {
    @ObservedObject private var store = PreferencesStore.shared
    @State private var dragging: String?
    @State private var hovered: String?

    var body: some View {
        QuickLauncherCard {
            if store.launcherApps.isEmpty {
                Text("No apps")
                    .font(DashStyle.labelFont)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            ForEach(store.launcherApps, id: \.self) { bundleID in
                tile(bundleID)
                    .frame(maxWidth: .infinity)
                    .onDrag {
                        dragging = bundleID
                        return NSItemProvider(object: bundleID as NSString)
                    }
                    .onDrop(
                        of: [UTType.text],
                        delegate: QuickLauncherDropDelegate(target: bundleID, store: store, dragging: $dragging)
                    )
            }
        }
    }

    private func tile(_ bundleID: String) -> some View {
        let name = QuickLauncher.name(for: bundleID)
        return QuickLauncherTileFace(bundleID: bundleID, highlighted: hovered == bundleID)
            .overlay(alignment: .topTrailing) {
                if hovered == bundleID {
                    Button {
                        withAnimation(.snappy) { store.removeLauncherApp(bundleID) }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .offset(x: 5, y: -5)
                    .accessibilityLabel("Remove \(name)")
                }
            }
            .help(name)
            .onHover { inside in
                if inside {
                    hovered = bundleID
                } else if hovered == bundleID {
                    hovered = nil
                }
            }
            .contextMenu {
                Button("Remove \(name)") {
                    withAnimation(.snappy) { store.removeLauncherApp(bundleID) }
                }
            }
    }
}

private struct QuickLauncherDropDelegate: DropDelegate {
    let target: String
    let store: PreferencesStore
    @Binding var dragging: String?

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target,
              let from = store.launcherApps.firstIndex(of: dragging),
              let to = store.launcherApps.firstIndex(of: target) else { return }
        withAnimation(.snappy) {
            store.moveLauncherApps(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
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
