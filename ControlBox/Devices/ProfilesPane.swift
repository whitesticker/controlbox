import CoreGraphics
import ControlBoxCore
import SwiftUI

struct DeviceProfilePane: View {
    @Bindable var monitor: DualSenseMonitor
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme
    @State private var customizingButton: DeviceButton?
    @State private var customizingGestureButton: DeviceButton?
    @State private var customizingGestureSlot: GestureSlot?
    @State private var showAddApp = false
    @State private var pendingMXProfileRemoval: MappingProfile?

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
                        TextField("Name", text: deviceNameBinding)
                        if record.isMXMaster {
                            LabeledContent("HID++", value: mxHIDPPStatus(for: record))
                        }
                        if record.isMXKeyboard {
                            LabeledContent("HID++", value: keyboardHIDPPStatus(for: record))
                        }
                    } footer: {
                        if record.isMXMaster || record.isMXKeyboard {
                            bullets(
                                "Shown in the sidebar.",
                                "Also stored on this device. Bluetooth Settings may update after reconnect."
                            )
                        } else {
                            bullets("Shown in the sidebar.")
                        }
                    }

                    if record.isMXKeyboard {
                        keyboardBatterySection
                        easySwitchSection(
                            hosts: monitor.mxKeyboardSnapshot.easySwitchHosts,
                            noun: "keyboard",
                            canRefresh: monitor.mxKeyboardSnapshot.hidppReady,
                            onRefresh: { monitor.reloadEasySwitch(isKeyboard: true) }
                        )
                        keyboardSettingsSection
                    } else {
                        if record.isMXMaster {
                            mxBatterySection
                            easySwitchSection(
                                hosts: monitor.mxMasterSnapshot.easySwitchHosts,
                                noun: "mouse",
                                canRefresh: monitor.mxMasterSnapshot.connected,
                                onRefresh: { monitor.reloadEasySwitch(isKeyboard: false) }
                            )
                        }
                        Section {
                            Toggle("Control this Mac", isOn: controlEnabledBinding)
                            Toggle("Allow while Control Box is focused", isOn: controlWhileFocusedBinding)
                        } footer: {
                            bullets(
                                "Sends this device’s inputs to the Mac.",
                                "Skipped while Control Box is frontmost, unless the second switch is on."
                            )
                        }

                        if record.isMXMaster {
                            Section {
                                mxProfilesCard(for: record)
                                    .listRowInsets(EdgeInsets())
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                            } header: {
                                Text("Profiles")
                            }
                        } else {
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

                    if !record.isMXMaster && !record.isAppleTVRemote && !record.isMXKeyboard {
                        dualSenseTouchpadGesturesSection(for: record)
                    }

                        Section {
                            SettingsSlider("Pointer speed", value: pointerSpeedBinding)
                            SettingsSlider("Scroll speed", value: wheelSpeedBinding)
                            if !record.isAppleTVRemote {
                                Toggle("Scroll acceleration", isOn: scrollAccelerationBinding)
                                    .disabled(!hasAnalogScrollSource(record))
                                if (monitor.selectedProfile.scrollAcceleration == true),
                                   hasAnalogScrollSource(record) {
                                    SettingsSlider("Amount", value: scrollAccelerationAmountBinding)
                                }
                            }
                            Picker("Scroll direction", selection: scrollDirectionBinding) {
                                Text("Natural").tag("natural")
                                Text("Standard").tag("standard")
                            }
                            .pickerStyle(.radioGroup)
                        } header: {
                            Text("Pointer & scroll")
                        } footer: {
                            if record.isAppleTVRemote {
                                bullets(
                                    "Pointer speed: stick, clickpad, and touchpad.",
                                    "Scroll speed: only when that analog is set to Scroll.",
                                    "Natural matches the Mac."
                                )
                            } else {
                                bullets(
                                    "Pointer speed: stick and touchpad.",
                                    "Scroll speed / acceleration: only when a stick or Touchpad analog is set to Scroll.",
                                    "Natural matches the Mac."
                                )
                            }
                        }

                    ForEach(buttonGroups(for: record)) { group in
                        Section {
                            ForEach(group.buttons, id: \.self) { button in
                                if button == .clickSelect {
                                    selectRow(for: record)
                                } else if button.canOwnGestures {
                                    mxActionRow(label(for: button, kind: record.kind), button: button, record: record)
                                } else {
                                    let mapped = record.selectedProfile.bindings[button]
                                        ?? (button.isMXScrollDirection ? .scroll : .none)
                                    actionRow(label(for: button, kind: record.kind), button: button, current: mapped)
                                }
                            }
                            if group.id == "shoulders",
                               !record.isMXMaster,
                               !record.isAppleTVRemote,
                               dualSenseUsesTriggerTabs(record) {
                                SettingsSlider(
                                    "Tab repeat",
                                    value: tabRepeatBinding,
                                    in: 0.10...0.55,
                                    valueText: "\(Int((monitor.selectedProfile.resolvedTabRepeatInterval * 1000).rounded())) ms"
                                )
                            }
                        } header: {
                            Text(group.title)
                        } footer: {
                            if group.id == "clickpad" {
                                bullets(
                                    "Double-tap Select for a double-click.",
                                    "Hold for the Hold action."
                                )
                            } else if group.id == "buttons" {
                                mxButtonsFooter(for: record)
                            } else if group.id == "wheel" {
                                bullets(
                                    "Up and Down are the main wheel, one direction each.",
                                    "Scroll keeps native scrolling; any other action replaces that direction."
                                )
                            } else if group.id == "thumb-wheel" {
                                bullets(
                                    "Left and Right are the thumb wheel.",
                                    "Scroll keeps native scrolling; any other action replaces that direction."
                                )
                            } else if group.id == "sticks" {
                                Text("L3 and R3 are stick clicks.")
                            } else if group.id == "shoulders", !record.isMXMaster, !record.isAppleTVRemote {
                                bullets(
                                    "L2 / R2 are analog. Previous/Next tab uses travel: mid pull = one tab, full hold = repeat.",
                                    "L1 / R1 are click buttons."
                                )
                            }
                        }
                    }
                        }

                    Section {
                        Button("Calibration…") {
                            openWindow(id: "calibration")
                        }
                    } footer: {
                        Text("Live capture of this device’s buttons and motion. DPI is in that window.")
                    }
                    }

                    if record.remembered {
                        Section {
                            Button("Delete Device…", role: .destructive) {
                                monitor.removeSelectedDevice()
                            }
                        } footer: {
                            bullets(
                                "Removes it from the sidebar.",
                                "Add Device brings it back.",
                                "If it’s still connected, it stays until it disconnects."
                            )
                        }
                    }
                }
                .formStyle(.grouped)
                .navigationTitle(record.displayName)
                .sheet(isPresented: $showAddApp) {
                    AddAppSheet(monitor: monitor)
                }
                .confirmationDialog(
                    "Remove \(pendingMXProfileRemoval?.mxScopeTitle ?? "this mapping")?",
                    isPresented: Binding(
                        get: { pendingMXProfileRemoval != nil },
                        set: { if !$0 { pendingMXProfileRemoval = nil } }
                    ),
                    titleVisibility: .visible
                ) {
                    Button("Remove", role: .destructive) {
                        if let id = pendingMXProfileRemoval?.id {
                            monitor.removeMXProfile(id)
                        }
                        pendingMXProfileRemoval = nil
                    }
                    Button("Cancel", role: .cancel) {
                        pendingMXProfileRemoval = nil
                    }
                } message: {
                    Text("The mouse will use Default in that app.")
                }
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
                    description: Text("Choose a device in the sidebar.")
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
        } else if record.isMXKeyboard {
            EmptyView()
        } else if record.isAppleTVRemote {
            Section {
                Toggle("Clickpad", isOn: analogToggle(.appleTVClickpad, on: .pointer))
                Toggle("Clickwheel", isOn: analogToggle(.appleTVWheel, on: .scroll))
                Toggle("Pointer acceleration", isOn: accelerationBinding)
                    .disabled(monitor.selectedProfile.mode(for: .appleTVClickpad) == .off)
                if (monitor.selectedProfile.pointerAcceleration ?? true),
                   monitor.selectedProfile.mode(for: .appleTVClickpad) != .off {
                    SettingsSlider("Amount", value: accelerationAmountBinding)
                }
                Toggle("Sticky targeting", isOn: stickyTargetingBinding)
                    .disabled(monitor.selectedProfile.mode(for: .appleTVClickpad) == .off)
            } footer: {
                bullets(
                    "Slow slides stay precise; flicks cover more of the screen.",
                    "Pointer does not move while Select is pressed.",
                    "Sticky targeting outlines the control under the pointer and clicks it."
                )
            }
        } else {
            Section {
                analogPicker("Left stick", source: .dualSenseLeftStick)
                analogPicker("Right stick", source: .dualSenseRightStick)
                analogPicker("Touchpad analog", source: .dualSenseTouchpad)
                Toggle("Pointer acceleration", isOn: accelerationBinding)
                    .disabled(!dualSenseHasPointerSource(record))
                if (monitor.selectedProfile.pointerAcceleration ?? true),
                   dualSenseHasPointerSource(record) {
                    SettingsSlider("Amount", value: accelerationAmountBinding)
                }
                Toggle("Sticky targeting", isOn: stickyTargetingBinding)
                Toggle("Haptic feedback", isOn: hapticFeedbackBinding)
            } header: {
                Text("Analog")
            } footer: {
                bullets(
                    "Sticks only move or scroll if that source is on.",
                    "Touchpad analog is pointer/scroll; swipes are under Touchpad gestures.",
                    "Acceleration: small moves stay precise, flicks speed up.",
                    "Sticky targeting outlines the control under the pointer and clicks it.",
                    "Haptic rumble on DualSense button press."
                )
            }
        }
    }

    @ViewBuilder
    private func dualSenseTouchpadGesturesSection(for record: DeviceRecord) -> some View {
        Section {
            mxActionRow("1-finger swipe", button: .touchpadOneFinger, record: record)
            mxActionRow("2-finger swipe", button: .touchpadTwoFinger, record: record)
        } header: {
            Text("Touchpad gestures")
        } footer: {
            bullets(
                "Two separate Gestures, like the MX gesture button.",
                "Hold and move for the four directions; lift without moving is Click.",
                "Physical click is Touchpad click under System."
            )
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
        LabeledContent(title) {
            actionPickerAndRecorder(button: button, current: current, includeScroll: button.isMXScrollDirection)
        }
        .labeledContentStyle(CenteredLabeledContentStyle())
    }

    @ViewBuilder
    private func mxActionRow(_ title: String, button: DeviceButton, record: DeviceRecord) -> some View {
        let current = record.selectedProfile.bindings[button] ?? .none
        LabeledContent(title) {
            actionPickerAndRecorder(
                button: button,
                current: current,
                includeScroll: false,
                includeGestures: button.canOwnGestures
            )
        }
        .labeledContentStyle(CenteredLabeledContentStyle())
        if current == .gestures {
            gestureEditor(for: button, record: record)
                .id("gesture-editor-\(button.rawValue)")
        }
    }

    @ViewBuilder
    private func actionPickerAndRecorder(
        button: DeviceButton,
        current: ControlAction,
        includeScroll: Bool,
        includeGestures: Bool = false
    ) -> some View {
        HStack(spacing: 8) {
            Picker(selection: actionBinding(for: button)) {
                if includeGestures {
                    Text("Gestures").tag("gestures")
                    Divider()
                }
                if includeScroll {
                    Text("Scroll").tag("scroll")
                    Divider()
                }
                mappingOptions
            } label: {
                EmptyView()
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            if current != .gestures, showsRecorder(for: button, current: current) {
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
                if showsGestureRecorder(for: button, slot: slot, current: set.action(for: slot)) {
                    gestureShortcutRecorder(for: button, slot: slot, current: set.action(for: slot))
                }
            }
            .id("\(button.rawValue)-\(slot.rawValue)-row")
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
            width: 140,
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
            HStack(spacing: 8) {
                Picker(caption, selection: actionBinding(for: button)) {
                    mappingOptions
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 168)
                if showsRecorder(for: button, current: current) {
                    shortcutRecorder(for: button, current: current)
                }
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

    private var deviceNameBinding: Binding<String> {
        Binding(
            get: { monitor.selectedRecord?.displayName ?? "" },
            set: { monitor.renameSelectedDevice($0) }
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

    private func dualSenseUsesTriggerTabs(_ record: DeviceRecord) -> Bool {
        let profile = record.selectedProfile
        return profile.bindings[.l2]?.isTabSwitch == true
            || profile.bindings[.r2]?.isTabSwitch == true
    }

    private var tabRepeatBinding: Binding<Double> {
        Binding(
            get: { monitor.selectedProfile.resolvedTabRepeatInterval },
            set: { monitor.setTabRepeatInterval($0) }
        )
    }

    private func hasAnalogScrollSource(_ record: DeviceRecord) -> Bool {
        let profile = record.selectedProfile
        if record.isAppleTVRemote {
            return profile.mode(for: .appleTVClickpad) == .scroll
                || profile.mode(for: .appleTVWheel) == .scroll
        }
        return profile.mode(for: .dualSenseLeftStick) == .scroll
            || profile.mode(for: .dualSenseRightStick) == .scroll
            || profile.mode(for: .dualSenseTouchpad) == .scroll
    }

    private func dualSenseHasPointerSource(_ record: DeviceRecord) -> Bool {
        let profile = record.selectedProfile
        return profile.mode(for: .dualSenseLeftStick) == .pointer
            || profile.mode(for: .dualSenseRightStick) == .pointer
            || profile.mode(for: .dualSenseTouchpad) == .pointer
    }

    private var scrollAccelerationBinding: Binding<Bool> {
        Binding(
            get: { monitor.selectedProfile.scrollAcceleration == true },
            set: { monitor.setScrollAcceleration($0) }
        )
    }

    private var scrollAccelerationAmountBinding: Binding<Double> {
        Binding(
            get: { monitor.selectedProfile.scrollAccelerationAmount ?? 0.3 },
            set: { monitor.setScrollAccelerationAmount($0) }
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

    private var pointerSpeedBinding: Binding<Double> {
        Binding(
            get: { monitor.selectedProfile.resolvedPointerSpeed },
            set: { monitor.setPointerSpeed($0) }
        )
    }

    private var wheelSpeedBinding: Binding<Double> {
        Binding(
            get: { monitor.selectedProfile.resolvedWheelScrollSpeed },
            set: { monitor.setWheelScrollSpeed($0) }
        )
    }

    private var scrollDirectionBinding: Binding<String> {
        Binding(
            get: { monitor.selectedProfile.resolvedNaturalScrolling ? "natural" : "standard" },
            set: { monitor.setNaturalScrolling($0 == "natural") }
        )
    }

    private func deviceIdentifier(for record: DeviceRecord, device: SidebarDevice) -> String? {
        for candidate in [device.address, record.address] where DeviceIdentity.isConcrete(candidate) {
            return DeviceIdentity.format(candidate)
        }
        return nil
    }

    private func bullets(_ lines: String...) -> Text {
        footerBullets(Array(lines))
    }

    private func mxButtonsFooter(for record: DeviceRecord) -> Text {
        if record.kind.isMXMaster3Family {
            return footerBullets(
                "Gesture is the only Gestures button: hold and move, or tap to Click."
            )
        }
        return footerBullets(
            "Haptic is the only Gestures button: hold and move, or tap to Click.",
            "Side is the extra thumb button (default: Mission Control)."
        )
    }

    private func mxProfilesCard(for record: DeviceRecord) -> some View {
        let groups = buttonGroups(for: record)
        let buttonGroup = groups.first(where: { $0.id == "buttons" })
        let gestureButtons = buttonGroup?.buttons.filter(\.canOwnGestures) ?? []
        let availableButtons = Set(buttonGroup?.buttons ?? [])
        let mainButtonOrder: [DeviceButton] = [.mxMiddle, .mxBack, .mxForward, .mxSmartShift]
        let mainButtons = mainButtonOrder.filter { availableButtons.contains($0) }
        let otherButtons = buttonGroup?.buttons.filter {
            !$0.canOwnGestures && !mainButtonOrder.contains($0)
        } ?? []

        return VStack(spacing: 7) {
            mxProfileSelectorCard(for: record)
                .padding(10)
                .background(
                    Palette.fill(colorScheme).opacity(0.42),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Palette.hairline(colorScheme), lineWidth: 1)
                }

            if !gestureButtons.isEmpty {
                mxProfileMappingBox("Gesture button", buttons: gestureButtons, record: record)
            }
            if !mainButtons.isEmpty {
                mxProfileMappingBox("Buttons", buttons: mainButtons, record: record)
            }
            if !otherButtons.isEmpty {
                mxProfileMappingBox("Other buttons", buttons: otherButtons, record: record)
            }
            if groups.contains(where: { $0.id == "thumb-wheel" }) {
                mxThumbWheelModeBox()
            }
        }
        .padding(10)
        .background(
            Palette.surface(colorScheme),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Palette.hairline(colorScheme), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.06), radius: 2, y: 1)
    }

    private func mxProfileMappingBox(
        _ title: String,
        buttons: [DeviceButton],
        record: DeviceRecord
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.45)
                .padding(.horizontal, 12)
                .padding(.top, 9)
                .padding(.bottom, 3)

            ForEach(buttons, id: \.self) { button in
                VStack(spacing: 0) {
                    if button.canOwnGestures {
                        mxActionRow(
                            label(for: button, kind: record.kind),
                            button: button,
                            record: record
                        )
                    } else {
                        let mapped = record.selectedProfile.bindings[button]
                            ?? (button.isMXScrollDirection ? .scroll : .none)
                        actionRow(
                            label(for: button, kind: record.kind),
                            button: button,
                            current: mapped
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)

                if button != buttons.last {
                    Divider()
                        .padding(.leading, 12)
                }
            }

            Color.clear.frame(height: 2)
        }
        .background(
            Palette.fill(colorScheme).opacity(0.34),
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Palette.hairline(colorScheme), lineWidth: 1)
        }
    }

    private func mxThumbWheelModeBox() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Thumb wheel")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.45)
                .padding(.horizontal, 12)
                .padding(.top, 9)
                .padding(.bottom, 3)

            LabeledContent("Action") {
                Picker("Action", selection: mxThumbWheelModeBinding) {
                    ForEach(MXWheelMode.thumbWheelOptions, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            .labeledContentStyle(CenteredLabeledContentStyle())
            .padding(.horizontal, 12)
            .padding(.vertical, 5)

            Color.clear.frame(height: 2)
        }
        .background(
            Palette.fill(colorScheme).opacity(0.34),
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Palette.hairline(colorScheme), lineWidth: 1)
        }
        .help("One action for both directions of the thumb wheel.")
    }

    private func mxProfileSelectorCard(for record: DeviceRecord) -> some View {
        let selected = record.selectedProfile
        return VStack(spacing: 8) {
            mxProfileTileGrid(for: record)
            HStack(spacing: 7) {
                Circle()
                    .fill(Palette.good)
                    .frame(width: 7, height: 7)
                Text(monitor.liveMXCaption(for: record))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if !selected.treatsAsMXDefault {
                    Menu {
                        Button("Remove \(selected.mxScopeTitle)", role: .destructive) {
                            pendingMXProfileRemoval = selected
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.body)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Profile actions")
                }
            }
        }
        .padding(.vertical, 3)
    }

    private func mxProfileTileGrid(for record: DeviceRecord) -> some View {
        let columns = [
            GridItem(.adaptive(minimum: 96, maximum: 132), spacing: 8)
        ]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(record.mxScopeProfiles()) { profile in
                mxProfileTile(profile, record: record)
            }
            Button {
                showAddApp = true
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .medium))
                        .frame(width: 25, height: 25)
                    Text("Add App")
                        .font(.caption.weight(.medium))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .foregroundStyle(.secondary)
                .background(
                    .thinMaterial,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            Palette.hairline(colorScheme),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                        )
                }
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityLabel("Add App")
                .help("Add App")
            }
            .buttonStyle(.plain)
        }
    }

    private func mxProfileTile(_ profile: MappingProfile, record: DeviceRecord) -> some View {
        let selected = profile.id == record.selectedProfileID
        let live = monitor.liveMXProfile(for: record).id == profile.id
        return Button {
            monitor.selectProfile(profile.id)
        } label: {
            VStack(spacing: 6) {
                if let bundle = profile.frontmostAppBundleID, !bundle.isEmpty {
                    AppBundleIcon(bundleID: bundle)
                        .frame(width: 25, height: 25)
                } else {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 25, height: 25)
                }
                Text(profile.mxScopeTitle)
                    .font(.caption.weight(selected ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .foregroundStyle(
                selected ? Palette.primaryText(colorScheme) : Palette.secondaryText(colorScheme)
            )
            .background(
                selected
                    ? AnyShapeStyle(Palette.accent.opacity(0.16))
                    : AnyShapeStyle(.thinMaterial),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        selected ? Palette.accent.opacity(0.72) : Palette.hairline(colorScheme),
                        lineWidth: selected ? 1.5 : 1
                    )
            }
            .overlay(alignment: .topTrailing) {
                if live {
                    Circle()
                        .fill(Palette.good)
                        .frame(width: 7, height: 7)
                        .padding(7)
                        .accessibilityLabel("In use")
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(profile.mxScopeTitle)
        .contextMenu {
            if !profile.treatsAsMXDefault {
                Button("Remove", role: .destructive) {
                    pendingMXProfileRemoval = profile
                }
            }
        }
    }

    private func mxHIDPPStatus(for record: DeviceRecord) -> String {
        let live = monitor.mxMasterSnapshot
        if monitor.isLiveMXSelection(live) {
            return sanitizedHIDPPStatus(live.status)
        }
        return "Not connected"
    }

    private func keyboardHIDPPStatus(for record: DeviceRecord) -> String {
        let live = monitor.mxKeyboardSnapshot
        if monitor.isLiveKeyboardSelection(live) {
            return sanitizedHIDPPStatus(live.status)
        }
        return "Not connected"
    }

    private func sanitizedHIDPPStatus(_ status: String) -> String {
        if status.localizedCaseInsensitiveContains("CID") { return "Connected" }
        return status
    }

    @ViewBuilder
    private var mxBatterySection: some View {
        let live = monitor.mxMasterSnapshot
        Section("Battery") {
            if live.batteryAvailable, let percent = live.batteryPercent {
                LabeledContent("Level", value: "\(percent)%")
                LabeledContent("State", value: live.batteryStateDescription)
            } else if monitor.isLiveMXSelection(live) {
                LabeledContent(
                    "Level",
                    value: live.batterySupported || !live.status.hasPrefix("Connected")
                        ? "Reading…"
                        : "Not available"
                )
            } else {
                LabeledContent("Level", value: "Not connected")
            }
        }
    }

    @ViewBuilder
    private var keyboardBatterySection: some View {
        let live = monitor.mxKeyboardSnapshot
        Section("Battery") {
            if live.batteryAvailable, let percent = live.batteryPercent {
                LabeledContent("Level", value: "\(percent)%")
                LabeledContent("State", value: live.batteryStateDescription)
            } else {
                LabeledContent("Level", value: monitor.isLiveKeyboardSelection(live) ? "Reading…" : "Not connected")
            }
        }
    }

    @ViewBuilder
    private func easySwitchSection(
        hosts: [MXEasySwitchHost],
        noun: String,
        canRefresh: Bool,
        onRefresh: @escaping () -> Void
    ) -> some View {
        let columns = (0..<3).map { index in
            hosts.first(where: { $0.index == index }) ?? MXEasySwitchHost.pending(index: index)
        }
        let pending = columns.allSatisfy(\.isPending)
        Section {
            HStack(alignment: .top, spacing: 8) {
                ForEach(columns) { host in
                    easySwitchTile(host)
                }
            }
        } header: {
            HStack {
                Text("Easy-Switch")
                Spacer()
                Button("Refresh", action: onRefresh)
                    .disabled(!canRefresh)
            }
        } footer: {
            if pending {
                bullets(
                    "This \(noun) can stay paired with up to three computers.",
                    "Channel names show once this \(noun) answers."
                )
            } else {
                bullets("This \(noun) can stay paired with up to three computers.")
            }
        }
    }

    private func easySwitchTile(_ host: MXEasySwitchHost) -> some View {
        VStack(spacing: 5) {
            HStack {
                Text(host.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if host.isCurrent {
                    Circle()
                        .fill(Palette.good)
                        .frame(width: 7, height: 7)
                        .accessibilityLabel("Current channel")
                }
            }

            if host.isPending {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: host.isPaired ? "display" : "rectangle.dashed")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(host.isCurrent ? Palette.accent : .secondary)
                    .frame(width: 24, height: 24)
            }

            Text(host.primary)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)

            if let detail = easySwitchTileDetail(host) {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .top)
        .background(
            host.isCurrent
                ? AnyShapeStyle(Palette.accent.opacity(0.14))
                : AnyShapeStyle(.thinMaterial),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    host.isCurrent ? Palette.accent.opacity(0.70) : Palette.hairline(colorScheme),
                    lineWidth: host.isCurrent ? 1.5 : 1
                )
        }
        .accessibilityElement(children: .combine)
    }

    private func easySwitchTileDetail(_ host: MXEasySwitchHost) -> String? {
        if host.isPending { return "Reading…" }
        if host.isCurrent {
            if let secondary = host.secondary, !secondary.isEmpty {
                return host.primary == "This Mac" ? secondary : "This Mac · \(secondary)"
            }
            return host.primary == "This Mac" ? "Current" : "This Mac"
        }
        return host.secondary
    }

    @ViewBuilder
    private var keyboardSettingsSection: some View {
        let live = monitor.mxKeyboardSnapshot
        let liveForRecord = monitor.isLiveKeyboardSelection(live)
        let disabled = !liveForRecord
        Section {
            Toggle("Backlight", isOn: keyboardBacklightBinding)
                .disabled(disabled || !live.backlightSupported)
            Picker("Lighting effect", selection: keyboardEffectBinding) {
                ForEach(keyboardPickerEffects) { effect in
                    Text(effect.title).tag(effect)
                }
            }
            .disabled(disabled || !live.backlightSupported)
            Toggle("Battery saving", isOn: keyboardBatterySavingBinding)
                .disabled(disabled || !live.batterySavingSupported)
        } header: {
            Text("Keyboard")
        } footer: {
            bullets(
                "Backlight and battery saving are stored on the keyboard.",
                "Battery saving turns the backlight off when charge is critically low.",
                "Quit Logi Options+ if HID++ stays disconnected."
            )
        }
    }

    private var keyboardPickerEffects: [MXKeyboardBacklightEffect] {
        let live = monitor.mxKeyboardSnapshot
        var effects = live.supportedEffects
        if !effects.contains(live.backlightEffect) {
            effects.insert(live.backlightEffect, at: 0)
        }
        return effects
    }

    private var keyboardBacklightBinding: Binding<Bool> {
        Binding(
            get: { monitor.mxKeyboardSnapshot.backlightEnabled },
            set: { monitor.setKeyboardBacklightEnabled($0) }
        )
    }

    private var keyboardEffectBinding: Binding<MXKeyboardBacklightEffect> {
        Binding(
            get: { monitor.mxKeyboardSnapshot.backlightEffect },
            set: { monitor.setKeyboardBacklightEffect($0) }
        )
    }

    private var keyboardBatterySavingBinding: Binding<Bool> {
        Binding(
            get: { monitor.mxKeyboardSnapshot.batterySaving },
            set: { monitor.setKeyboardBatterySaving($0) }
        )
    }

    private func buttonGroups(for record: DeviceRecord) -> [DeviceButtonGroup] {
        if record.isMXKeyboard { return [] }
        if record.isMXMaster {
            if record.kind.isMXMaster3Family {
                return DeviceButton.mxMasterGroups.map { group in
                    DeviceButtonGroup(
                        id: group.id,
                        title: group.title,
                        buttons: group.buttons.filter { $0 != .mxSide }
                    )
                }
            }
            return DeviceButton.mxMasterGroups
        }
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
        case .mxSide: return "Side"
        default: return button.title
        }
    }

    private func actionBinding(for button: DeviceButton) -> Binding<String> {
        Binding(
            get: {
                if customizingButton == button {
                    return ControlActionOption.customID
                }
                if let action = monitor.selectedProfile.bindings[button] {
                    return action.catalogID
                }
                return button.isMXScrollDirection ? "scroll" : ControlAction.none.catalogID
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

    private var mxThumbWheelModeBinding: Binding<MXWheelMode> {
        Binding(
            get: { monitor.selectedProfile.resolvedMXThumbWheelMode },
            set: { monitor.setMXThumbWheelMode($0) }
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
            width: 140,
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

private struct CenteredLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 8) {
            configuration.label
            Spacer(minLength: 8)
            configuration.content
        }
    }
}
