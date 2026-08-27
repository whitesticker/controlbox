import AppKit
import ControlBoxCore
import SwiftUI

struct DisplaysPane: View {
    @Bindable var catalog: DisplayCatalog

    var body: some View {
        NavigationStack {
            Form {
                if catalog.displays.isEmpty {
                    Section {
                        Text("No displays reported.")
                    }
                } else {
                    unifiedSection

                    ForEach(catalog.displays) { display in
                        Section {
                            SettingsSlider(
                                "Brightness",
                                value: brightnessBinding(display),
                                enabled: display.canAdjustBrightness && !catalog.unifiedEnabled
                            )
                            if !display.isBuiltIn {
                                SettingsSlider(
                                    "Contrast",
                                    value: contrastBinding(display),
                                    enabled: display.canAdjustContrast
                                )
                            }
                        } header: {
                            Text(display.name)
                        } footer: {
                            Text(footer(for: display))
                        }
                    }
                }

                Section {
                    Text("External brightness and contrast use DDC/CI matching and Apple-silicon I2C from [MonitorControl](https://github.com/MonitorControl/MonitorControl) (MIT), © MonitorControl contributors.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Display Brightness")
            .animation(.easeInOut(duration: 0.2), value: catalog.unifiedEnabled)
            .onAppear { catalog.refresh() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
                catalog.refresh()
            }
        }
    }

    @ViewBuilder
    private var unifiedSection: some View {
        Section {
            Toggle("One slider for all displays", isOn: unifiedEnabledBinding)
                .disabled(!catalog.canUnify && !catalog.unifiedEnabled)
            if catalog.unifiedEnabled {
                SettingsSlider("Brightness", value: unifiedBrightnessBinding)
            }
        } footer: {
            Text(unifiedFooter)
        }
    }

    private var unifiedEnabledBinding: Binding<Bool> {
        Binding(
            get: { catalog.unifiedEnabled },
            set: { catalog.setUnifiedEnabled($0) }
        )
    }

    private var unifiedBrightnessBinding: Binding<Double> {
        Binding(
            get: { catalog.unifiedBrightness },
            set: { catalog.setUnifiedBrightness($0) }
        )
    }

    private var unifiedFooter: String {
        if catalog.canUnify {
            return "On enable, Control Box remembers how bright each panel is relative to the brightest one. The shared slider keeps that mix: 0% is all dark, 100% raises the brightest panel to full and scales the others with it. Turn it off to set each display again."
        }
        return "Connect at least two brightness-adjustable displays to link them."
    }

    private func brightnessBinding(_ display: AttachedDisplay) -> Binding<Double> {
        Binding(
            get: { catalog.displays.first { $0.id == display.id }?.brightness ?? display.brightness },
            set: { catalog.setBrightness($0, id: display.id) }
        )
    }

    private func contrastBinding(_ display: AttachedDisplay) -> Binding<Double> {
        Binding(
            get: { catalog.displays.first { $0.id == display.id }?.contrast ?? display.contrast },
            set: { catalog.setContrast($0, id: display.id) }
        )
    }

    private func footer(for display: AttachedDisplay) -> String {
        if display.isDummy {
            return display.detail
        }
        if display.canAdjustBrightness || display.canAdjustContrast {
            return display.detail
        }
        if display.isBuiltIn {
            return "Built-in brightness is not available on this panel."
        }
        return "\(display.detail). HDMI on some Apple silicon Macs cannot do DDC; USB-C / DisplayPort usually can."
    }
}
