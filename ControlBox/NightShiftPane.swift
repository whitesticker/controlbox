import ControlBoxCore
import SwiftUI

struct NightShiftPane: View {
    @Bindable var catalog: NightShiftCatalog

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Adjust Night Shift from this curve", isOn: enabledBinding)
                        .disabled(!catalog.isSupported)
                    TimelineView(.periodic(from: .now, by: 15)) { timeline in
                        LabeledContent("Now") {
                            Text(nowSummary(at: timeline.date))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text(footer)
                }

                Section {
                    NightShiftCurveView(
                        curve: curveBinding,
                        range: catalog.range,
                        enabled: catalog.isSupported,
                        onMove: { id, minutes, warmth, live in
                            catalog.movePoint(id: id, minutes: minutes, warmth: warmth, live: live)
                        },
                        onAdd: { minutes, warmth in
                            catalog.addPoint(minutes: minutes, warmth: warmth)
                        },
                        onRemove: { id in
                            catalog.removePoint(id: id)
                        }
                    )
                    .frame(minHeight: 280)
                    .listRowInsets(EdgeInsets(top: 10, leading: 8, bottom: 4, trailing: 8))
                    Button("Reset Curve") {
                        catalog.resetCurve()
                    }
                    .disabled(!catalog.isSupported)
                } header: {
                    Text("Yellowness")
                } footer: {
                    Text("X is the time of day. Y is how yellow Night Shift is, from cool daylight at the bottom to Night Shift’s maximum warmth at the top. Drag a dot to edit. Double-click the chart to add a point. Drag a point off the bottom to remove it.")
                }

                Section {
                    Toggle("Also adjust external brightness", isOn: brightnessFollowBinding)
                        .disabled(!catalog.isSupported)
                    if catalog.adjustExternalBrightness {
                        SettingsSlider(
                            "Swing",
                            value: brightnessSwingBinding,
                            in: 0...0.5,
                            enabled: catalog.isSupported,
                            valueText: "±\(Int((catalog.brightnessSwing * 100).rounded()))%"
                        )
                    }
                } header: {
                    Text("External brightness")
                } footer: {
                    Text("When the curve is warm, external monitors dim by up to this amount from the level you set. When it is cool, they brighten by the same amount. The built-in panel is left alone. Default is ±10%.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Night Shift")
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { catalog.enabled },
            set: { catalog.setEnabled($0) }
        )
    }

    private var curveBinding: Binding<NightShiftCurve> {
        Binding(
            get: { catalog.curve },
            set: { catalog.curve = $0 }
        )
    }

    private var brightnessFollowBinding: Binding<Bool> {
        Binding(
            get: { catalog.adjustExternalBrightness },
            set: { catalog.setAdjustExternalBrightness($0) }
        )
    }

    private var brightnessSwingBinding: Binding<Double> {
        Binding(
            get: { catalog.brightnessSwing },
            set: { catalog.setBrightnessSwing($0) }
        )
    }

    private func nowSummary(at date: Date) -> String {
        let warmth = catalog.curve.warmth(at: date)
        let percent = Int((warmth * 100).rounded())
        let kelvin = NightShiftCurve.kelvin(warmth: warmth, range: catalog.range)
        return "\(NightShiftCurve.timeLabel(minutes: NightShiftCurve.minutes(from: date))) · \(percent)% · \(kelvin) K"
    }

    private var footer: String {
        if !catalog.isSupported {
            return "Night Shift is not available on this Mac."
        }
        if catalog.enabled {
            return "Control Box is driving system Night Shift from the curve. Apple’s sunset-to-sunrise schedule is paused until you turn this off, which puts Night Shift back the way it was."
        }
        return "Off until you turn it on. Then Control Box sets system Night Shift yellowness from the curve as the day goes on."
    }
}
