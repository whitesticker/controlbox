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
                    footer
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
                    footerBullets(
                        "X is time of day; Y is warmth (cool at the bottom, max yellow at the top).",
                        "Drag a dot to edit. Double-click to add. Drag off the bottom to remove."
                    )
                }

                Section {
                    Toggle("Schedule Light and Dark", isOn: appearanceEnabledBinding)
                        .disabled(!catalog.isSupported)
                    if catalog.appearanceSchedule.enabled {
                        Picker("When", selection: appearanceModeBinding) {
                            Text("Sunset to sunrise").tag(AppearanceScheduleMode.sunset)
                            Text("Custom hours").tag(AppearanceScheduleMode.custom)
                        }
                        .disabled(!catalog.isSupported)
                        if catalog.appearanceSchedule.mode == .custom {
                            DatePicker(
                                "Dark from",
                                selection: appearanceDarkFromBinding,
                                displayedComponents: .hourAndMinute
                            )
                            .disabled(!catalog.isSupported)
                            DatePicker(
                                "Until",
                                selection: appearanceDarkToBinding,
                                displayedComponents: .hourAndMinute
                            )
                            .disabled(!catalog.isSupported)
                        } else {
                            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                                let solar = SolarTimes.today(date: timeline.date)
                                LabeledContent("Today") {
                                    Text(
                                        "Dark \(NightShiftCurve.timeLabel(minutes: solar.sunset)) – \(NightShiftCurve.timeLabel(minutes: solar.sunrise))"
                                    )
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Appearance")
                } footer: {
                    footerBullets(
                        "Apple Auto follows our all-day Night Shift window, so Control Box flips Light/Dark instead.",
                        "Sunset uses this Mac’s time zone. Custom hours wrap past midnight.",
                        "Off freezes the look that is on screen. Turning Night Shift off restores Apple Auto."
                    )
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
                    footerBullets(
                        "Warm curve dims external monitors; cool brightens them.",
                        "Built-in panel is left alone. Default ±10%."
                    )
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

    private var appearanceEnabledBinding: Binding<Bool> {
        Binding(
            get: { catalog.appearanceSchedule.enabled },
            set: { catalog.setAppearanceScheduleEnabled($0) }
        )
    }

    private var appearanceModeBinding: Binding<AppearanceScheduleMode> {
        Binding(
            get: { catalog.appearanceSchedule.mode },
            set: { catalog.setAppearanceScheduleMode($0) }
        )
    }

    private var appearanceDarkFromBinding: Binding<Date> {
        Binding(
            get: { NightShiftCurve.date(fromMinutes: catalog.appearanceSchedule.darkFromMinutes) },
            set: { catalog.setAppearanceDarkFrom($0) }
        )
    }

    private var appearanceDarkToBinding: Binding<Date> {
        Binding(
            get: { NightShiftCurve.date(fromMinutes: catalog.appearanceSchedule.darkToMinutes) },
            set: { catalog.setAppearanceDarkTo($0) }
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

    private var footer: Text {
        if !catalog.isSupported {
            return Text("Night Shift is not available on this Mac.")
        }
        if catalog.enabled {
            return footerBullets(
                "Control Box owns system Night Shift.",
                "System Settings / Control Center changes are undone until you turn this off."
            )
        }
        return footerBullets(
            "Off until this is on.",
            "Then Control Box owns system Night Shift from the curve."
        )
    }
}
