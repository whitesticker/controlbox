import IRemoteControl
import SwiftUI

struct DeviceProfilePane: View {
    @Bindable var monitor: DualSenseMonitor
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationStack {
            if let record = monitor.selectedRecord, let device = sidebarDevice {
                Form {
                    Section {
                        LabeledContent("Status") {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(device.isConnected ? Palette.good : Palette.bad)
                                    .frame(width: 8, height: 8)
                                Text(device.statusTitle)
                            }
                        }
                        LabeledContent("Type", value: record.kind.title)
                        if !record.address.isEmpty {
                            LabeledContent("Address", value: record.address)
                        }
                    }

                    Section {
                        Toggle("Control this Mac", isOn: controlEnabledBinding)
                        Toggle("Allow while VibeRemote is focused", isOn: controlWhileFocusedBinding)
                    } footer: {
                        Text("Sends this device’s inputs to the Mac. Injection is skipped while VibeRemote is frontmost unless you enable the second switch.")
                    }

                    Section {
                        LabeledContent("System permission") {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(monitor.accessibilityTrusted ? Palette.good : Palette.bad)
                                    .frame(width: 8, height: 8)
                                Text(monitor.accessibilityTrusted ? "Allowed" : "Not allowed")
                            }
                        }
                        if !monitor.accessibilityTrusted {
                            Button("Request Accessibility Access…") {
                                monitor.promptForAccessibility()
                            }
                            Button("Open System Settings") {
                                monitor.openAccessibilitySettings()
                            }
                            Button("Relaunch VibeRemote") {
                                monitor.relaunchApp()
                            }
                        }
                    } header: {
                        Text("Accessibility")
                    } footer: {
                        Text(monitor.accessibilityTrusted
                             ? "This running copy of VibeRemote can inject keyboard, pointer, and scroll events."
                             : "macOS does not apply a new Accessibility grant until the app relaunches. Enable VibeRemote in Privacy & Security → Accessibility, then click Relaunch. Rebuilds can leave extra VibeRemote entries — turn on the one that is running now.")
                    }

                    Section("Profile") {
                        if record.profiles.count > 1 {
                            Picker("Active profile", selection: profileSelection) {
                                ForEach(record.profiles) { profile in
                                    Text(profile.name).tag(profile.id)
                                }
                            }
                        }

                        TextField("Name", text: nameBinding)
                        TextField("Description", text: summaryBinding, axis: .vertical)
                            .lineLimit(2...4)

                        HStack {
                            Button("New Profile") {
                                monitor.addProfile()
                            }
                            Button("Duplicate") {
                                monitor.duplicateSelectedProfile()
                            }
                            Spacer()
                            Button("Delete Profile", role: .destructive) {
                                monitor.deleteSelectedProfile()
                            }
                            .disabled(record.profiles.count < 2)
                        }
                    }

                    analogSection(for: record)

                    ForEach(buttonGroups(for: record)) { group in
                        Section {
                            ForEach(group.buttons, id: \.self) { button in
                                if button == .clickSelect {
                                    selectRow(for: record)
                                } else {
                                    Picker(label(for: button), selection: actionBinding(for: button)) {
                                        ForEach(ControlActionOption.options(including: record.selectedProfile.bindings[button] ?? .none)) { option in
                                            Text(option.title).tag(option.id)
                                        }
                                    }
                                }
                            }
                        } header: {
                            Text(group.title)
                        } footer: {
                            if group.id == "clickpad" {
                                Text("Tap Select twice quickly for a double-click. Hold for the Hold action.")
                            }
                        }
                    }

                    Section {
                        Button("Calibration…") {
                            openWindow(id: "calibration")
                        }
                    } footer: {
                        Text("Opens a live capture window for this device so you can confirm buttons, clickpad, and motion.")
                    }

                    if record.remembered {
                        Section {
                            Button("Delete Device…", role: .destructive) {
                                monitor.removeSelectedDevice()
                            }
                        } footer: {
                            Text("Removes this device from the sidebar. Add it again from Add Device. If it is still connected, it stays in the list until it disconnects.")
                        }
                    }
                }
                .formStyle(.grouped)
                .navigationTitle(record.name)
            } else {
                ContentUnavailableView(
                    "Select a Device",
                    systemImage: "appletvremote.gen4",
                    description: Text("Choose a controller in the sidebar to set up mapping.")
                )
            }
        }
    }

    private var sidebarDevice: SidebarDevice? {
        monitor.sidebarDevices.first { $0.id == monitor.selectedDeviceID }
    }

    @ViewBuilder
    private func analogSection(for record: DeviceRecord) -> some View {
        if record.isAppleTVRemote {
            Section {
                Toggle("Clickpad", isOn: analogToggle(.appleTVClickpad, on: .pointer))
                Toggle("Clickwheel", isOn: analogToggle(.appleTVWheel, on: .scroll))
                Toggle("Pointer acceleration", isOn: accelerationBinding)
                    .disabled(monitor.selectedProfile.mode(for: .appleTVClickpad) == .off)
                if (monitor.selectedProfile.pointerAcceleration ?? true),
                   monitor.selectedProfile.mode(for: .appleTVClickpad) != .off {
                    Slider(value: accelerationAmountBinding, in: 0...1) {
                        Text("Amount")
                    } minimumValueLabel: {
                        Text("Low")
                    } maximumValueLabel: {
                        Text("High")
                    }
                }
                Toggle("Sticky targeting", isOn: stickyTargetingBinding)
                    .disabled(monitor.selectedProfile.mode(for: .appleTVClickpad) == .off)
            } footer: {
                Text("Slow slides stay precise. Faster flicks cover more of the screen. The pointer does not move while Select is pressed. Sticky targeting outlines the control under the pointer and clicks that control.")
            }
        } else {
            Section {
                analogPicker("Left stick", source: .dualSenseLeftStick)
                analogPicker("Right stick", source: .dualSenseRightStick)
                analogPicker("Touchpad", source: .dualSenseTouchpad)
                Toggle("Sticky targeting", isOn: stickyTargetingBinding)
                Toggle("Haptic feedback", isOn: hapticFeedbackBinding)
            } header: {
                Text("Analog")
            } footer: {
                Text("Sticks and the touchpad only move the pointer or scroll if you turn that source on. Sticky targeting outlines the control under the pointer and clicks that control. Haptic feedback rumbles the DualSense when you press a button.")
            }
        }
    }

    private func analogPicker(_ title: String, source: AnalogSource) -> some View {
        Picker(title, selection: analogBinding(source)) {
            ForEach([AnalogMode.off, .pointer, .scroll], id: \.self) { mode in
                Text(mode.title).tag(mode)
            }
        }
    }

    @ViewBuilder
    private func selectRow(for record: DeviceRecord) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text("Select")
            Spacer(minLength: 8)
            selectPicker(
                caption: "Click",
                button: .clickSelect,
                current: record.selectedProfile.bindings[.clickSelect] ?? .none
            )
            selectPicker(
                caption: "Hold",
                button: .clickSelectLong,
                current: record.selectedProfile.bindings[.clickSelectLong] ?? .none
            )
        }
    }

    private func selectPicker(caption: String, button: DeviceButton, current: ControlAction) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker(caption, selection: actionBinding(for: button)) {
                ForEach(ControlActionOption.options(including: current)) { option in
                    Text(option.title).tag(option.id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 136)
        }
    }

    private var controlEnabledBinding: Binding<Bool> {
        Binding(
            get: { monitor.selectedRecord?.controlEnabled ?? false },
            set: { monitor.setControlEnabled($0) }
        )
    }

    private var controlWhileFocusedBinding: Binding<Bool> {
        Binding(
            get: { monitor.selectedRecord?.controlWhileFocused ?? false },
            set: { monitor.setControlWhileFocused($0) }
        )
    }

    private var profileSelection: Binding<String> {
        Binding(
            get: { monitor.selectedRecord?.selectedProfileID ?? "" },
            set: { monitor.selectProfile($0) }
        )
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { monitor.selectedProfile.name },
            set: { monitor.renameSelectedProfile($0) }
        )
    }

    private var summaryBinding: Binding<String> {
        Binding(
            get: { monitor.selectedProfile.summary },
            set: { monitor.updateSelectedSummary($0) }
        )
    }

    private func analogBinding(_ source: AnalogSource) -> Binding<AnalogMode> {
        Binding(
            get: { monitor.selectedProfile.mode(for: source) },
            set: { monitor.setAnalogMode($0, for: source) }
        )
    }

    private func analogToggle(_ source: AnalogSource, on mode: AnalogMode) -> Binding<Bool> {
        Binding(
            get: { monitor.selectedProfile.mode(for: source) != .off },
            set: { monitor.setAnalogMode($0 ? mode : .off, for: source) }
        )
    }

    private var accelerationBinding: Binding<Bool> {
        Binding(
            get: { monitor.selectedProfile.pointerAcceleration ?? true },
            set: { monitor.setPointerAcceleration($0) }
        )
    }

    private var accelerationAmountBinding: Binding<Double> {
        Binding(
            get: { monitor.selectedProfile.pointerAccelerationAmount ?? 0.3 },
            set: { monitor.setPointerAccelerationAmount($0) }
        )
    }

    private var stickyTargetingBinding: Binding<Bool> {
        Binding(
            get: { monitor.selectedProfile.stickyTargeting ?? false },
            set: { monitor.setStickyTargeting($0) }
        )
    }

    private var hapticFeedbackBinding: Binding<Bool> {
        Binding(
            get: { monitor.selectedRecord?.hapticFeedbackEnabled ?? true },
            set: { monitor.setHapticFeedback($0) }
        )
    }

    private func buttonGroups(for record: DeviceRecord) -> [DeviceButtonGroup] {
        record.isAppleTVRemote ? DeviceButton.appleTVGroups : DeviceButton.dualSenseGroups
    }

    private func label(for button: DeviceButton) -> String {
        switch button {
        case .clickUp: return "Up"
        case .clickDown: return "Down"
        case .clickLeft: return "Left"
        case .clickRight: return "Right"
        case .clickSelect: return "Select"
        case .volumeUp: return "Volume +"
        case .volumeDown: return "Volume −"
        default: return button.title
        }
    }

    private func actionBinding(for button: DeviceButton) -> Binding<String> {
        Binding(
            get: { (monitor.selectedProfile.bindings[button] ?? .none).catalogID },
            set: { monitor.setButtonAction(ControlAction.fromCatalogID($0), for: button) }
        )
    }
}
