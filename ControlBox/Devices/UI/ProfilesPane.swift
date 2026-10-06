import CoreGraphics
import ControlBoxCore
import SwiftUI

private struct GestureTileTarget: Equatable {
    let button: DeviceButton
    let slot: GestureSlot
}

private struct GestureSetDeletionTarget {
    let button: DeviceButton
    let id: String
    let name: String
}

struct DeviceProfilePane: View {
    @Bindable var monitor: DualSenseMonitor
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme
    @State private var customizingButton: DeviceButton?
    @State private var customizingGestureButton: DeviceButton?
    @State private var customizingGestureSlot: GestureSlot?
    @State private var gestureTileTarget: GestureTileTarget?
    @State private var pendingGestureSetDeletion: GestureSetDeletionTarget?
    @State private var showAddApp = false
    @State private var pendingMXProfileRemoval: MappingProfile?

    var body: some View {
        NavigationStack {
            if let record = monitor.selectedRecord, let device = sidebarDevice {
                Form {
                    if !record.isMXKeyboard {
                        controlThisMacSection
                    }

                    Section {
                        DeviceNameField(
                            name: record.displayName,
                            byteLimit: monitor.selectedFriendlyNameLimit,
                            noun: record.isMXKeyboard ? "keyboard" : "mouse",
                            status: monitor.friendlyNameWrites[record.id],
                            onCommit: { [id = record.id] in monitor.renameDevice(id, to: $0) }
                        )
                        .id(record.id)
                        deviceBatteryRow(for: record)
                        Text(deviceDetails(for: record, device: device))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } header: {
                        Text("Device")
                    }

                    if record.isMXKeyboard {
                        easySwitchSection(
                            hosts: monitor.mxKeyboardSnapshot.easySwitchHosts,
                            canRefresh: monitor.mxKeyboardSnapshot.hidppReady,
                            onRefresh: { monitor.reloadEasySwitch(isKeyboard: true) }
                        )
                        keyboardSettingsSection
                    } else {
                        if record.isMXMaster,
                           record.kind != .logitechMouse
                            || monitor.mxSnapshot(for: record.id).hidppCapabilities.easySwitch {
                            easySwitchSection(
                                hosts: monitor.mxMasterSnapshot.easySwitchHosts,
                                canRefresh: monitor.mxMasterSnapshot.connected,
                                onRefresh: { monitor.reloadEasySwitch(isKeyboard: false) }
                            )
                        }

                        if record.isGamepad || record.isAppleTVRemote {
                            controllerAnalogSection(for: record)
                            controllerPointerScrollSection(for: record)
                        }

                        if record.isMXMaster, showsMXProfiles(for: record) {
                            mxProfilesSections(for: record)
                        } else if record.isGamepad || record.isAppleTVRemote {
                            controllerProfilesSections(for: record)
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
                                } header: {
                                    Text(group.title)
                                } footer: {
                                    if group.id == "clickpad" {
                                        bullets(
                                            "Double-tap Select for a double-click.",
                                            "Hold for the Hold action."
                                        )
                                    }
                                }
                            }
                        }

                    Section {
                        HStack {
                            Button("Calibration…") {
                                openWindow(id: "calibration", value: record.id)
                            }
                            if record.isMXMaster {
                                Button("Mouse Settings…") {
                                    openWindow(id: "mx-mouse-settings")
                                }
                            }
                        }
                    }
                    }

                    if record.remembered {
                        Section {
                            Button("Delete Device…", role: .destructive) {
                                monitor.removeSelectedDevice()
                            }
                            .rowCaption("Add Device brings it back.")
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
                    Text("The \(record.isMXMaster ? "mouse" : (record.isAppleTVRemote ? "remote" : "gamepad")) will use Default in that app.")
                }
                .confirmationDialog(
                    "Delete \(pendingGestureSetDeletion?.name ?? "custom gesture set")?",
                    isPresented: Binding(
                        get: { pendingGestureSetDeletion != nil },
                        set: { if !$0 { pendingGestureSetDeletion = nil } }
                    ),
                    titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive) {
                        if let target = pendingGestureSetDeletion {
                            monitor.deleteNamedCustomGestureSet(target.id, for: target.button)
                        }
                        pendingGestureSetDeletion = nil
                    }
                    Button("Cancel", role: .cancel) {
                        pendingGestureSetDeletion = nil
                    }
                } message: {
                    Text("This custom gesture set cannot be recovered.")
                }
                .onChange(of: monitor.selectedDeviceID) { _, _ in
                    customizingButton = nil
                    customizingGestureButton = nil
                    customizingGestureSlot = nil
                    gestureTileTarget = nil
                    pendingGestureSetDeletion = nil
                }
                .onChange(of: record.selectedProfileID) { _, _ in
                    customizingButton = nil
                    customizingGestureButton = nil
                    customizingGestureSlot = nil
                    gestureTileTarget = nil
                    pendingGestureSetDeletion = nil
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

    private func deviceDetails(
        for record: DeviceRecord,
        device: SidebarDevice
    ) -> String {
        var lines = [
            "Status: \(device.statusTitle)",
            "Type: \(record.kind.title)"
        ]
        var insertAt = 1
        if record.isGamepad, let player = gamepadPlayerLabel(for: record, device: device) {
            lines.insert("Player: \(player)", at: insertAt)
            insertAt += 1
        }
        if let identifier = deviceIdentifier(for: record, device: device) {
            lines.insert(
                "\(DeviceIdentity.displayLabel(for: identifier)): \(identifier)",
                at: insertAt
            )
        }
        if record.isMXMaster {
            lines.append("HID++: \(mxHIDPPStatus(for: record))")
        } else if record.isMXKeyboard {
            lines.append("HID++: \(keyboardHIDPPStatus(for: record))")
        }
        return lines.joined(separator: "\n")
    }

    private func gamepadPlayerLabel(for record: DeviceRecord, device: SidebarDevice) -> Int? {
        let player = device.gamepadPlayerIndex ?? record.gamepadPlayerIndex
        guard let player, (1...4).contains(player) else { return nil }
        return player
    }

    private func deviceBatteryRow(for record: DeviceRecord) -> some View {
        let battery = deviceBatteryPresentation(for: record)
        return LabeledContent("Battery") {
            HStack(spacing: 4) {
                if battery.charging, battery.percent != nil {
                    Image(systemName: "bolt.fill")
                        .font(.caption)
                }
                Text(battery.percent.map { "\($0)%" } ?? battery.placeholder)
            }
        }
        .labeledContentStyle(CenteredLabeledContentStyle())
    }

    private func deviceBatteryPresentation(
        for record: DeviceRecord
    ) -> (percent: Int?, charging: Bool, placeholder: String) {
        if record.isMXMaster {
            let live = monitor.mxMasterSnapshot
            if live.batteryAvailable, let percent = live.batteryPercent {
                return (percent, live.batteryCharging, "")
            }
            if monitor.isLiveMXSelection(live) {
                let placeholder = live.batterySupported || !live.status.hasPrefix("Connected")
                    ? "Reading…"
                    : "Not available"
                return (nil, false, placeholder)
            }
            return (nil, false, "Not connected")
        }

        if record.isMXKeyboard {
            let live = monitor.mxKeyboardSnapshot
            if live.batteryAvailable, let percent = live.batteryPercent {
                return (percent, live.batteryCharging, "")
            }
            return (
                nil,
                false,
                monitor.isLiveKeyboardSelection(live) ? "Reading…" : "Not connected"
            )
        }

        if record.isAppleTVRemote {
            let live = monitor.appleTVSnapshot
            if live.batteryAvailable, let percent = live.batteryPercent {
                return (percent, live.batteryCharging, "")
            }
            return (nil, false, live.connected ? "Reading…" : "Not connected")
        }

        if record.isGamepad {
            let live = monitor.gamepadSnapshot(for: record.id)
            if live.batteryAvailable, let percent = live.batteryPercent {
                return (percent, live.batteryCharging, "")
            }
            return (nil, false, live.connected ? "Reading…" : "Not connected")
        }

        return (nil, false, "Not available")
    }

    @ViewBuilder
    private func controllerAnalogSection(for record: DeviceRecord) -> some View {
        if record.isAppleTVRemote {
            Section {
                Toggle("Clickpad", isOn: analogToggle(.appleTVClickpad, on: .pointer))
                Toggle("Clickwheel", isOn: analogToggle(.appleTVWheel, on: .scroll))
                Toggle("Pointer acceleration", isOn: accelerationBinding)
                .disabled(monitor.selectedProfile.mode(for: .appleTVClickpad) == .off)
                if (monitor.selectedProfile.pointerAcceleration ?? true),
                   monitor.selectedProfile.mode(for: .appleTVClickpad) != .off {
                    SettingsSlider("Amount", value: accelerationAmountBinding)
                }
            } header: {
                Text("Analog")
            }
        } else {
            let capabilities = record.resolvedGamepadCapabilities
            Section {
                analogPicker("Left stick", source: .dualSenseLeftStick)
                analogPicker("Right stick", source: .dualSenseRightStick)
                if capabilities.touchpad {
                    analogPicker(
                        "Touchpad analog",
                        subtitle: "Swipes are under Touchpad gestures.",
                        source: .dualSenseTouchpad
                    )
                }
                Toggle("Pointer acceleration", isOn: accelerationBinding)
                .disabled(!gamepadHasPointerSource(record))
                if (monitor.selectedProfile.pointerAcceleration ?? true),
                   gamepadHasPointerSource(record) {
                    SettingsSlider("Amount", value: accelerationAmountBinding)
                }
                if capabilities.haptics {
                    Toggle("Haptic feedback", isOn: hapticFeedbackBinding)
                }
            } header: {
                Text("Analog")
            }
        }
    }

    private func controllerPointerScrollSection(for record: DeviceRecord) -> some View {
        Section {
            SettingsSlider(
                "Pointer speed",
                value: pointerSpeedBinding
            )
            SettingsSlider(
                "Scroll speed",
                value: wheelSpeedBinding
            )
            if record.isGamepad {
                Toggle("Scroll acceleration", isOn: scrollAccelerationBinding)
                    .disabled(!hasAnalogScrollSource(record))
                if (monitor.selectedProfile.scrollAcceleration == true),
                   hasAnalogScrollSource(record) {
                    SettingsSlider("Amount", value: scrollAccelerationAmountBinding)
                }
            }
            Picker(selection: scrollDirectionBinding) {
                Text("Natural").tag("natural")
                Text("Standard").tag("standard")
            } label: {
                Text("Scroll direction")
            }
            .pickerStyle(.radioGroup)
        } header: {
            Text("Pointer & scroll")
        } footer: {
            Text("Analog and pointer settings apply to every app profile.")
        }
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
            } footer: {
                bullets(
                    "One setting for this remote across every app profile.",
                    "Slow slides stay precise; flicks cover more of the screen.",
                    "Pointer does not move while Select is pressed."
                )
            }
        } else {
            Section {
                analogPicker("Left stick", source: .dualSenseLeftStick)
                analogPicker("Right stick", source: .dualSenseRightStick)
                if record.resolvedGamepadCapabilities.touchpad {
                    analogPicker("Touchpad analog", source: .dualSenseTouchpad)
                }
                Toggle("Pointer acceleration", isOn: accelerationBinding)
                    .disabled(!gamepadHasPointerSource(record))
                if (monitor.selectedProfile.pointerAcceleration ?? true),
                   gamepadHasPointerSource(record) {
                    SettingsSlider("Amount", value: accelerationAmountBinding)
                }
                if record.resolvedGamepadCapabilities.haptics {
                    Toggle("Haptic feedback", isOn: hapticFeedbackBinding)
                }
            } header: {
                Text("Analog")
            } footer: {
                bullets(
                    "One setting for this gamepad across every app profile.",
                    "Sticks only move or scroll if that source is on.",
                    "Touchpad analog is pointer/scroll; swipes are under Touchpad gestures.",
                    "Acceleration: small moves stay precise, flicks speed up.",
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
                "Hold and move for four directions; lift without moving to click.",
                "Physical click is Touchpad click under System."
            )
        }
    }

    @ViewBuilder
    private func analogPicker(_ title: String, subtitle: String? = nil, source: AnalogSource) -> some View {
        Picker(selection: analogBinding(source)) {
            ForEach([AnalogMode.off, .pointer, .scroll], id: \.self) { mode in
                Text(mode.title).tag(mode)
            }
        } label: {
            SettingsRowLabel(title, subtitle)
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
        VStack(alignment: .leading, spacing: 0) {
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
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: current == .gestures)
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
        VStack(alignment: .leading, spacing: 10) {
            Picker(selection: gesturePresetBinding(for: button)) {
                ForEach(GesturePreset.allCases, id: \.self) { preset in
                    Text(preset.title).tag(preset)
                }
            } label: {
                Text("Gesture preset")
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity, alignment: .center)
            .id("\(button.rawValue)-preset")

            if set.preset == .custom {
                customGestureSetSelector(for: button, profile: record.selectedProfile)
                    .transition(.opacity)
            }

            ZStack(alignment: .topLeading) {
                gestureDirectionalPad(for: button, set: set)
                    .id(gesturePadID(for: button, profile: record.selectedProfile))
                    .transition(.opacity)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .animation(
                .easeInOut(duration: 0.18),
                value: gesturePadID(for: button, profile: record.selectedProfile)
            )

            if set.preset == .custom {
                Text("Choose a tile to assign an action.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
                customGestureShortcutEditors(for: button, set: set)
            } else {
                Text("Presets are read-only. Choose Custom to edit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private func customGestureSetSelector(
        for button: DeviceButton,
        profile: MappingProfile
    ) -> some View {
        let sets = profile.namedCustomGestureSets(for: button)
        let selectedID = profile.selectedNamedCustomGestureSetID(for: button)
        let selected = sets.first { $0.id == selectedID }
        return HStack(spacing: 8) {
            Picker("Custom gesture set", selection: namedCustomGestureSetBinding(for: button)) {
                ForEach(sets) { named in
                    Text(named.name).tag(named.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                monitor.addNamedCustomGestureSet(for: button)
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.bordered)
            .help("Add custom gesture set")
            .accessibilityLabel("Add custom gesture set")

            Button(role: .destructive) {
                if let selected {
                    pendingGestureSetDeletion = GestureSetDeletionTarget(
                        button: button,
                        id: selected.id,
                        name: selected.name
                    )
                }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
            .disabled(selected == nil)
            .help("Delete custom gesture set")
            .accessibilityLabel("Delete custom gesture set")
        }
    }

    private func gesturePadID(for button: DeviceButton, profile: MappingProfile) -> String {
        let set = profile.gestureSet(for: button) ?? .named(.windowNavigation)
        if set.preset == .custom {
            return profile.selectedNamedCustomGestureSetID(for: button) ?? "custom"
        }
        return set.preset.rawValue
    }

    @ViewBuilder
    private func customGestureShortcutEditors(
        for button: DeviceButton,
        set: GestureSet
    ) -> some View {
        ForEach(GestureSlot.allCases, id: \.self) { slot in
            let action = set.action(for: slot)
            if showsGestureRecorder(for: button, slot: slot, current: action) {
                HStack(spacing: 8) {
                    Text("\(gestureSlotShortTitle(slot)) shortcut")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    gestureShortcutRecorder(for: button, slot: slot, current: action)
                }
                .transition(.opacity)
            }
        }
    }

    private func gestureDirectionalPad(
        for button: DeviceButton,
        set: GestureSet
    ) -> some View {
        let columns = Array(
            repeating: GridItem(.flexible(minimum: 76), spacing: 7),
            count: 3
        )
        return LazyVGrid(columns: columns, spacing: 7) {
            gesturePadSpacer()
            gestureTile(.up, for: button, set: set)
            gesturePadSpacer()

            gestureTile(.left, for: button, set: set)
            gestureTile(.click, for: button, set: set)
            gestureTile(.right, for: button, set: set)

            gesturePadSpacer()
            gestureTile(.down, for: button, set: set)
            gesturePadSpacer()
        }
    }

    @ViewBuilder
    private func gestureTile(
        _ slot: GestureSlot,
        for button: DeviceButton,
        set: GestureSet
    ) -> some View {
        let current = set.action(for: slot)
        if set.preset == .custom {
            Button {
                gestureTileTarget = GestureTileTarget(button: button, slot: slot)
            } label: {
                gestureTileLabel(slot, action: current)
            }
            .buttonStyle(.plain)
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .accessibilityLabel("\(gestureSlotShortTitle(slot)): \(current.title)")
            .popover(
                isPresented: gestureTilePopoverPresented(for: button, slot: slot),
                arrowEdge: .trailing
            ) {
                gestureMappingPopover(for: button, slot: slot, current: current)
            }
        } else {
            gestureTileLabel(slot, action: current)
                .help("Choose Custom to edit gesture actions.")
        }
    }

    private func gestureMappingPopover(
        for button: DeviceButton,
        slot: GestureSlot,
        current: ControlAction
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(gestureSlotShortTitle(slot))
                .font(.headline)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)

            ForEach(ControlAction.catalog) { option in
                Button {
                    gestureTileTarget = nil
                    monitor.setGestureAction(option.action, slot: slot, for: button)
                } label: {
                    HStack {
                        Text(option.title)
                        Spacer(minLength: 12)
                        if current.catalogID == option.id {
                            Image(systemName: "checkmark")
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }

            Divider()
                .padding(.vertical, 3)

            Button("Custom Shortcut…") {
                gestureTileTarget = nil
                customizingGestureButton = button
                customizingGestureSlot = slot
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .padding(8)
        .frame(width: 230)
    }

    private func gestureTilePopoverPresented(
        for button: DeviceButton,
        slot: GestureSlot
    ) -> Binding<Bool> {
        Binding(
            get: { gestureTileTarget == GestureTileTarget(button: button, slot: slot) },
            set: { if !$0 { gestureTileTarget = nil } }
        )
    }

    private func gestureTileLabel(
        _ slot: GestureSlot,
        action: ControlAction
    ) -> some View {
        VStack(spacing: 5) {
            Image(systemName: gestureSlotSymbol(slot))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.accent)
            Text(action.title)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(gestureSlotShortTitle(slot))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 72)
        .background(
            Palette.fill(colorScheme),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Palette.hairline(colorScheme), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func gesturePadSpacer() -> some View {
        Color.clear
            .frame(height: 72)
            .accessibilityHidden(true)
    }

    private func gestureSlotShortTitle(_ slot: GestureSlot) -> String {
        switch slot {
        case .click: return "Click"
        case .up: return "Up"
        case .down: return "Down"
        case .left: return "Left"
        case .right: return "Right"
        }
    }

    private func gestureSlotSymbol(_ slot: GestureSlot) -> String {
        switch slot {
        case .click: return "circle.fill"
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        case .left: return "arrow.left"
        case .right: return "arrow.right"
        }
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
            SettingsRowLabel("Select", "Double-tap for a double-click.")
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

    @ViewBuilder
    private var controlThisMacSection: some View {
        Section {
            Toggle("Control this Mac", isOn: controlEnabledBinding)
            Toggle("Allow while Control Box is focused", isOn: controlWhileFocusedBinding)
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

    private func hasAnalogScrollSource(_ record: DeviceRecord) -> Bool {
        let profile = record.selectedProfile
        if record.isAppleTVRemote {
            return profile.mode(for: .appleTVClickpad) == .scroll
                || profile.mode(for: .appleTVWheel) == .scroll
        }
        return profile.mode(for: .dualSenseLeftStick) == .scroll
            || profile.mode(for: .dualSenseRightStick) == .scroll
            || (record.resolvedGamepadCapabilities.touchpad
                && profile.mode(for: .dualSenseTouchpad) == .scroll)
    }

    private func gamepadHasPointerSource(_ record: DeviceRecord) -> Bool {
        let profile = record.selectedProfile
        if profile.mode(for: .dualSenseLeftStick) == .pointer { return true }
        if profile.mode(for: .dualSenseRightStick) == .pointer { return true }
        if record.resolvedGamepadCapabilities.touchpad,
           profile.mode(for: .dualSenseTouchpad) == .pointer {
            return true
        }
        return false
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
        for candidate in [device.address, record.address] {
            if candidate.hasPrefix("slot:") { continue }
            if DeviceIdentity.isConcrete(candidate) {
                return DeviceIdentity.format(candidate)
            }
        }
        return nil
    }

    private func bullets(_ lines: String...) -> Text {
        footerBullets(Array(lines))
    }

    private func mxButtonsFooter(for record: DeviceRecord) -> Text {
        if record.kind.isMXMaster3Family {
            return footerBullets(
                "Gesture is the thumb button: hold and move, or tap to Click."
            )
        }
        return footerBullets(
            "Haptic is the force pad. Gesture is the thumb button. Both can be Gestures."
        )
    }

    @ViewBuilder
    private func controllerProfilesSections(for record: DeviceRecord) -> some View {
        Section {
            appProfileSelectorCard(for: record)
                .listRowSeparator(.hidden)
            if record.isGamepad, record.resolvedGamepadCapabilities.touchpad {
                profileGroupBox(
                    "Touchpad gestures",
                    footer: bullets(
                        "Hold and move for four directions; lift without moving to click.",
                        "Physical click is Touchpad click under System."
                    )
                ) {
                    profileGroupRow {
                        mxActionRow("1-finger swipe", button: .touchpadOneFinger, record: record)
                    }
                    Divider().padding(.leading, 12)
                    profileGroupRow {
                        mxActionRow("2-finger swipe", button: .touchpadTwoFinger, record: record)
                    }
                }
            }
            ForEach(buttonGroups(for: record)) { group in
                profileGroupBox(group.title, footer: controllerButtonFooter(group, record: record)) {
                    ForEach(group.buttons, id: \.self) { button in
                        profileGroupRow {
                            if button == .clickSelect {
                                selectRow(for: record)
                            } else if button.canOwnGestures {
                                mxActionRow(
                                    mxLabel(for: button, record: record),
                                    button: button,
                                    record: record
                                )
                            } else {
                                let mapped = record.selectedProfile.bindings[button]
                                    ?? (button.isMXScrollDirection ? .scroll : .none)
                                actionRow(
                                    mxLabel(for: button, record: record),
                                    button: button,
                                    current: mapped
                                )
                            }
                        }
                        if button != group.buttons.last {
                            Divider().padding(.leading, 12)
                        }
                    }
                }
            }
        } header: {
            Text("Profiles")
        }
    }

    private func profileGroupBox<Content: View>(
        _ title: String,
        footer: Text? = nil,
        @ViewBuilder content: () -> Content
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

            content()

            if let footer {
                footer
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 3)
                    .padding(.bottom, 9)
            } else {
                Color.clear.frame(height: 4)
            }
        }
        .background(
            Palette.fill(colorScheme).opacity(0.34),
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Palette.hairline(colorScheme), lineWidth: 1)
        }
        .padding(.vertical, 3)
        .listRowSeparator(.hidden)
    }

    private func profileGroupRow<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
    }

    private func controllerButtonFooter(
        _ group: DeviceButtonGroup,
        record: DeviceRecord
    ) -> Text? {
        if group.id == "sticks" {
            return Text("L3 and R3 are stick clicks.")
        }
        if group.id == "shoulders", record.isGamepad {
            let layout = record.resolvedGamepadLayout
            let l2 = layout.label(for: .l2)
            let r2 = layout.label(for: .r2)
            let l1 = layout.label(for: .l1)
            let r1 = layout.label(for: .r1)
            return Text("\(l2) / \(r2) tab switching: half pull = one tab, full hold = repeat.")
        }
        return nil
    }

    @ViewBuilder
    private func mxProfilesSections(for record: DeviceRecord) -> some View {
        let groups = buttonGroups(for: record)
        let buttonGroup = groups.first(where: { $0.id == "buttons" })
        let gestureButtons = buttonGroup?.buttons.filter {
            isGestureCapable($0, for: record)
        } ?? []
        let availableButtons = Set(buttonGroup?.buttons ?? [])
        let mainButtonOrder: [DeviceButton] = [.mxMiddle, .mxBack, .mxForward, .mxSmartShift]
        let mainButtons = mainButtonOrder.filter {
            availableButtons.contains($0) && !gestureButtons.contains($0)
        }
        let otherButtons = buttonGroup?.buttons.filter {
            !gestureButtons.contains($0) && !mainButtonOrder.contains($0)
        } ?? []

        Section {
            appProfileSelectorCard(for: record)
                .listRowSeparator(.hidden)
            if !gestureButtons.isEmpty {
                mxMappingBox("Gesture-capable controls", buttons: gestureButtons, record: record)
            }
            if !otherButtons.isEmpty {
                mxMappingBox("Other buttons", buttons: otherButtons, record: record)
            }
            if groups.contains(where: { $0.id == "thumb-wheel" }) {
                mxThumbWheelBox()
            }
            if !mainButtons.isEmpty {
                mxMappingBox("Buttons", buttons: mainButtons, record: record)
            }
        } header: {
            Text("Profiles")
        }
    }

    private func mxMappingBox(
        _ title: String,
        buttons: [DeviceButton],
        record: DeviceRecord
    ) -> some View {
        profileGroupBox(title) {
            ForEach(buttons, id: \.self) { button in
                profileGroupRow {
                    if isGestureCapable(button, for: record) {
                        mxActionRow(
                            mxLabel(for: button, record: record),
                            button: button,
                            record: record
                        )
                    } else {
                        let mapped = record.selectedProfile.bindings[button]
                            ?? (button.isMXScrollDirection ? .scroll : .none)
                        actionRow(
                            mxLabel(for: button, record: record),
                            button: button,
                            current: mapped
                        )
                    }
                }
                if button != buttons.last {
                    Divider().padding(.leading, 12)
                }
            }
        }
    }

    private func mxThumbWheelBox() -> some View {
        profileGroupBox("Thumb wheel") {
            profileGroupRow {
                LabeledContent {
                    Picker("Action", selection: mxThumbWheelModeBinding) {
                        ForEach(MXWheelMode.thumbWheelOptions, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                } label: {
                    Text("Action")
                }
                .labeledContentStyle(CenteredLabeledContentStyle())
            }
        }
    }

    private func appProfileSelectorCard(for record: DeviceRecord) -> some View {
        let selected = record.selectedProfile
        return VStack(spacing: 8) {
            appProfileTileGrid(for: record)
            HStack(spacing: 7) {
                Circle()
                    .fill(Palette.good)
                    .frame(width: 7, height: 7)
                Text(monitor.liveAppCaption(for: record))
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

    private func appProfileTileGrid(for record: DeviceRecord) -> some View {
        let columns = [
            GridItem(.adaptive(minimum: 96, maximum: 132), spacing: 8)
        ]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(record.appScopeProfiles()) { profile in
                appProfileTile(profile, record: record)
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
                    Palette.fill(colorScheme),
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

    private func appProfileTile(_ profile: MappingProfile, record: DeviceRecord) -> some View {
        let selected = profile.id == record.selectedProfileID
        let live = monitor.liveAppProfile(for: record).id == profile.id
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
                    ? Palette.accent.opacity(0.16)
                    : Palette.fill(colorScheme),
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
    private func easySwitchSection(
        hosts: [MXEasySwitchHost],
        canRefresh: Bool,
        onRefresh: @escaping () -> Void
    ) -> some View {
        let columns = (0..<3).map { index in
            hosts.first(where: { $0.index == index }) ?? MXEasySwitchHost.pending(index: index)
        }
        Section {
            HStack(alignment: .top, spacing: 8) {
                ForEach(columns) { host in
                    easySwitchTile(host)
                }
            }
            .padding(.vertical, 3)
        } header: {
            HStack {
                Text("Easy-Switch")
                Spacer()
                Button("Refresh", action: onRefresh)
                    .disabled(!canRefresh)
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
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .accessibilityLabel("Pending")
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
                ? Palette.accent.opacity(0.14)
                : Palette.fill(colorScheme),
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
            Toggle(isOn: keyboardBatterySavingBinding) {
                SettingsRowLabel(
                    "Battery saving",
                    "Turns the backlight off when charge is critically low."
                )
            }
            .disabled(disabled || !live.batterySavingSupported)
            if keyboardLayoutOption(.macOS) != nil, keyboardLayoutOption(.windows) != nil {
                HStack {
                    SettingsRowLabel(
                        "OS layout",
                        "Per Easy-Switch channel."
                    )
                    Spacer()
                    Picker("OS layout", selection: keyboardOSLayoutBinding) {
                        Text("macOS").tag(LogitechHostOS?.some(.macOS))
                        Text("Windows").tag(LogitechHostOS?.some(.windows))
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                .disabled(disabled)
            }
        } header: {
            Text("Keyboard")
        } footer: {
            Text("Quit Logi Options+ if HID++ stays disconnected.")
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

    private func keyboardLayoutOption(_ os: LogitechHostOS) -> LogitechPlatformOption? {
        monitor.mxKeyboardSnapshot.osLayouts.first { $0.os == os }
    }

    private var keyboardOSLayoutBinding: Binding<LogitechHostOS?> {
        Binding(
            get: {
                let live = monitor.mxKeyboardSnapshot
                return live.osLayouts.first { $0.platformIndex == live.osLayout }?.os
            },
            set: { os in
                guard let os, let option = keyboardLayoutOption(os) else { return }
                monitor.setKeyboardOSLayout(option.platformIndex)
            }
        )
    }

    private func buttonGroups(for record: DeviceRecord) -> [DeviceButtonGroup] {
        if record.isMXKeyboard { return [] }
        if record.isMXMaster {
            if record.kind == .logitechMouse {
                let live = monitor.mxSnapshot(for: record.id)
                return DeviceButton.mxMasterGroups.compactMap { group in
                    let buttons: [DeviceButton]
                    if group.id == "thumb-wheel" {
                        buttons = live.hidppCapabilities.thumbWheel ? group.buttons : []
                    } else {
                        let standard = group.buttons.filter(live.availableButtons.contains)
                        let dynamic = DeviceButton.mxExtraButtons.filter(live.availableButtons.contains)
                        buttons = standard + dynamic
                    }
                    guard !buttons.isEmpty else { return nil }
                    return DeviceButtonGroup(id: group.id, title: group.title, buttons: buttons)
                }
            }
            if record.kind.isMXMaster3Family {
                return DeviceButton.mxMasterGroups.map { group in
                    DeviceButtonGroup(
                        id: group.id,
                        title: group.title,
                        buttons: group.buttons.filter { $0 != .mxHaptic }
                    )
                }
            }
            return DeviceButton.mxMasterGroups
        }
        if record.isAppleTVRemote { return DeviceButton.appleTVGroups }
        if record.isGamepad {
            return DeviceButton.gamepadGroups(hasTouchpad: record.resolvedGamepadCapabilities.touchpad)
        }
        return DeviceButton.dualSenseGroups
    }

    private func showsMXProfiles(for record: DeviceRecord) -> Bool {
        guard record.kind == .logitechMouse else { return true }
        let live = monitor.mxSnapshot(for: record.id)
        return live.hidppCapabilities.reprogrammableControls
            || live.hidppCapabilities.thumbWheel
            || !live.availableButtons.isEmpty
    }

    private func isGestureCapable(_ button: DeviceButton, for record: DeviceRecord) -> Bool {
        guard button.canOwnGestures else { return false }
        if button == .mxHaptic, record.kind != .logitechMouse, !record.kind.isMXMaster3Family {
            return true
        }
        if button == .mxSide || button == .mxSmartShift, record.kind != .logitechMouse {
            return true
        }
        let live = monitor.mxSnapshot(for: record.id)
        if live.connected {
            return live.gestureCapableButtons.contains(button)
        }
        return record.selectedProfile.mxGestureOwners.contains(button) || button == .mxHaptic
    }

    private func mxLabel(for button: DeviceButton, record: DeviceRecord) -> String {
        if record.isGamepad {
            return record.resolvedGamepadLayout.label(for: button)
        }
        return monitor.mxSnapshot(for: record.id).controlTitles[button]
            ?? label(for: button, kind: record.kind)
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
        case .mxHaptic: return "Haptic button"
        case .mxSide: return "Gesture button"
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

    private func namedCustomGestureSetBinding(for button: DeviceButton) -> Binding<String> {
        Binding(
            get: {
                monitor.selectedProfile.selectedNamedCustomGestureSetID(for: button) ?? ""
            },
            set: { monitor.selectNamedCustomGestureSet($0, for: button) }
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

/// Device name with the hardware's UTF-8 byte limit (Chinese characters are 3 bytes each).
/// Commits on Return or focus loss; Escape reverts.
private struct DeviceNameField: View {
    let name: String
    let byteLimit: Int?
    let noun: String
    let status: FriendlyNameWrite?
    let onCommit: (String) -> Void

    @State private var text = ""
    @State private var committed: String?
    @FocusState private var focused: Bool

    private var statusText: String? {
        switch status {
        case .waiting: "Saves to the \(noun) when connected."
        case .saving: "Saving to the \(noun)…"
        case .saved: "Saved to the \(noun)."
        case .failed: "Couldn’t save to the \(noun). Press Return to retry."
        case nil: nil
        }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let unchanged = trimmed == name || trimmed == committed
        guard !unchanged || status == .failed else { return }
        committed = trimmed
        onCommit(trimmed)
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField(text: $text) {
                SettingsRowLabel("Name", statusText)
            }
            .focused($focused)
            .onSubmit(commit)
            .onExitCommand {
                text = name
                committed = nil
                focused = false
            }
            if let byteLimit {
                Text("\(text.utf8.count)/\(byteLimit)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(text.utf8.count >= byteLimit ? .primary : .secondary)
                    .help("This device stores up to \(byteLimit) bytes. Most letters are 1 byte; Chinese characters are 3.")
            }
        }
        .onAppear { text = name }
        .onDisappear(perform: commit)
        .onChange(of: name) { _, newName in
            let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !focused || typed == committed {
                text = newName
            }
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { commit() }
        }
        .onChange(of: text) { _, newText in
            if let byteLimit, newText.utf8.count > byteLimit {
                text = MXFriendlyNameHIDPP.clipped(newText, maxBytes: byteLimit)
            }
        }
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
