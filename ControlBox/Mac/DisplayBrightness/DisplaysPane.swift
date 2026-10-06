import AppKit
import ControlBoxCore
import SwiftUI

struct DisplaysPane: View {
    @Bindable var catalog: DisplayCatalog
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Show in menu bar", isOn: $settings.brightnessMenuBarEnabled)
                }

                if catalog.displays.isEmpty {
                    Section {
                        Text("No displays reported.")
                    }
                } else {
                    unifiedSection

                    ForEach(catalog.displays) { display in
                        Section {
                            SettingsSlider(
                                "Brightness",
                                value: brightnessBinding(display),
                                enabled: display.canAdjustBrightness && !catalog.unifiedEnabled
                            )
                            if !display.isBuiltIn {
                                SettingsSlider(
                                    "Contrast",
                                    value: contrastBinding(display),
                                    enabled: display.canAdjustContrast
                                )
                                SettingsSlider(
                                    "Volume",
                                    value: volumeBinding(display),
                                    enabled: display.canAdjustVolume
                                )
                            }
                            DisplayAdvancedSettings(catalog: catalog, id: display.id)
                        } header: {
                            Text(display.name)
                        } footer: {
                            Text(footer(for: display))
                        }
                    }
                }

                DisplayEngineSettings(catalog: catalog)
            }
            .formStyle(.grouped)
            .navigationTitle("Display Brightness")
            .animation(.easeInOut(duration: 0.2), value: catalog.unifiedEnabled)
            .onAppear { catalog.refresh() }
        }
    }

    @ViewBuilder
    private var unifiedSection: some View {
        Section {
            Toggle(isOn: unifiedEnabledBinding) {
                SettingsRowLabel("One slider for all displays", unifiedSubtitle)
            }
            .disabled(!catalog.canUnify && !catalog.unifiedEnabled)
            if catalog.unifiedEnabled {
                SettingsSlider("Brightness", value: unifiedBrightnessBinding)
            }
        }
    }

    private var unifiedEnabledBinding: Binding<Bool> {
        Binding(
            get: { catalog.unifiedEnabled },
            set: { catalog.setUnifiedEnabled($0) }
        )
    }

    private var unifiedBrightnessBinding: Binding<Double> {
        Binding(
            get: { catalog.unifiedBrightness },
            set: { catalog.setUnifiedBrightness($0) }
        )
    }

    private var unifiedSubtitle: String {
        if catalog.canUnify {
            return "Keeps each panel’s relative mix."
        }
        return "Needs two brightness-adjustable displays."
    }

    private func brightnessBinding(_ display: AttachedDisplay) -> Binding<Double> {
        Binding(
            get: { catalog.displays.first { $0.id == display.id }?.brightness ?? display.brightness },
            set: { catalog.setBrightness($0, id: display.id) }
        )
    }

    private func contrastBinding(_ display: AttachedDisplay) -> Binding<Double> {
        Binding(
            get: { catalog.displays.first { $0.id == display.id }?.contrast ?? display.contrast },
            set: { catalog.setContrast($0, id: display.id) }
        )
    }

    private func volumeBinding(_ display: AttachedDisplay) -> Binding<Double> {
        Binding(
            get: { catalog.displays.first { $0.id == display.id }?.volume ?? display.volume },
            set: { catalog.setVolume($0, id: display.id) }
        )
    }

    private func footer(for display: AttachedDisplay) -> String {
        if display.canAdjustBrightness || display.canAdjustContrast || display.isBuiltIn {
            return display.detail
        }
        return "\(display.detail). HDMI may not support DDC; try USB-C or DisplayPort."
    }
}

/// App-wide engine settings (startup, smooth, sync, keyboard).
private struct DisplayEngineSettings: View {
    let catalog: DisplayCatalog

