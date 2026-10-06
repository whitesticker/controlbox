import ControlBoxCore
import SwiftUI

struct PointerScrollPane: View {
    @Bindable var monitor: DualSenseMonitor

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SettingsSlider(
                        "Pointer speed",
                        caption: "Mice only; trackpads use System Settings.",
                        value: pointerSpeedBinding
                    )
                } header: {
                    Text("Pointer")
                }

                Section {
                    Toggle("Smooth scrolling", isOn: smoothScrollingBinding)
                    SettingsSlider("Wheel speed", value: wheelSpeedBinding)
                    Picker("Scroll direction", selection: scrollDirectionBinding) {
                        Text("Natural").tag("natural")
                        Text("Standard").tag("standard")
                    }
                    .pickerStyle(.radioGroup)
                } header: {
                    Text("Scroll")
                } footer: {
                    Text("MX DPI and thumb-wheel speed are on Mouse Settings.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Pointer & Scroll")
        }
    }

    private var pointerSpeedBinding: Binding<Double> {
        Binding(
            get: { monitor.macMouseProfile.resolvedPointerSpeed },
            set: { monitor.setMacPointerSpeed($0) }
        )
    }

    private var smoothScrollingBinding: Binding<Bool> {
        Binding(
            get: { monitor.macMouseProfile.resolvedSmoothScrolling },
            set: { monitor.setMacSmoothScrolling($0) }
        )
    }

    private var wheelSpeedBinding: Binding<Double> {
        Binding(
            get: { monitor.macMouseProfile.resolvedWheelScrollSpeed },
            set: { monitor.setMacWheelScrollSpeed($0) }
        )
    }

    private var scrollDirectionBinding: Binding<String> {
        Binding(
            get: { monitor.macMouseProfile.resolvedNaturalScrolling ? "natural" : "standard" },
            set: { monitor.setMacNaturalScrolling($0 == "natural") }
        )
    }
}
