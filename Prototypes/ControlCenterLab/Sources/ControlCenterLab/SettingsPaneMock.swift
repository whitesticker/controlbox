import SwiftUI

/// Mock of the Control Box **Control Center** pane that Edit Controls… opens.
/// The preview is the editor: drag modules to rearrange, drag one out (or
/// hover → remove badge) to hide it, drag from Available to add.
struct SettingsPaneMock: View {
    @ObservedObject var store: LabStore

    var body: some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    Text("🎛️")
                        .font(.system(size: 16))
                        .frame(width: 30, height: 30)
                        .glassEffect(.regular.tint(Color.blue.opacity(0.42)), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Control Center").font(.title3.weight(.semibold))
                        Text("Click the Control Box icon in the menu bar to open it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                HStack {
                    Spacer()
                    ControlCenterPanel(store: store, editing: true)
                        .padding(.vertical, 20)
                    Spacer()
                }
                .background(
                    Wallpaper()
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                )
            } header: {
                Text("Layout")
            } footer: {
                Text("Drag a control to move it. Drag it out of the panel, or hover and click −, to remove it. Small controls fill the gaps after large ones.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                if store.available.isEmpty {
                    Text("Every control is in Control Center.")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.available) { kind in
                    AvailableRow(store: store, kind: kind)
                }
            } header: {
                Text("Available")
            } footer: {
                Text("Drag into the preview to place it, or click + to add it at the end.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(ModuleKind.allCases.filter(\.canBeExtra)) { kind in
                    Toggle(isOn: Binding(
                        get: { store.extras.contains(kind) },
                        set: { on in
                            if on { store.extras.insert(kind) } else { store.extras.remove(kind) }
                        }
                    )) {
                        HStack(spacing: 8) {
                            ModuleIcon(kind: kind, size: 15)
                                .foregroundStyle(kind.tint)
                                .frame(width: 20)
                            Text(kind.title)
                        }
                    }
                }
            } header: {
                Text("Show in Menu Bar")
            } footer: {
                Text("Adds its own menu bar icon that opens the same detail view. It stays in Control Center either way.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Reset to Default Layout") {
                    withAnimation(.snappy) { store.resetLayout() }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AvailableRow: View {
    @ObservedObject var store: LabStore
    let kind: ModuleKind

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
            ModuleIcon(kind: kind, size: 16)
                .foregroundStyle(kind.tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.title)
                Text(sizeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                withAnimation(.snappy) { store.show(kind) }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Color.green)
                    .font(.system(size: 15))
            }
            .buttonStyle(.plain)
            .help("Add to Control Center")
        }
        .contentShape(Rectangle())
        .draggable(kind.rawValue) {
            HStack(spacing: 6) {
                ModuleIcon(kind: kind, size: 14)
                Text(kind.title).font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(.regularMaterial))
        }
    }

    private var sizeLabel: String {
        let (w, h) = GridLayout.span(kind, design: store.design)
        switch kind.size {
        case .small: return "Button · \(w)×\(h)"
        case .large: return "Module · \(w)×\(h)"
        case .slider: return "Slider · full width"
        }
    }
}
