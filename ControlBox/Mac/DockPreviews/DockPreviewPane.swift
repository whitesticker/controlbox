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
                    Text("Accessibility required.")
                }

                Section {
                    Toggle("Show window previews in the app switcher", isOn: switcherBinding)
                    SettingsSlider(
                        "Preview size",
                        description: "Switcher only",
                        value: switcherScaleBinding,
                        in: Double(DockPreview.minCardScale)...Double(DockPreview.maxSwitcherCardScale),
                        enabled: catalog.switcherEnabled,
                        valueText: switcherScaleText
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
                        Text("Live thumbnails need Screen Recording.")
                    }
                }

                Section {
                    Toggle(isOn: cardSwitchBinding) {
                        SettingsRowLabel("Switch to Space", "A card on another Space slides that display to it.")
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
                        SettingsRowLabel(
                            "Switch to Space",
                            "Command-Tab to an app with no window here goes to its Space."
                        )
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

}
