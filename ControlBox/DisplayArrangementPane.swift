import AppKit
import ControlBoxCore
import SwiftUI

struct DisplayArrangementPane: View {
    @Bindable var catalog: ArrangementCatalog
    @Bindable var monitor: DualSenseMonitor
    @State private var editor: ArrangementEditorSession?
    @State private var renameText: [String: String] = [:]
    @State private var shortcutMessage: String?
    @State private var conflictName: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("This Mac") {
                        Text(liveSummary)
                            .multilineTextAlignment(.trailing)
                    }
                    Button("Save Current Arrangement") {
                        catalog.saveCurrent()
                    }
                    .disabled(catalog.live.screens.isEmpty)
                    Button("New Arrangement…") {
                        editor = catalog.newEditorSession()
                    }
                    .disabled(catalog.live.screens.count < 2)
                } footer: {
                    Text("Save Current captures this layout. New Arrangement opens an editor; screens do not move until you apply a preset.")
                }

                if let applyMessage = catalog.applyMessage {
                    Section {
                        Text(applyMessage)
                            .foregroundStyle(catalog.applyFailed ? Color.red : .secondary)
                    }
                }

                Section {
                    Toggle("Keyboard shortcut", isOn: shortcutEnabledBinding)
                    ModifierChordPicker(
                        title: "Shortcut keys",
                        flags: shortcutFlagsBinding,
                        minimumCount: 3,
                        occupied: occupancy.occupied(except: "Display Arrangement"),
                        message: $shortcutMessage,
                        onConflict: { conflictName = $0 }
                    )
                    if let shortcutMessage {
                        Text(shortcutMessage)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Shortcut")
                } footer: {
                    Text("Hold at least three modifier keys, then press 1–9 to apply a layout for the displays that are connected now, or press an arrow key to move through them. Accessibility must be on. These keys cannot match Window Management move, resize, or throw. If Organize uses the same modifiers, it cannot use 1–9 or the arrows.")
                }

                if catalog.store.presets.isEmpty && catalog.live.screens.count < 2 {
                    Section {
                        Text("Connect a second display to save an arrangement.")
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(catalog.combos) { combo in
                    let presets = catalog.presets(for: combo.id)
                    if !presets.isEmpty {
                        Section {
                            ForEach(presets) { preset in
                                presetRow(preset)
                            }
                        } header: {
                            Text(comboHeader(combo))
                        } footer: {
                            comboFooter(combo, presets: presets)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Display Arrangement")
            .onAppear { catalog.refresh() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
                catalog.refresh()
            }
            .sheet(item: $editor) { session in
                ArrangementEditorSheet(
                    session: session,
                    onCancel: { editor = nil },
                    onSave: { next in
                        catalog.saveEditor(session: next)
                        editor = nil
                    }
                )
            }
            .modifierConflictAlert($conflictName)
        }
    }

    private var liveSummary: String {
        var parts = [catalog.live.comboTitle]
        if catalog.live.includesBuiltIn, catalog.live.comboID != DisplayArrangement.comboNone {
            parts.append("Built-in")
        }
        if catalog.live.screens.contains(where: { $0.mirrorMaster != nil }) {
            parts.append("Mirrored")
        }
        return parts.joined(separator: " · ")
    }

    private func comboHeader(_ combo: DisplayCombo) -> String {
        if combo.id == catalog.live.comboID {
            return "Current · \(combo.title)"
        }
        return combo.title
    }

    @ViewBuilder
    private func presetRow(_ preset: ArrangementPreset) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                ArrangementCanvas(screens: preset.screens)
                    .frame(width: 88, height: 56)
                    .clipped()
                    .allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Name", text: renameBinding(preset))
                        .textFieldStyle(.plain)
                        .font(.headline)
                    Text(presetSubtitle(preset))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if let number = shortcutNumber(for: preset) {
                    Text("\(number)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .help("\(ShortcutFormatter.modifierGlyphs(catalog.shortcutFlags))\(number)")
                }
                if catalog.matchesLive(preset) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .help("This is the current arrangement.")
                }
            }
            HStack {
                Button("Apply") {
                    catalog.apply(preset)
                }
                .disabled(!catalog.canApply(preset))
                .help(catalog.applyBlockedReason(preset) ?? "Apply this arrangement.")
                Button("Edit…") {
                    editor = catalog.editorSession(for: preset)
                }
                Spacer()
                Button("Delete", role: .destructive) {
                    catalog.delete(preset)
                }
            }
            if let reason = catalog.applyBlockedReason(preset) {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func comboFooter(_ combo: DisplayCombo, presets: [ArrangementPreset]) -> some View {
        if combo.id != catalog.live.comboID {
            Text("Connect these displays to apply. You can still edit the layout.")
        } else if !catalog.live.includesBuiltIn, presets.contains(where: \.includesBuiltIn) {
            Text("The built-in display is off. Open the lid to apply arrangements that include it.")
        }
    }

    private func presetSubtitle(_ preset: ArrangementPreset) -> String {
        var parts: [String] = []
        parts.append("\(preset.screens.count) displays")
        if preset.includesBuiltIn {
            parts.append("includes built-in")
        }
        if preset.isMirrored {
            parts.append("mirrored")
        }
        return parts.joined(separator: " · ")
    }

    private var occupancy: MacModifierOccupancy {
        monitor.macModifierOccupancy(
            arrangementEnabled: catalog.shortcutEnabled,
            arrangementFlags: CGEventFlags(rawValue: catalog.shortcutFlags)
        )
    }

    private var shortcutEnabledBinding: Binding<Bool> {
        Binding(
            get: { catalog.shortcutEnabled },
            set: { enabled in
                if enabled, let name = occupancy.collision(
                    CGEventFlags(rawValue: catalog.shortcutFlags),
                    except: "Display Arrangement"
                ) {
                    conflictName = name
                    return
                }
                if enabled, organizeUsesArrangementLayoutKeys(CGEventFlags(rawValue: catalog.shortcutFlags)) {
                    conflictName = "Window Management organize"
                    return
                }
                shortcutMessage = nil
                catalog.shortcutEnabled = enabled
            }
        )
    }

    private var shortcutFlagsBinding: Binding<UInt64> {
        Binding(
            get: { catalog.shortcutFlags },
            set: { flags in
                if catalog.shortcutEnabled, organizeUsesArrangementLayoutKeys(CGEventFlags(rawValue: flags)) {
                    conflictName = "Window Management organize"
                    return
                }
                catalog.shortcutFlags = flags
            }
        )
    }

    private func organizeUsesArrangementLayoutKeys(_ flags: CGEventFlags) -> Bool {
        let profile = monitor.macMouseProfile
        guard profile.resolvedWindowOrganizeEnabled else { return false }
        return ModifierChords.collides(flags, profile.resolvedWindowOrganizeFlags)
            && ArrangementHotkey.isLayoutKey(profile.resolvedWindowOrganizeKey)
    }

    private func shortcutNumber(for preset: ArrangementPreset) -> Int? {
        guard catalog.shortcutEnabled else { return nil }
        guard let index = catalog.applicablePresets.firstIndex(where: { $0.id == preset.id }) else {
            return nil
        }
        let number = index + 1
        return number <= 10 ? number : nil
    }

    private func renameBinding(_ preset: ArrangementPreset) -> Binding<String> {
        Binding(
            get: { renameText[preset.id] ?? preset.name },
            set: { name in
                renameText[preset.id] = name
                catalog.rename(preset, to: name)
            }
        )
    }
}