    var body: some View {
        let _ = catalog.settingsRevision
        Section {
            Picker("Upon startup or wake", selection: intBinding(.startupAction)) {
                Text("Assume last saved settings are valid (recommended)").tag(StartupAction.doNothing.rawValue)
                Text("Apply last saved values to the display").tag(StartupAction.write.rawValue)
                Text("Attempt to read display settings").tag(StartupAction.read.rawValue)
            }
            Toggle("Enable smooth brightness transitions", isOn: Binding(
                get: { !prefs.bool(forKey: PrefKey.disableSmoothBrightness.rawValue) },
                set: { prefs.set(!$0, forKey: PrefKey.disableSmoothBrightness.rawValue); catalog.noteSettingsChanged() }
            ))
            Toggle("Sync brightness changes from Built-in and Apple displays", isOn: boolBinding(.enableBrightnessSync))
        } header: {
            Text("Hardware Control")
        } footer: {
            Text("Hold Shift at launch for Safe mode (no display reads or writes).")
        }

        Section {
            Picker("Brightness keys", selection: intBinding(.keyboardBrightness, after: { app.updateMenusAndKeys() })) {
                Text("Standard keyboard brightness keys").tag(KeyboardBrightness.media.rawValue)
                Text("Disable keyboard").tag(KeyboardBrightness.disabled.rawValue)
            }
            Picker("Brightness keys control", selection: intBinding(.multiKeyboardBrightness, after: { app.updateMediaKeyTap() })) {
                Text("Depends on mouse pointer position").tag(MultiKeyboardBrightness.mouse.rawValue)
                Text("Change for all screens").tag(MultiKeyboardBrightness.allScreens.rawValue)
                Text("Use window focus to determine which display to control").tag(MultiKeyboardBrightness.focusInsteadOfMouse.rawValue)
            }
            Toggle("Use fine OSD scale for brightness and contrast", isOn: boolBinding(.useFineScaleBrightness))
            Toggle(isOn: boolBinding(.disableAltBrightnessKeys, after: { app.updateMediaKeyTap() })) {
                SettingsRowLabel(
                    "Do not use alternative brightness keys",
                    "F14/F15: Scroll Lock and Pause on PC keyboards."
                )
            }
            Picker(selection: intBinding(.keyboardVolume, after: { app.updateMenusAndKeys() })) {
                Text("Standard keyboard volume and mute keys").tag(KeyboardVolume.media.rawValue)
                Text("Disable keyboard").tag(KeyboardVolume.disabled.rawValue)
            } label: {
                SettingsRowLabel(
                    "Volume keys",
                    "Only when the audio output has no volume of its own."
                )
            }
            Picker(selection: intBinding(.multiKeyboardVolume, after: { app.updateMediaKeyTap() })) {
                Text("Depends on mouse pointer position").tag(MultiKeyboardVolume.mouse.rawValue)
                Text("Change volume for all screens").tag(MultiKeyboardVolume.allScreens.rawValue)
                Text("Use audio device name to determine which display to control").tag(MultiKeyboardVolume.audioDeviceNameMatching.rawValue)
            } label: {
                Text("Volume keys control")
            }
            Toggle("Use fine OSD scale for volume", isOn: boolBinding(.useFineScaleVolume))
        } header: {
            Text("Keyboard")
        }
    }

    private func boolBinding(_ key: PrefKey, after: @escaping () -> Void = {}) -> Binding<Bool> {
        Binding(
            get: { prefs.bool(forKey: key.rawValue) },
            set: {
                prefs.set($0, forKey: key.rawValue)
                after()
                catalog.noteSettingsChanged()
            }
        )
    }

    private func intBinding(_ key: PrefKey, after: @escaping () -> Void = {}) -> Binding<Int> {
        Binding(
            get: { prefs.integer(forKey: key.rawValue) },
            set: {
                prefs.set($0, forKey: key.rawValue)
                after()
                catalog.noteSettingsChanged()
            }
        )
    }
}

/// Per-display advanced settings (DDC block, polling, overrides).
private struct DisplayAdvancedSettings: View {
    let catalog: DisplayCatalog
    let id: String

    var body: some View {
        let _ = catalog.settingsRevision
        if let display = catalog.engineDisplay(id: id) {
            DisclosureGroup("Advanced") {
                Toggle("Enabled", isOn: Binding(
                    get: { !display.readPrefAsBool(key: .isDisabled) },
                    set: { display.savePref(!$0, key: .isDisabled); catalog.noteSettingsChanged() }
                ))
                PrefTextField("Friendly name", revision: catalog.settingsRevision, value: {
                    display.readPrefAsString(key: .friendlyName) != "" ? display.readPrefAsString(key: .friendlyName) : display.name
                }) { newValue in
                    let originalValue = display.readPrefAsString(key: .friendlyName) != "" ? display.readPrefAsString(key: .friendlyName) : display.name
                    if newValue != originalValue, !newValue.isEmpty {
                        display.savePref(newValue, key: .friendlyName)
                    }
                    app.updateMenusAndKeys()
                }
                if let other = display as? OtherDisplay {
                    otherDisplaySettings(other)
                }
                Button("Reset Settings") { resetSettings(display) }
            }
        }
    }

