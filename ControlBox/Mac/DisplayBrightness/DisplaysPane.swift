import AppKit
import ControlBoxCore
import SwiftUI

struct DisplaysPane: View {
    @Bindable var catalog: DisplayCatalog
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Show in menu bar", isOn: $settings.brightnessMenuBarEnabled)
                } footer: {
                    footerBullets(
                        "Separate extra. The Control Box icon stays.",
                        "Click for brightness sliders.",
                        "Hide from Menu Bar turns this extra off; it does not quit Control Box."
                    )
                }

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
            unifiedFooter
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

    private var unifiedFooter: Text {
        if catalog.canUnify {
            return footerBullets(
                "Remembers each panel’s mix relative to the brightest.",
                "0% is all dark; 100% raises the brightest to full and scales the rest.",
                "Off to set each display again."
            )
        }
        return Text("Needs two brightness-adjustable displays.")
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
            return "Built-in brightness is not available here."
        }
        return "\(display.detail). HDMI on some Apple silicon Macs cannot do DDC; USB-C / DisplayPort usually can."
    }
}
