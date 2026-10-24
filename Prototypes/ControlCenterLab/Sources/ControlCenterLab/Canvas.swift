import SwiftUI

struct Wallpaper: View {
    var body: some View {
        LinearGradient(
            colors: [Color(red: 0.22, green: 0.33, blue: 0.56), Color(red: 0.58, green: 0.40, blue: 0.52), Color(red: 0.86, green: 0.62, blue: 0.44)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct LabCanvas: View {
    @ObservedObject var store: LabStore
    let onEditControls: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $store.canvasTab) {
                ForEach(CanvasTab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 280)
            .padding(10)
            Divider()
            switch store.canvasTab {
            case .panel:
                panelCanvas
            case .pane:
                SettingsPaneMock(store: store)
            }
        }
    }

    private var panelCanvas: some View {
        ZStack(alignment: .top) {
            Wallpaper()
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    FakeMenuBar(store: store)
                    HStack(alignment: .top, spacing: 36) {
                        VStack(alignment: .leading, spacing: 8) {
                            caption("Control Box extra", "Click a chevron for a module’s detail view")
                            ControlCenterPanel(store: store, onEditControls: onEditControls)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            caption("Separate extras", "Same detail views, opened from their own icon")
                            HStack(alignment: .top, spacing: 20) {
                                ForEach(ModuleKind.allCases.filter(\.canBeExtra)) { kind in
                                    VStack(alignment: .leading, spacing: 6) {
                                        Label(
                                            store.extras.contains(kind) ? "\(kind.title): in menu bar" : "\(kind.title): off",
                                            systemImage: store.extras.contains(kind) ? "checkmark.circle.fill" : "circle"
                                        )
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.85))
                                        ExtraPanel(store: store, kind: kind)
                                            .opacity(store.extras.contains(kind) ? 1 : 0.55)
                                    }
                                }
                            }
                        }
                    }
                    .padding(32)
                }
            }
        }
    }

    private func caption(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.headline).foregroundStyle(.white)
            Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.75))
        }
    }
}

/// A strip that stands in for the menu bar: which icons the user would see.
private struct FakeMenuBar: View {
    @ObservedObject var store: LabStore

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "apple.logo")
            Text("Finder").fontWeight(.semibold)
            Spacer()
            ForEach(ModuleKind.allCases.filter { store.extras.contains($0) }) { kind in
                ModuleIcon(kind: kind, filled: kind == .caffeinate && store.caffeinateActive, size: 16)
            }
            if let ring = LabIcons.ring {
                Image(nsImage: ring).renderingMode(.template).resizable().scaledToFit().frame(width: 14, height: 14)
            }
            Image(systemName: "switch.2")
            Text(Date.now, format: .dateTime.weekday().hour().minute())
        }
        .font(.system(size: 13))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(height: 26)
        .frame(minWidth: 1000)
        .background(.black.opacity(0.18))
    }
}
