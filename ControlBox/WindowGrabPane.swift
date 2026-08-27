import CoreGraphics
import ControlBoxCore
import SwiftUI

struct WindowGrabPane: View {
    @Bindable var monitor: DualSenseMonitor
    @Bindable var arrangementCatalog: ArrangementCatalog
    @State private var chordMessage: String?
    @State private var conflictName: String?
    @State private var recordingOrganize = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Move window", isOn: windowMoveEnabledBinding)
                    ModifierChordPicker(
                        title: "Move keys",
                        flags: windowMoveFlagsBinding,
                        minimumCount: 1,
                        occupied: occupancy.occupied(except: "Window Grab move"),
                        message: $chordMessage,
                        onConflict: { conflictName = $0 }
                    )
                    Toggle("Resize window", isOn: windowResizeEnabledBinding)
                    ModifierChordPicker(
                        title: "Resize keys",
                        flags: windowResizeFlagsBinding,
                        minimumCount: 1,
                        occupied: occupancy.occupied(except: "Window Grab resize"),
                        message: $chordMessage,
                        onConflict: { conflictName = $0 }
                    )
                    if let chordMessage {
                        Text(chordMessage)
                            .foregroundStyle(.red)
                    }
                } footer: {
                    Text("Hold the move keys and move the pointer to drag a window from anywhere. Hold the resize keys and move to grow or shrink from the bottom-right; the top-left stays put. Works with the trackpad, any mouse, or DualSense. Accessibility must be on. These keys cannot match Throw, Display Arrangement, or each other.")
                }

                Section {
                    Toggle("Throw window", isOn: windowThrowEnabledBinding)
                    ModifierChordPicker(
                        title: "Throw keys",
                        flags: windowThrowFlagsBinding,
                        minimumCount: 1,
                        occupied: occupancy.occupied(except: "Window Grab throw"),
                        message: $chordMessage,
                        onConflict: { conflictName = $0 }
                    )
                } footer: {
                    Text("Hold these keys and move the pointer. The window under the cursor snaps to a 3×3 map of that screen: corners are quarters, edges are halves, center is full size. Off until this toggle is on.")
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
                    Text("Press this shortcut to tile visible windows on the pointer’s screen. Press it again to shuffle which window sits in each tile. Default is Control-Command-O. Off until this toggle is on. Record modifiers plus a key; it cannot use Display Arrangement’s number or arrow keys with the same modifiers.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Window Grab")
            .modifierConflictAlert($conflictName)
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
            except: "Window Grab move",
            set: { monitor.setWindowMoveEnabled($0) }
        )
    }

    private var windowResizeEnabledBinding: Binding<Bool> {
        enabledBinding(
            get: { monitor.macMouseProfile.resolvedWindowResizeEnabled },
            flags: { monitor.macMouseProfile.resolvedWindowResizeFlags },
            except: "Window Grab resize",
            set: { monitor.setWindowResizeEnabled($0) }
        )
    }

    private var windowThrowEnabledBinding: Binding<Bool> {
        enabledBinding(
            get: { monitor.macMouseProfile.resolvedWindowThrowEnabled },
            flags: { monitor.macMouseProfile.resolvedWindowThrowFlags },
            except: "Window Grab throw",
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
}
