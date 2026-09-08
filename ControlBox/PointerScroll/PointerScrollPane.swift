import ControlBoxCore
import SwiftUI

struct PointerScrollPane: View {
    @Bindable var monitor: DualSenseMonitor

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SettingsSlider("Pointer speed", value: pointerSpeedBinding)
                } header: {
                    Text("Pointer")
                } footer: {
                    footerBullets(
                        "Scales cursor motion from every USB and Bluetooth mouse.",
                        "Trackpads stay on System Settings.",
                        "MX also gets a HID++ pointer scale so a DPI change does not change cursor feel.",
                        "DualSense and Siri Remote keep their own sliders on the device page."
                    )
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
                    footerBullets(
                        "Wheel speed scales vertical and horizontal mouse-wheel events.",
                        "An MX thumb wheel in a scroll mode uses the Thumb wheel slider on Calibration.",
                        "Trackpad and Magic Mouse gestures stay native.",
                        "Smooth scrolling also turns on the MX high-res wheel.",
                        "Accessibility is required for wheel speed.",
                        "DPI is on Calibration."
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

    private var scrollDirectionBinding: Binding<String> {
        Binding(
            get: { monitor.macMouseProfile.resolvedNaturalScrolling ? "natural" : "standard" },
            set: { monitor.setMacNaturalScrolling($0 == "natural") }
        )
    }
}
