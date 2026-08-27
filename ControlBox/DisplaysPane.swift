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
                    ForEach(catalog.displays) { display in
                        Section {
                            SettingsSlider(
                                "Brightness",
                                value: brightnessBinding(display),
                                enabled: display.canAdjustBrightness
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
            .navigationTitle("Displays")
            .onAppear { catalog.refresh() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
                catalog.refresh()
            }
        }
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
