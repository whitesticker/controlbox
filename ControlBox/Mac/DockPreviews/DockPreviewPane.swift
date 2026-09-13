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
                    footer
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
                    footerBullets(
                        "Same cards while Command-Tab is up, without titles or HUD.",
                        "Click a card to open that window.",
                        "Preview size is only for the switcher. Off until this toggle is on."
                    )
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
                } footer: {
                    footerBullets(
                        "Hover delay is the first wait; moving to another icon updates immediately.",
                        "Dock preview size defaults to 130%."
                    )
                }

                if !catalog.hasScreenRecording {
                    Section {
                        LabeledContent("Screen Recording") {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Palette.bad)
                                    .frame(width: 8, height: 8)
                                Text("Titles only")
                            }
                        }
                        Button("Request Screen Recording…") {
                            catalog.requestScreenRecording()
                        }
                        Button("Open Screen Recording Settings") {
                            catalog.openScreenRecordingSettings()
                        }
                    } footer: {
                        footerBullets(
                            "Live thumbnails need Screen Recording.",
                            "Without it, windows still list by title.",
                            "Not the same grant as System Audio Recording on Sound."
                        )
                    }
                }

                Section {
                    Toggle(isOn: cardSwitchBinding) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Switch to Space")
                            Text("A card on another Space slides that display to it.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    HStack {
                        Text("When already in front")
                        Spacer()
                        Picker("When already in front", selection: cardFrontActionBinding) {
                            Text("Nothing").tag(DockClickFrontAction.none)
                            Text("Minimize").tag(DockClickFrontAction.minimize)
                            Text("Hide").tag(DockClickFrontAction.hide)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                } header: {
                    Text("Card click")
                }

                Section {
                    Toggle(isOn: switcherSelectBinding) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Switch to Space")
                            Text("Pick an app in Command-Tab that has no window on a current Space: go to the Space that has one, on this display or another.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } header: {
                    Text("App switcher select")
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

    private var cardSwitchBinding: Binding<Bool> {
        Binding(
            get: { catalog.cardSwitchToSpace },
            set: { catalog.setCardSwitchToSpace($0) }
        )
    }

    private var cardFrontActionBinding: Binding<DockClickFrontAction> {
        Binding(
            get: { catalog.cardFrontAction },
            set: { catalog.setCardFrontAction($0) }
        )
    }

    private var switcherSelectBinding: Binding<Bool> {
        Binding(
            get: { catalog.switcherSelectSwitchToSpace },
            set: { catalog.setSwitcherSelectSwitchToSpace($0) }
        )
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

    private var footer: Text {
        if catalog.enabled {
            return footerBullets(
                "Hover a Dock icon that has windows to preview them. Apps with none stay native.",
                "Click a card to focus. HUD: close, minimize/restore, quit. Other Spaces always show quit.",
                "Hides while a Dock right-click menu is open.",
                "Accessibility must be on. Native Dock clicks still work."
            )
        }
        return footerBullets(
            "Off until this is on.",
            "Then hover a Dock icon to see that app’s windows, including minimized and other Spaces."
        )
    }
}
