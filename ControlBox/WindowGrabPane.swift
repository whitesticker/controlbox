import CoreGraphics
import ControlBoxCore
import SwiftUI

struct WindowGrabPane: View {
    @Bindable var monitor: DualSenseMonitor
    @Bindable var arrangementCatalog: ArrangementCatalog
    @State private var chordMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Move window", isOn: windowMoveEnabledBinding)
                    ModifierChordPicker(
                        title: "Move keys",
                        flags: windowMoveFlagsBinding,
                        minimumCount: 1,
                        occupied: occupiedExceptMove,
                        message: $chordMessage
                    )
                    Toggle("Resize window", isOn: windowResizeEnabledBinding)
                    ModifierChordPicker(
                        title: "Resize keys",
                        flags: windowResizeFlagsBinding,
                        minimumCount: 1,
                        occupied: occupiedExceptResize,
                        message: $chordMessage
                    )
                    if let chordMessage {
                        Text(chordMessage)
                            .foregroundStyle(.red)
                    }
                } footer: {
                    Text("Hold the move keys and move the pointer to drag a window from anywhere. Hold the resize keys and move to grow or shrink from the bottom-right; the top-left stays put. Works with the trackpad, any mouse, or DualSense. Accessibility must be on. These keys cannot match Display Arrangement or each other.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Window Grab")
        }
    }

    private var occupiedExceptMove: [(name: String, flags: CGEventFlags)] {
        var items: [(name: String, flags: CGEventFlags)] = []
        if monitor.macMouseProfile.resolvedWindowResizeEnabled {
            items.append(("Window Grab resize", monitor.macMouseProfile.resolvedWindowResizeFlags))
        }
        items.append(contentsOf: arrangementOccupied)
        return items
    }

    private var occupiedExceptResize: [(name: String, flags: CGEventFlags)] {
        var items: [(name: String, flags: CGEventFlags)] = []
        if monitor.macMouseProfile.resolvedWindowMoveEnabled {
            items.append(("Window Grab move", monitor.macMouseProfile.resolvedWindowMoveFlags))
        }
        items.append(contentsOf: arrangementOccupied)
        return items
    }

    private var arrangementOccupied: [(name: String, flags: CGEventFlags)] {
        guard arrangementCatalog.shortcutEnabled else { return [] }
        return [("Display Arrangement", CGEventFlags(rawValue: arrangementCatalog.shortcutFlags))]
    }

    private var windowMoveEnabledBinding: Binding<Bool> {
        Binding(
            get: { monitor.macMouseProfile.resolvedWindowMoveEnabled },
            set: { enabled in
                if enabled, let name = ModifierChords.collision(
                    monitor.macMouseProfile.resolvedWindowMoveFlags,
                    occupied: occupiedExceptMove
                ) {
                    chordMessage = "Those keys are already used by \(name)."
                    return
                }
                chordMessage = nil
                monitor.setWindowMoveEnabled(enabled)
            }
        )
    }

    private var windowResizeEnabledBinding: Binding<Bool> {
        Binding(
            get: { monitor.macMouseProfile.resolvedWindowResizeEnabled },
            set: { enabled in
                if enabled, let name = ModifierChords.collision(
                    monitor.macMouseProfile.resolvedWindowResizeFlags,
                    occupied: occupiedExceptResize
                ) {
                    chordMessage = "Those keys are already used by \(name)."
                    return
                }
                chordMessage = nil
                monitor.setWindowResizeEnabled(enabled)
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
}
