import IRemoteControl
import SwiftUI

struct PointerScrollPane: View {
    @Bindable var monitor: DualSenseMonitor

    var body: some View {
        NavigationStack {
            Form {
                if monitor.hasMXMaster {
                    Section {
                        speedSlider("Pointer speed", value: pointerSpeedBinding)
                        Toggle("Smooth scrolling", isOn: smoothScrollingBinding)
                        speedSlider("Wheel speed", value: wheelSpeedBinding)
                        speedSlider("Thumb wheel speed", value: thumbSpeedBinding)
                        Picker("Scroll direction", selection: scrollDirectionBinding) {
                            Text("Natural").tag("natural")
                            Text("Standard").tag("standard")
                        }
                        .pickerStyle(.radioGroup)
                    } footer: {
                        Text("These apply to every MX Master (and later, any mouse we intercept). One system scroll tap, so they cannot differ per mouse. Accessibility must be on for wheel speed. DualSense and Siri Remote keep their own pointer and scroll on the device page.")
                    }
                } else {
                    Section {
                        Text("Add an MX Master to set pointer speed, wheel speed, and scroll direction for mice.")
                            .foregroundStyle(.secondary)
                    }
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

    private func speedSlider(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int((value.wrappedValue * 100).rounded()))%")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: 0...1)
        }
    }
}
