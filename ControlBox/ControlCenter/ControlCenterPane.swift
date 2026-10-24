import SwiftUI

/// Edits the Control Box menu bar extra's panel. The preview is the editor:
/// drag a control to move it, drag it out (or hover → remove badge) to hide
/// it, drag a row from Available into the preview to add it.
struct ControlCenterPane: View {
    let context: ControlCenterContext
    @Bindable private var settings = ControlCenterSettings.shared
    @Bindable private var appSettings = AppSettings.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        PreviewChrome {
                            ControlCenterPanelView(context: context, editing: true)
                        }
                        .padding(.vertical, 20)
                        Spacer()
                    }
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.22, green: 0.33, blue: 0.56),
                                Color(red: 0.58, green: 0.40, blue: 0.52),
                                Color(red: 0.86, green: 0.62, blue: 0.44),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    )
                } header: {
                    Text("Layout")
                } footer: {
                    Text("Click the Control Box icon in the menu bar to open this panel. Drag a control to move it. Drag it out, or hover and click −, to remove it. Small controls fill the gaps after large ones.")
                }

                Section {
                    if settings.available.isEmpty {
                        Text("Every control is in Control Center.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(settings.available) { module in
                        AvailableRow(module: module)
                    }
                } header: {
                    Text("Available")
                } footer: {
                    Text("Drag into the preview to place a control, or click + to add it at the end.")
                }

                Section {
                    Toggle(isOn: $appSettings.brightnessMenuBarEnabled) { menuBarLabel(.display) }
                    Toggle(isOn: $appSettings.soundMenuBarEnabled) { menuBarLabel(.sound) }
                    Toggle(isOn: $appSettings.caffeinateMenuBarEnabled) { menuBarLabel(.caffeinate) }
                } header: {
                    Text("Show in Menu Bar")
                } footer: {
                    Text("Adds its own menu bar icon that opens the same detail view. It stays in Control Center either way.")
                }

                Section {
                    Button("Reset to Default Layout") {
                        withAnimation(.snappy) { settings.resetLayout() }
                    }
                    .disabled(settings.order == ControlCenterModule.defaultOrder)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Control Center")
        }
    }

    private func menuBarLabel(_ module: ControlCenterModule) -> some View {
        HStack(spacing: 8) {
            ControlCenterGlyph(module: module, size: 15)
                .foregroundStyle(module.tint)
                .frame(width: 20)
            Text(module.pane.title)
        }
    }
}

/// The panel's own chrome around the pane preview.
private struct PreviewChrome<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ControlCenterDesign.panelCornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular, in: shape)
                .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
        } else {
            content
                .background(shape.fill(.regularMaterial))
                .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
        }
    }
}

private struct AvailableRow: View {
    let module: ControlCenterModule

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
            ControlCenterGlyph(module: module, size: 16)
                .foregroundStyle(module.tint)
                .frame(width: 22)
            SettingsRowLabel(module.title, sizeLabel)
            Spacer()
            Button {
                withAnimation(.snappy) { ControlCenterSettings.shared.show(module) }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Palette.good)
                    .font(.system(size: 15))
            }
            .buttonStyle(.plain)
            .help("Add to Control Center")
        }
        .contentShape(Rectangle())
        .draggable(module.rawValue) {
            HStack(spacing: 6) {
                ControlCenterGlyph(module: module, size: 14)
                Text(module.title).font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(.regularMaterial))
        }
    }

    private var sizeLabel: String {
        switch module.size {
        case .small: "Button"
        case .large: "Two cells wide"
        case .slider: "Slider, full width"
        }
    }
}