    @ViewBuilder
    private func otherDisplaySettings(_ display: OtherDisplay) -> some View {
        Toggle("Use hardware DDC control", isOn: Binding(
            get: { !display.isSw() },
            set: { on in
                ddcButtonToggled(display, on: on)
            }
        ))
        .disabled(display.isSwOnly())
        if !display.isSwOnly() {
            Toggle("Disable macOS volume OSD", isOn: Binding(
                get: { display.readPrefAsBool(key: .hideOsd) },
                set: { display.savePref($0, key: .hideOsd); catalog.noteSettingsChanged() }
            ))
            .disabled(display.isSw())
            Picker("DDC read polling mode", selection: Binding(
                get: { display.readPrefAsInt(key: .pollingMode) },
                set: { newValue in
                    if newValue != display.readPrefAsInt(key: .pollingMode) {
                        display.savePref(newValue, key: .pollingMode)
                    }
                    catalog.noteSettingsChanged()
                }
            )) {
                Text("None").tag(PollingMode.none.rawValue)
                Text("Minimal").tag(PollingMode.minimal.rawValue)
                Text("Normal").tag(PollingMode.normal.rawValue)
                Text("Heavy").tag(PollingMode.heavy.rawValue)
                Text("Custom").tag(PollingMode.custom.rawValue)
            }
            PrefTextField("Polling count", revision: catalog.settingsRevision, value: { String(display.pollingCount) }) { newValue in
                if newValue != "\(display.pollingCount)", !newValue.isEmpty, let newValue = Int(newValue) {
                    display.pollingCount = newValue
                }
                catalog.noteSettingsChanged()
            }
            .disabled(display.readPrefAsInt(key: .pollingMode) != PollingMode.custom.rawValue)
            Toggle("Longer delay during DDC read operations", isOn: Binding(
                get: { display.readPrefAsBool(key: .longerDelay) },
                set: { longerDelayToggled(display, on: $0) }
            ))
            Toggle("Enable Mute DDC command", isOn: Binding(
                get: { display.readPrefAsBool(key: .enableMuteUnmute) },
                set: { on in
                    if on {
                        display.savePref(true, key: .enableMuteUnmute)
                    } else {
                        // If the display is currently muted, toggle back to unmute
                        // to prevent the display becoming stuck in the muted state
                        if display.readPrefAsInt(for: .audioMuteScreenBlank) == 1 {
                            display.toggleMute()
                        }
                        display.savePref(false, key: .enableMuteUnmute)
                    }
                    catalog.noteSettingsChanged()
                }
            ))
            HStack {
                PrefTextField("Override audio device name", revision: catalog.settingsRevision, value: {
                    display.readPrefAsString(key: .audioDeviceNameOverride)
                }) { newValue in
                    audioDeviceNameOverride(display, newValue)
                }
                Button("Use Current") {
                    if let defaultDevice = app.coreAudio.defaultOutputDevice {
                        audioDeviceNameOverride(display, defaultDevice.name)
                    }
                }
            }
            ForEach([Command.brightness, .contrast, .audioSpeakerVolume], id: \.self) { command in
                commandSettings(display, command)
            }
        }
    }

    @ViewBuilder
    private func commandSettings(_ display: OtherDisplay, _ command: Command) -> some View {
        let title = command == .brightness ? "Brightness" : command == .contrast ? "Contrast" : "Volume"
        LabeledContent(title) {
            VStack(alignment: .trailing) {
                Toggle("Available", isOn: Binding(
                    get: { !display.readPrefAsBool(key: .unavailableDDC, for: command) },
                    set: { unavailableDDC(display, command, available: $0) }
                ))
                Toggle("Invert", isOn: Binding(
                    get: { display.readPrefAsBool(key: .invertDDC, for: command) },
                    set: {
                        display.savePref($0, key: .invertDDC, for: command)
                        catalog.reconfigure()
                    }
                ))
            }
        }
        HStack {
            PrefTextField("DDC min", revision: catalog.settingsRevision, value: {
                display.readPrefAsString(key: .minDDCOverride, for: command)
            }) { ddcOverride(display, .minDDCOverride, command, $0) }
            PrefTextField("DDC max", revision: catalog.settingsRevision, value: {
                display.readPrefAsString(key: .maxDDCOverride, for: command)
            }) { ddcOverride(display, .maxDDCOverride, command, $0) }
            PrefTextField("Remap", revision: catalog.settingsRevision, value: {
                display.readPrefAsString(key: .remapDDC, for: command)
            }) { remapDDC(display, command, $0) }
        }
        SettingsSlider(
            "\(title) curve",
            value: Binding(
                get: {
                    Double(display.readPrefAsInt(key: .curveDDC, for: command) == 0 ? 5 : display.readPrefAsInt(key: .curveDDC, for: command))
                },
                set: {
                    display.savePref(Int($0.rounded()), key: .curveDDC, for: command)
                    catalog.noteSettingsChanged()
                }
            ),
            in: 1...9,
            step: 1
        )
    }

