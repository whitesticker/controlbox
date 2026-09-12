import AppKit
import CoreGraphics
import ControlBoxCore
import SwiftUI

struct WindowGrabPane: View {
    @Bindable var monitor: DualSenseMonitor
    @Bindable var arrangementCatalog: ArrangementCatalog
    @State private var chordMessage: String?
    @State private var conflictName: String?
    @State private var recordingOrganize = false
    @State private var addingIgnoredApp = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Move window", isOn: windowMoveEnabledBinding)
                    ModifierChordPicker(
                        title: "Move keys",
                        flags: windowMoveFlagsBinding,
                        minimumCount: 1,
                        occupied: occupancy.occupied(except: "Window Management move"),
                        message: $chordMessage,
                        onConflict: { conflictName = $0 }
                    )
                    Toggle("Resize window", isOn: windowResizeEnabledBinding)
                    ModifierChordPicker(
                        title: "Resize keys",
                        flags: windowResizeFlagsBinding,
                        minimumCount: 1,
                        occupied: occupancy.occupied(except: "Window Management resize"),
                        message: $chordMessage,
                        onConflict: { conflictName = $0 }
                    )
                    if let chordMessage {
                        Text(chordMessage)
                            .foregroundStyle(.red)
                    }
                } footer: {
                    footerBullets(
                        "Hold Move and drag from anywhere.",
                        "Hold Resize and move: grows from the bottom-right; top-left stays put.",
                        "Trackpad, mouse, or DualSense. Accessibility required.",
                        "These keys cannot match Throw, Display Arrangement, Dock click move all, or each other."
                    )
                }

                Section {
                    Toggle("Throw window", isOn: windowThrowEnabledBinding)
                    ModifierChordPicker(
                        title: "Throw keys",
                        flags: windowThrowFlagsBinding,
                        minimumCount: 1,
                        occupied: occupancy.occupied(except: "Window Management throw"),
                        message: $chordMessage,
                        onConflict: { conflictName = $0 }
                    )
                } footer: {
                    footerBullets(
                        "Hold and move: snaps the window under the cursor to a 3×3 map of that screen.",
                        "Corners = quarters, edges = halves, center = full.",
                        "Off until this toggle is on."
                    )
                }

                Section {
                    Toggle("Organize windows", isOn: windowOrganizeEnabledBinding)
                    HStack {
                        Text("Shortcut")
                        Spacer()
                        ShortcutRecorderField(
                            shortcut: organizeShortcut,
                            isRecording: recordingOrganize,
                            onBegin: { recordingOrganize = true },
                            onRecord: { key, flags in
                                recordingOrganize = false
                                recordOrganize(virtualKey: key, flags: flags)
                            },
                            onClear: {
                                recordingOrganize = false
                                chordMessage = "Record a shortcut with at least one modifier and a key."
                            },
                            onCancel: { recordingOrganize = false }
                        )
                    }
                } footer: {
                    footerBullets(
                        "Tiles visible windows on the pointer’s screen. Press again to shuffle.",
                        "Default Control-Command-O. Off until this toggle is on.",
                        "Cannot reuse Display Arrangement’s number or arrow keys with the same modifiers."
                    )
                }

                Section {
                    Toggle("Shake to focus", isOn: windowShakeEnabledBinding)
                    Picker("Hide other windows on", selection: windowShakeScopeBinding) {
                        Text("This display").tag(WindowShakeScope.thisDisplay)
                        Text("All displays").tag(WindowShakeScope.allDisplays)
                    }
                    .pickerStyle(.radioGroup)
                    .disabled(!monitor.macMouseProfile.resolvedWindowShakeEnabled)
                } footer: {
                    footerBullets(
                        "Shake a window (title bar, or while Move is held) to hide the others. Shake again to restore.",
                        "This display / All displays is the physical monitor, not a Space.",
                        "Off until this toggle is on. Accessibility required."
                    )
                }

                Section {
                    Toggle(isOn: windowDockClickBinding) {
                        rowLabel(
                            "Switch to Space",
                            "Go to the Space that has the window, on this display or another. The window stays where it is."
                        )
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        rowLabel(
                            "When already in front",
                            "One click on an app that is in front. Native Dock does nothing here. Fullscreen is left alone."
                        )
                        Picker("When already in front", selection: windowDockClickFrontActionBinding) {
                            Text("Do nothing").tag(DockClickFrontAction.none)
                            Text("Minimize window").tag(DockClickFrontAction.minimize)
                            Text("Hide app").tag(DockClickFrontAction.hide)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                } header: {
                    dockClickHeader("Dock click", "Single click")
                } footer: {
                    Text("Everything else stays native: raise, restore, unhide. Accessibility required.")
                }

                Section {
                    Toggle(isOn: windowDockClickMoveAllBinding) {
                        rowLabel(
                            "Move all windows here",
                            "Hold the keys, then click. Gathers every window of that app onto this display and organizes them."
                        )
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        ModifierChordPicker(
                            title: "Keys",
                            flags: windowDockClickMoveAllFlagsBinding,
                            minimumCount: 1,
                            occupied: occupancy.occupied(except: "Dock click move all"),
                            message: $chordMessage,
                            onConflict: { conflictName = $0 }
                        )
                        Text("Cannot match Move, Resize, Throw, or Display Arrangement.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .disabled(!monitor.macMouseProfile.resolvedWindowDockClickMoveAllEnabled)
                } header: {
                    Text("Modifier click")
                }

                Section {
                    ForEach(ignoredDockClickApps, id: \.self) { bundleID in
                        HStack(spacing: 10) {
                            AppBundleIcon(bundleID: bundleID)
                                .frame(width: 24, height: 24)
                            Text(appName(for: bundleID))
                            Spacer()
                            Button {
                                monitor.removeWindowDockClickIgnoredApp(bundleID)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(appName(for: bundleID))")
                        }
                    }
                    Button("Add App…") {
                        addingIgnoredApp = true
                    }
                } header: {
                    Text("Ignored apps")
                } footer: {
                    Text("These apps keep the native Dock click only.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Window Management")
            .modifierConflictAlert($conflictName)
            .sheet(isPresented: $addingIgnoredApp) {
                AddAppSheet(
                    monitor: monitor,
                    excludedBundleIDs: Set(ignoredDockClickApps),
                    onPick: { bundleID, _ in
                        monitor.addWindowDockClickIgnoredApp(bundleID)
                    }
                )
            }
        }
    }

    private var occupancy: MacModifierOccupancy {
        monitor.macModifierOccupancy(
            arrangementEnabled: arrangementCatalog.shortcutEnabled,
            arrangementFlags: CGEventFlags(rawValue: arrangementCatalog.shortcutFlags)
        )
    }

    private var windowMoveEnabledBinding: Binding<Bool> {
        enabledBinding(
            get: { monitor.macMouseProfile.resolvedWindowMoveEnabled },
            flags: { monitor.macMouseProfile.resolvedWindowMoveFlags },
            except: "Window Management move",
            set: { monitor.setWindowMoveEnabled($0) }
        )
    }

    private var windowResizeEnabledBinding: Binding<Bool> {
        enabledBinding(
            get: { monitor.macMouseProfile.resolvedWindowResizeEnabled },
            flags: { monitor.macMouseProfile.resolvedWindowResizeFlags },
            except: "Window Management resize",
            set: { monitor.setWindowResizeEnabled($0) }
        )
    }

    private var windowThrowEnabledBinding: Binding<Bool> {
        enabledBinding(
            get: { monitor.macMouseProfile.resolvedWindowThrowEnabled },
            flags: { monitor.macMouseProfile.resolvedWindowThrowFlags },
            except: "Window Management throw",
            set: { monitor.setWindowThrowEnabled($0) }
        )
    }

    private var windowOrganizeEnabledBinding: Binding<Bool> {
        Binding(
            get: { monitor.macMouseProfile.resolvedWindowOrganizeEnabled },
            set: { enabled in
                if enabled, let name = organizeArrangementConflict(
                    key: monitor.macMouseProfile.resolvedWindowOrganizeKey,
                    flags: monitor.macMouseProfile.resolvedWindowOrganizeFlags
                ) {
                    conflictName = name
                    return
                }
                chordMessage = nil
                monitor.setWindowOrganizeEnabled(enabled)
            }
        )
    }

    private var organizeShortcut: (virtualKey: UInt16, flags: UInt64)? {
        let profile = monitor.macMouseProfile
        return (profile.resolvedWindowOrganizeKey, profile.resolvedWindowOrganizeFlags.rawValue)
    }

    private func recordOrganize(virtualKey: UInt16, flags: UInt64) {
        let normalized = ModifierChords.normalized(flags)
        if ModifierChords.count(normalized) < 1 {
            chordMessage = "Include at least one modifier key."
            return
        }
        if let name = organizeArrangementConflict(key: virtualKey, flags: normalized) {
            conflictName = name
            return
        }
        chordMessage = nil
        monitor.setWindowOrganizeShortcut(virtualKey: virtualKey, flags: normalized.rawValue)
    }

    private func organizeArrangementConflict(key: UInt16, flags: CGEventFlags) -> String? {
        guard arrangementCatalog.shortcutEnabled else { return nil }
        let arrangement = CGEventFlags(rawValue: arrangementCatalog.shortcutFlags)
        guard ModifierChords.collides(flags, arrangement), ArrangementHotkey.isLayoutKey(key) else {
            return nil
        }
        return "Display Arrangement"
    }

    private func enabledBinding(
        get: @escaping () -> Bool,
        flags: @escaping () -> CGEventFlags,
        except: String,
        set: @escaping (Bool) -> Void
    ) -> Binding<Bool> {
        Binding(
            get: get,
            set: { enabled in
                if enabled, let name = occupancy.collision(flags(), except: except) {
                    conflictName = name
                    return
                }
                chordMessage = nil
                set(enabled)
            }
        )
    }

    private var windowMoveFlagsBinding: Binding<UInt64> {
        Binding(
            get: { monitor.macMouseProfile.resolvedWindowMoveFlags.rawValue },
            set: { monitor.setWindowMoveFlags($0) }
        )
    }

    private var windowResizeFlagsBinding: Binding<UInt64> {
        Binding(
            get: { monitor.macMouseProfile.resolvedWindowResizeFlags.rawValue },
            set: { monitor.setWindowResizeFlags($0) }
        )
    }

    private var windowThrowFlagsBinding: Binding<UInt64> {
        Binding(
            get: { monitor.macMouseProfile.resolvedWindowThrowFlags.rawValue },
            set: { monitor.setWindowThrowFlags($0) }
        )
    }

    private var windowShakeEnabledBinding: Binding<Bool> {
        Binding(
            get: { monitor.macMouseProfile.resolvedWindowShakeEnabled },
            set: { monitor.setWindowShakeEnabled($0) }
        )
    }

    private var windowShakeScopeBinding: Binding<WindowShakeScope> {
        Binding(
            get: { monitor.macMouseProfile.resolvedWindowShakeScope },
            set: { monitor.setWindowShakeScope($0) }
        )
    }

    private var windowDockClickBinding: Binding<Bool> {
        Binding(
            get: { monitor.macMouseProfile.resolvedWindowDockClickEnabled },
            set: { monitor.setWindowDockClickEnabled($0) }
        )
    }

    private var windowDockClickFrontActionBinding: Binding<DockClickFrontAction> {
        Binding(
            get: { monitor.macMouseProfile.resolvedWindowDockClickFrontAction },
            set: { monitor.setWindowDockClickFrontAction($0) }
        )
    }

    private var windowDockClickMoveAllBinding: Binding<Bool> {
        enabledBinding(
            get: { monitor.macMouseProfile.resolvedWindowDockClickMoveAllEnabled },
            flags: { monitor.macMouseProfile.resolvedWindowDockClickMoveAllFlags },
            except: "Dock click move all",
            set: { monitor.setWindowDockClickMoveAllEnabled($0) }
        )
    }

    private var windowDockClickMoveAllFlagsBinding: Binding<UInt64> {
        Binding(
            get: { monitor.macMouseProfile.resolvedWindowDockClickMoveAllFlags.rawValue },
            set: { monitor.setWindowDockClickMoveAllFlags($0) }
        )
    }

    private var ignoredDockClickApps: [String] {
        monitor.macMouseProfile.resolvedWindowDockClickIgnoredBundleIDs
    }

    private func rowLabel(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func dockClickHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
            Divider()
            Text(subtitle)
        }
    }

    private func appName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let bundle = Bundle(url: url) {
            let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            if let name, !name.isEmpty { return name }
        }
        if let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }),
           let name = running.localizedName, !name.isEmpty {
            return name
        }
        return bundleID
    }
}
