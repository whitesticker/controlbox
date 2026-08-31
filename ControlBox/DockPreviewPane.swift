import ControlBoxCore
import SwiftUI

struct DockPreviewPane: View {
    @Bindable var catalog: DockPreviewCatalog

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Show window previews on the Dock", isOn: enabledBinding)
                } footer: {
                    Text(footer)
                }

                Section {
                    Toggle("Show window previews in the app switcher", isOn: switcherBinding)
                    SettingsSlider(
                        "Preview size",
                        value: switcherScaleBinding,
                        in: Double(DockPreview.minCardScale)...Double(DockPreview.maxSwitcherCardScale),
                        enabled: catalog.switcherEnabled,
                        valueText: switcherScaleText
                    )
                } footer: {
                    Text("While Command-Tab (or Next / Previous application) is up, show that app’s window cards — same catalog as Dock hover, without titles or the close / minimize / quit HUD. Click a card to open that window. Preview size is only for the switcher. Off until this toggle is on.")
                }

                Section {
                    SettingsSlider(
                        "Hover delay",
                        value: delayBinding,
                        in: 0.08...0.8,
                        enabled: catalog.enabled,
                        valueText: delayText
                    )
                    SettingsSlider(
                        "Preview size",
                        value: scaleBinding,
                        in: Double(DockPreview.minCardScale)...Double(DockPreview.maxCardScale),
                        enabled: catalog.enabled,
                        valueText: scaleText
                    )
                    Toggle("Show Dock icon names", isOn: namesBinding)
                } footer: {
                    Text(optionsFooter)
                }

                Section {
                    LabeledContent("Screen Recording") {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(catalog.hasScreenRecording ? Palette.good : Palette.bad)
                                .frame(width: 8, height: 8)
                            Text(catalog.hasScreenRecording ? "Allowed" : "Titles only")
                        }
                    }
                    if !catalog.hasScreenRecording {
                        Button("Request Screen Recording…") {
                            catalog.requestScreenRecording()
                        }
                        Button("Open Screen Recording Settings") {
                            catalog.openScreenRecordingSettings()
                        }
                    }
                } footer: {
                    Text("Live thumbnails need Screen Recording. Without it the panel still lists every window by title. This is not the same grant as System Audio Recording on Sound.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Dock Previews")
            .onAppear { catalog.refreshScreenRecording() }
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { catalog.enabled },
            set: { catalog.setEnabled($0) }
        )
    }

    private var delayBinding: Binding<Double> {
        Binding(
            get: { catalog.showDelay },
            set: { catalog.setShowDelay($0) }
        )
    }

    private var switcherBinding: Binding<Bool> {
        Binding(
            get: { catalog.switcherEnabled },
            set: { catalog.setSwitcherEnabled($0) }
        )
    }

    private var namesBinding: Binding<Bool> {
        Binding(
            get: { catalog.showDockNames },
            set: { catalog.setShowDockNames($0) }
        )
    }

    private var scaleBinding: Binding<Double> {
        Binding(
            get: { Double(catalog.cardScale) },
            set: { catalog.setCardScale(CGFloat($0)) }
        )
    }

    private var switcherScaleBinding: Binding<Double> {
        Binding(
            get: { Double(catalog.switcherCardScale) },
            set: { catalog.setSwitcherCardScale(CGFloat($0)) }
        )
    }

    private var optionsFooter: String {
        "Hover delay is how long the pointer stays on an icon before the panel first appears; moving to another icon updates immediately. Dock preview size defaults to 130%. Dock icon names are the native labels on pinned icons. Off clears them and keeps a copy so they come back when you turn this on. Icons that are only running (not pinned) may still show a name. The Dock is not restarted."
    }

    private var delayText: String {
        String(format: "%.2fs", catalog.showDelay)
    }

    private var scaleText: String {
        "\(Int((catalog.cardScale * 100).rounded()))%"
    }

    private var switcherScaleText: String {
        "\(Int((catalog.switcherCardScale * 100).rounded()))%"
    }

    private var footer: String {
        if catalog.enabled {
            return "Point at a Dock icon that has open windows to see them. Apps with no windows stay native — no empty card. Click a card to open that window. Hover a card on this Space for close (red), minimize (yellow) or restore (green), and quit (purple). Cards on another Space have no HUD. The preview hides while a Dock right-click menu is open. Accessibility must be on. Native Dock clicks still work."
        }
        return "Off until you turn it on. Then hovering a Dock icon shows that app’s open windows, including minimized ones and windows on other Spaces."
    }
}