    private func ddcButtonToggled(_ display: Display, on: Bool) {
        if on {
            _ = display.setDirectBrightness(1)
            display.savePref(false, key: .forceSw)
        } else {
            display.savePref(true, key: .forceSw)
        }
        _ = display.setDirectBrightness(1)
        catalog.reconfigure()
    }

    private func longerDelayToggled(_ display: OtherDisplay, on: Bool) {
        if on {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("Enable Longer Delay?", comment: "Shown in the alert dialog")
            alert.informativeText = NSLocalizedString("Are you sure you want to enable a longer delay? Doing so may freeze your system and require a restart. Start at login will be disabled as a safety measure.", comment: "Shown in the alert dialog")
            alert.addButton(withTitle: NSLocalizedString("Yes", comment: "Shown in the alert dialog"))
            alert.addButton(withTitle: NSLocalizedString("No", comment: "Shown in the alert dialog"))
            alert.alertStyle = NSAlert.Style.critical
            if alert.runModal() == NSApplication.ModalResponse.alertFirstButtonReturn {
                app.setStartAtLogin(enabled: false)
                display.savePref(true, key: .longerDelay)
            }
        } else {
            display.savePref(false, key: .longerDelay)
        }
        catalog.noteSettingsChanged()
    }

    private func audioDeviceNameOverride(_ display: OtherDisplay, _ value: String) {
        display.savePref(value, key: .audioDeviceNameOverride)
        catalog.reconfigure()
    }

    private func unavailableDDC(_ display: Display, _ command: Command, available: Bool) {
        display.savePref(!available, key: .unavailableDDC, for: command)
        _ = display.setDirectBrightness(1)
        catalog.reconfigure()
    }

    private func ddcOverride(_ display: OtherDisplay, _ prefKey: PrefKey, _ command: Command, _ value: String) {
        if let intValue = Int(value), intValue >= 0, intValue <= 65535 {
            display.savePref(intValue, key: prefKey, for: command)
        } else {
            display.removePref(key: prefKey, for: command)
        }
        catalog.reconfigure()
    }

    private func remapDDC(_ display: OtherDisplay, _ command: Command, _ value: String) {
        let values = value.components(separatedBy: ",")
        var normalizedValues: [String] = []
        var normalizedString = ""
        for value in values {
            let trimmedValue = value.trimmingCharacters(in: CharacterSet(charactersIn: " "))
            if !trimmedValue.isEmpty, let intValue = UInt8(trimmedValue, radix: 16), intValue != 0 {
                normalizedValues.append(String(format: "%02x", intValue))
            }
        }
        var first = true
        for normalizedValue in normalizedValues {
            if !first {
                normalizedString.append(", ")
            }
            normalizedString.append(normalizedValue)
            first = false
        }
        display.savePref(normalizedString, key: .remapDDC, for: command)
        catalog.noteSettingsChanged()
    }

    private func resetSettings(_ display: Display) {
        if let other = display as? OtherDisplay, !other.isSwOnly() {
            ddcButtonToggled(other, on: true)
            other.savePref(false, key: .hideOsd)
            other.savePref(PollingMode.custom.rawValue, key: .pollingMode)
            other.savePref(false, key: .longerDelay)
            audioDeviceNameOverride(other, "")
            for command in [Command.audioSpeakerVolume, .contrast] {
                unavailableDDC(other, command, available: true)
            }
            for command in [Command.brightness, .audioSpeakerVolume, .contrast] {
                ddcOverride(other, .minDDCOverride, command, "")
                ddcOverride(other, .maxDDCOverride, command, "")
                other.savePref(5, key: .curveDDC, for: command)
                other.savePref(false, key: .invertDDC, for: command)
                remapDDC(other, command, "")
            }
            catalog.reconfigure()
        }
        unavailableDDC(display, .brightness, available: true)
        display.savePref(display.name, key: .friendlyName)
        app.updateMenusAndKeys()
        display.savePref(false, key: .isDisabled)
        catalog.noteSettingsChanged()
    }
}

/// Text field that commits on Return, like the AppKit fields it replaces.
private struct PrefTextField: View {
    let title: String
    let revision: Int
    let value: () -> String
    let commit: (String) -> Void
    @State private var text = ""

    init(_ title: String, revision: Int, value: @escaping () -> String, commit: @escaping (String) -> Void) {
        self.title = title
        self.revision = revision
        self.value = value
        self.commit = commit
    }

    var body: some View {
        TextField(title, text: $text)
            .onSubmit {
                commit(text)
                text = value()
            }
            .onAppear { text = value() }
            .onChange(of: revision) { text = value() }
    }
}
