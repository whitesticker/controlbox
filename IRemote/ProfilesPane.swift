import IRemoteControl
import SwiftUI

struct DeviceProfilePane: View {
    @Bindable var monitor: DualSenseMonitor
    @Environment(\.openWindow) private var openWindow
    @State private var customizingButton: DeviceButton?
    @State private var customizingGestureButton: DeviceButton?
    @State private var customizingGestureSlot: GestureSlot?

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
                        if let identifier = deviceIdentifier(for: record, device: device) {
                            LabeledContent(DeviceIdentity.displayLabel(for: identifier), value: identifier)
                                .textSelection(.enabled)
                        }
                        LabeledContent("Type", value: record.kind.title)
                        if record.isMXMaster {
                            LabeledContent("HID++", value: mxHIDPPStatus(for: record))
                        }
                    }

                    Section {
                        Toggle("Control this Mac", isOn: controlEnabledBinding)
                        Toggle("Allow while VibeRemote is focused", isOn: controlWhileFocusedBinding)
                    } footer: {
                        Text("Sends this device’s inputs to the Mac. Injection is skipped while VibeRemote is frontmost unless you enable the second switch.")
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

                    Section {
                        if record.isMXMaster {
                            dpiSlider
                            speedSlider("Pointer speed", value: pointerSpeedBinding)
                            speedSlider(
                                record.kind.isMXMaster3Family ? "Gesture speed" : "Haptic gesture speed",
                                value: hapticGestureSpeedBinding
                            )
                            Toggle("Smooth scrolling", isOn: smoothScrollingBinding)
                            speedSlider("Wheel speed", value: wheelSpeedBinding)
                            speedSlider("Thumb wheel speed", value: thumbSpeedBinding)
                        } else {
                            speedSlider("Pointer speed", value: pointerSpeedBinding)
                            speedSlider("Scroll speed", value: wheelSpeedBinding)
                        }
                        Picker("Scroll direction", selection: scrollDirectionBinding) {
                            Text("Natural").tag("natural")
                            Text("Standard").tag("standard")
                        }
                        .pickerStyle(.radioGroup)
                    } header: {
                        Text("Pointer & scroll")
                    } footer: {
                        if record.isMXMaster {
                            Text(mxPointerScrollFooter(for: record))
                        } else {
                            Text("Pointer speed scales stick, clickpad, and touchpad cursor motion. Scroll speed scales analog scroll. Natural matches the Mac’s default direction.")
                        }
                    }

                    ForEach(buttonGroups(for: record)) { group in
                        Section {
                            ForEach(group.buttons, id: \.self) { button in
                                if button == .clickSelect {
                                    selectRow(for: record)
                                } else if record.isMXMaster {
                                    mxActionRow(label(for: button, kind: record.kind), button: button, record: record)
                                } else {
                                    actionRow(label(for: button, kind: record.kind), button: button, current: record.selectedProfile.bindings[button] ?? .none)
                                }
                            }
                        } header: {
                            Text(group.title)
                        } footer: {
                            if group.id == "clickpad" {
                                Text("Tap Select twice quickly for a double-click. Hold for the Hold action.")
                            } else if group.id == "buttons" {
                                Text(mxButtonsFooter(for: record))
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
                .onChange(of: monitor.selectedDeviceID) { _, _ in
                    customizingButton = nil
                    customizingGestureButton = nil
                    customizingGestureSlot = nil
                }
                .onChange(of: record.selectedProfileID) { _, _ in
                    customizingButton = nil
                    customizingGestureButton = nil
                    customizingGestureSlot = nil
                }
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
        if record.isMXMaster {
            EmptyView()
        } else if record.isAppleTVRemote {
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
                Toggle("Pointer acceleration", isOn: accelerationBinding)
                    .disabled(!dualSenseHasPointerSource(record))
                if (monitor.selectedProfile.pointerAcceleration ?? true),
                   dualSenseHasPointerSource(record) {
                    Slider(value: accelerationAmountBinding, in: 0...1) {
                        Text("Amount")
                    } minimumValueLabel: {
                        Text("Low")
                    } maximumValueLabel: {
                        Text("High")
                    }
                }
                Toggle("Sticky targeting", isOn: stickyTargetingBinding)
                Toggle("Haptic feedback", isOn: hapticFeedbackBinding)
            } header: {
                Text("Analog")
            } footer: {
                Text("Sticks and the touchpad only move the pointer or scroll if you turn that source on. Pointer acceleration keeps small stick or touch moves precise and speeds up flicks. Sticky targeting outlines the control under the pointer and clicks that control. Haptic feedback rumbles the DualSense when you press a button.")
            }
        }
    }

    @ViewBuilder
    private func analogPicker(_ title: String, source: AnalogSource) -> some View {
        Picker(title, selection: analogBinding(source)) {
            ForEach([AnalogMode.off, .pointer, .scroll], id: \.self) { mode in
                Text(mode.title).tag(mode)
            }
        }
    }

    @ViewBuilder
    private func actionRow(_ title: String, button: DeviceButton, current: ControlAction) -> some View {
        Picker(title, selection: actionBinding(for: button)) {
            mappingOptions
        }
        if showsRecorder(for: button, current: current) {
            LabeledContent("Shortcut") {
                shortcutRecorder(for: button, current: current)
            }
        }
    }

    @ViewBuilder
    private func mxActionRow(_ title: String, button: DeviceButton, record: DeviceRecord) -> some View {
        let current = record.selectedProfile.bindings[button] ?? .none
        Picker(title, selection: actionBinding(for: button)) {
            if button == .mxHaptic {
                Text("Gestures").tag("gestures")
                Divider()
            }
            mappingOptions
        }
        if current == .gestures {
            gestureEditor(for: button, record: record)
                .id("gesture-editor-\(button.rawValue)")
        } else if showsRecorder(for: button, current: current) {
            LabeledContent("Shortcut") {
                shortcutRecorder(for: button, current: current)
            }
        }
    }

    @ViewBuilder
    private func gestureEditor(for button: DeviceButton, record: DeviceRecord) -> some View {
        let set = record.selectedProfile.gestureSet(for: button) ?? .named(.windowNavigation)
        gestureNestedRow {
            Picker(selection: gesturePresetBinding(for: button)) {
                ForEach(GesturePreset.allCases, id: \.self) { preset in
                    Text(preset.title).tag(preset)
                }
            } label: {
                Text("Preset")
            }
            .id("\(button.rawValue)-preset")
        }
        ForEach(GestureSlot.allCases, id: \.self) { slot in
            gestureNestedRow {
                Picker(selection: gestureSlotBinding(for: button, slot: slot)) {
                    mappingOptions
                } label: {
                    Text(slot.title)
                }
                .id("\(button.rawValue)-\(slot.rawValue)")
            }
            .id("\(button.rawValue)-\(slot.rawValue)-row")
            if showsGestureRecorder(for: button, slot: slot, current: set.action(for: slot)) {
                gestureNestedRow {
                    LabeledContent("Shortcut") {
                        gestureShortcutRecorder(for: button, slot: slot, current: set.action(for: slot))
                    }
                }
                .id("\(button.rawValue)-\(slot.rawValue)-recorder")
            }
        }
    }

    private func gestureNestedRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Capsule()
                .fill(Palette.accent.opacity(0.45))
                .frame(width: 3, height: 14)
            content()
        }
        .padding(.leading, 22)
        .listRowInsets(EdgeInsets(top: 5, leading: 36, bottom: 5, trailing: 16))
    }

    @ViewBuilder
    private var mappingOptions: some View {
        ForEach(ControlAction.catalog) { option in
            Text(option.title).tag(option.id)
        }
        Divider()
        Text("Custom Shortcut…").tag(ControlActionOption.customID)
    }

    private func showsRecorder(for button: DeviceButton, current: ControlAction) -> Bool {
        customizingButton == button || current.catalogID == ControlActionOption.customID
    }

    private func customShortcut(from action: ControlAction) -> (UInt16, UInt64)? {
        if case .key(let key, let flags) = action, action.catalogID == ControlActionOption.customID {
            return (key, flags)
        }
        return nil
    }

    private func shortcutRecorder(for button: DeviceButton, current: ControlAction) -> ShortcutRecorderField {
        ShortcutRecorderField(
            shortcut: customShortcut(from: current),
            isRecording: customizingButton == button,
            onBegin: { customizingButton = button },
            onRecord: { key, flags in
                customizingButton = nil
                monitor.setButtonAction(.key(virtualKey: key, flags: flags), for: button)
            },
            onClear: {
                customizingButton = nil
                monitor.setButtonAction(.none, for: button)
            },
            onCancel: {
                customizingButton = nil
            }
        )
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
        VStack(alignment: .trailing, spacing: 6) {
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker(caption, selection: actionBinding(for: button)) {
                mappingOptions
            }
            .labelsHidden()
            .frame(maxWidth: 168)
            if showsRecorder(for: button, current: current) {
                shortcutRecorder(for: button, current: current)
            }
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

    private func dualSenseHasPointerSource(_ record: DeviceRecord) -> Bool {
        let profile = record.selectedProfile
        return profile.mode(for: .dualSenseLeftStick) == .pointer
            || profile.mode(for: .dualSenseRightStick) == .pointer
            || profile.mode(for: .dualSenseTouchpad) == .pointer
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

    private var pointerSpeedBinding: Binding<Double> {
        Binding(
            get: { monitor.selectedProfile.resolvedPointerSpeed },
            set: { monitor.setPointerSpeed($0) }
        )
    }

    private var hapticGestureSpeedBinding: Binding<Double> {
        Binding(
            get: { monitor.selectedProfile.resolvedHapticGestureSpeed },
            set: { monitor.setHapticGestureSpeed($0) }
        )
    }

    private var smoothScrollingBinding: Binding<Bool> {
        Binding(
            get: { monitor.selectedProfile.resolvedSmoothScrolling },
            set: { monitor.setSmoothScrolling($0) }
        )
    }

    private var dpiLevels: [Int] {
        let fromMouse = monitor.mxMasterSnapshot.availableDPI
        return fromMouse.count >= 2 ? fromMouse : MappingProfile.fallbackDPILevels
    }

    private var dpiIndexBinding: Binding<Double> {
        Binding(
            get: {
                let levels = dpiLevels
                let current = MappingProfile.nearestDPI(monitor.selectedProfile.resolvedSensorDPI, in: levels)
                return Double(levels.firstIndex(of: current) ?? 0)
            },
            set: { index in
                let levels = dpiLevels
                let clamped = min(max(Int(index.rounded()), 0), levels.count - 1)
                monitor.setSensorDPI(levels[clamped])
            }
        )
    }

    @ViewBuilder
    private var dpiSlider: some View {
        let levels = dpiLevels
        let current = MappingProfile.nearestDPI(monitor.selectedProfile.resolvedSensorDPI, in: levels)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("DPI")
                Spacer()
                Text("\(current)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: dpiIndexBinding, in: 0...Double(max(levels.count - 1, 1)), step: 1)
        }
    }

    private var wheelSpeedBinding: Binding<Double> {
        Binding(
            get: { monitor.selectedProfile.resolvedWheelScrollSpeed },
            set: { monitor.setWheelScrollSpeed($0) }
        )
    }

    private var thumbSpeedBinding: Binding<Double> {
        Binding(
            get: { monitor.selectedProfile.resolvedThumbScrollSpeed },
            set: { monitor.setThumbScrollSpeed($0) }
        )
    }

    private var scrollDirectionBinding: Binding<String> {
        Binding(
            get: { monitor.selectedProfile.resolvedNaturalScrolling ? "natural" : "standard" },
            set: { monitor.setNaturalScrolling($0 == "natural") }
        )
    }

    @ViewBuilder
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

    private func deviceIdentifier(for record: DeviceRecord, device: SidebarDevice) -> String? {
        for candidate in [device.address, record.address] where DeviceIdentity.isConcrete(candidate) {
            return DeviceIdentity.format(candidate)
        }
        return nil
    }

    private func mxPointerScrollFooter(for record: DeviceRecord) -> String {
        let feel = record.kind.isMXMaster3Family
            ? "DPI is sensor resolution on this mouse. Gesture speed is hold-to-swipe on the thumb button."
            : "DPI is sensor resolution on this mouse. Haptic gesture speed is the thumb pad."
        return feel
            + " Pointer speed, scroll direction, smooth scrolling, and wheel/thumb speed are shared by every mouse — there is one system scroll tap, so those cannot differ per mouse. Accessibility must be allowed for wheel speed."
    }

    private func mxButtonsFooter(for record: DeviceRecord) -> String {
        let gesture = record.kind.isMXMaster3Family
            ? "Gesture is the only Gestures button. Hold the thumb button and move for the four directions. A tap without moving is Click."
            : "Haptic is the only Gestures button. Hold the pad and move for the four directions. A tap without moving is Click."
        return gesture
            + " macOS click events do not say which physical mouse generated them, so extra-button fallbacks are gated per model: MX4 haptic (buttons 5/6) will not start a 3S gesture."
    }

    private func mxHIDPPStatus(for record: DeviceRecord) -> String {
        let live = monitor.mxMasterSnapshot
        if monitor.isLiveMXSelection(live) {
            return live.status
        }
        return "Not connected"
    }

    private func buttonGroups(for record: DeviceRecord) -> [DeviceButtonGroup] {
        if record.isMXMaster { return DeviceButton.mxMasterGroups }
        if record.isAppleTVRemote { return DeviceButton.appleTVGroups }
        return DeviceButton.dualSenseGroups
    }

    private func label(for button: DeviceButton, kind: DeviceKind = .unsupported) -> String {
        switch button {
        case .clickUp: return "Up"
        case .clickDown: return "Down"
        case .clickLeft: return "Left"
        case .clickRight: return "Right"
        case .clickSelect: return "Select"
        case .volumeUp: return "Volume +"
        case .volumeDown: return "Volume −"
        case .mxHaptic: return kind.mxGestureControlTitle
        default: return button.title
        }
    }

    private func actionBinding(for button: DeviceButton) -> Binding<String> {
        Binding(
            get: {
                if customizingButton == button {
                    return ControlActionOption.customID
                }
                return (monitor.selectedProfile.bindings[button] ?? .none).catalogID
            },
            set: { id in
                if id == ControlActionOption.customID {
                    customizingButton = button
                    return
                }
                if customizingButton == button {
                    customizingButton = nil
                }
                monitor.setButtonAction(ControlAction.fromCatalogID(id), for: button)
            }
        )
    }

    private func gesturePresetBinding(for button: DeviceButton) -> Binding<GesturePreset> {
        Binding(
            get: {
                monitor.selectedProfile.gestureSet(for: button)?.preset ?? .windowNavigation
            },
            set: { monitor.setGesturePreset($0, for: button) }
        )
    }

    private func gestureSlotBinding(for button: DeviceButton, slot: GestureSlot) -> Binding<String> {
        Binding(
            get: {
                if customizingGestureButton == button, customizingGestureSlot == slot {
                    return ControlActionOption.customID
                }
                return (monitor.selectedProfile.gestureSet(for: button) ?? .named(.windowNavigation))
                    .action(for: slot)
                    .catalogID
            },
            set: { id in
                if id == ControlActionOption.customID {
                    customizingGestureButton = button
                    customizingGestureSlot = slot
                    return
                }
                if customizingGestureButton == button, customizingGestureSlot == slot {
                    customizingGestureButton = nil
                    customizingGestureSlot = nil
                }
                monitor.setGestureAction(ControlAction.fromCatalogID(id), slot: slot, for: button)
            }
        )
    }

    private func showsGestureRecorder(for button: DeviceButton, slot: GestureSlot, current: ControlAction) -> Bool {
        (customizingGestureButton == button && customizingGestureSlot == slot)
            || current.catalogID == ControlActionOption.customID
    }

    private func gestureShortcutRecorder(for button: DeviceButton, slot: GestureSlot, current: ControlAction) -> ShortcutRecorderField {
        ShortcutRecorderField(
            shortcut: customShortcut(from: current),
            isRecording: customizingGestureButton == button && customizingGestureSlot == slot,
            onBegin: {
                customizingGestureButton = button
                customizingGestureSlot = slot
            },
            onRecord: { key, flags in
                customizingGestureButton = nil
                customizingGestureSlot = nil
                monitor.setGestureAction(.key(virtualKey: key, flags: flags), slot: slot, for: button)
            },
            onClear: {
                customizingGestureButton = nil
                customizingGestureSlot = nil
                monitor.setGestureAction(.none, slot: slot, for: button)
            },
            onCancel: {
                customizingGestureButton = nil
                customizingGestureSlot = nil
            }
        )
    }
}
