import ControlBoxCore
import SwiftUI

struct NightShiftPane: View {
    @Bindable var catalog: NightShiftCatalog
    @State private var selectedPointID: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: enabledBinding) {
                        SettingsRowLabel("Adjust Night Shift from this curve", enabledSubtitle)
                    }
                    .disabled(!catalog.isSupported)
                    TimelineView(.periodic(from: .now, by: 15)) { timeline in
                        LabeledContent("Now") {
                            Text(nowSummary(at: timeline.date))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    NightShiftCurveView(
                        curve: curveBinding,
                        selectedID: $selectedPointID,
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
                    HStack {
                        Button("Add Point") {
                            if let id = catalog.addSuggestedPoint() {
                                selectedPointID = id
                            }
                        }
                        .disabled(!canAddPoint)
                        Button("Remove Point", role: .destructive) {
                            if let id = selectedPointID {
                                catalog.removePoint(id: id)
                                selectedPointID = nil
                            }
                        }
                        .disabled(!canRemovePoint)
                        Spacer()
                        Button("Reset Curve") {
                            selectedPointID = nil
                            catalog.resetCurve()
                        }
                    }
                    .disabled(!catalog.isSupported)
                } header: {
                    Text("Yellowness")
                } footer: {
                    Text("Drag a knot to change its time and warmth.")
                }

                Section {
                    Toggle(isOn: appearanceEnabledBinding) {
                        SettingsRowLabel(
                            "Schedule Light and Dark",
                            "Off keeps the current look."
                        )
                    }
                    .disabled(!catalog.isSupported)
                    if catalog.appearanceSchedule.enabled {
                        Picker(selection: appearanceModeBinding) {
                            Text("Sunset to sunrise").tag(AppearanceScheduleMode.sunset)
                            Text("Custom hours").tag(AppearanceScheduleMode.custom)
                        } label: {
                            Text("When")
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
                }

                Section {
                    Toggle(isOn: brightnessFollowBinding) {
                        SettingsRowLabel(
                            "Also adjust external brightness",
                            "Warmer dims external monitors; built-in is left alone."
                        )
                    }
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
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Night Shift")
        }
    }

    private var canAddPoint: Bool {
        catalog.isSupported && catalog.curve.points.count < NightShiftCurve.maxPoints
    }

    private var canRemovePoint: Bool {
        catalog.isSupported
            && catalog.curve.points.count > NightShiftCurve.minPoints
            && selectedPointID.map { id in catalog.curve.points.contains(where: { $0.id == id }) } == true
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

    private var enabledSubtitle: String? {
        if !catalog.isSupported {
            return "Night Shift is not available on this Mac."
        }
        if catalog.enabled {
            return "Control Box owns Night Shift; System Settings changes are undone."
        }
        return nil
    }
}
