import ControlBoxCore
import SwiftUI

struct PointerScrollPane: View {
    @Bindable var monitor: DualSenseMonitor

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SettingsSlider("Pointer speed", value: pointerSpeedBinding)
                    Toggle("Smooth scrolling", isOn: smoothScrollingBinding)
                    SettingsSlider("Wheel speed", value: wheelSpeedBinding)
                    SettingsSlider("Thumb wheel speed", value: thumbSpeedBinding)
                    Picker("Scroll direction", selection: scrollDirectionBinding) {
                        Text("Natural").tag("natural")
                        Text("Standard").tag("standard")
                    }
                    .pickerStyle(.radioGroup)
                } footer: {
                    footerBullets(
                        "Pointer speed: USB and Bluetooth mice, including every MX Master.",
                        "Wheel speed, smooth scrolling, and direction are shared once a mouse is attached.",
                        "Accessibility is required for wheel speed.",
                        "DualSense and Siri Remote keep their own sliders on the device page."
                    )
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

    private var thumbSpeedBinding: Binding<Double> {
        Binding(
            get: { monitor.macMouseProfile.resolvedThumbScrollSpeed },
            set: { monitor.setMacThumbScrollSpeed($0) }
        )
    }

    private var scrollDirectionBinding: Binding<String> {
        Binding(
            get: { monitor.macMouseProfile.resolvedNaturalScrolling ? "natural" : "standard" },
            set: { monitor.setMacNaturalScrolling($0 == "natural") }
        )
    }
}
