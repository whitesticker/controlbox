import CoreGraphics
import ControlBoxCore
import SwiftUI

struct WindowGrabPane: View {
    @Bindable var monitor: DualSenseMonitor

    var body: some View {
        NavigationStack {
            Form {
                if monitor.hasMXMaster {
                    Section {
                        Toggle("Move window", isOn: windowMoveEnabledBinding)
                        modifierChordRow("Move keys", flags: windowMoveFlagsBinding)
                        Toggle("Resize window", isOn: windowResizeEnabledBinding)
                        modifierChordRow("Resize keys", flags: windowResizeFlagsBinding)
                    } footer: {
                        Text("Hold the move keys and move the pointer to drag a window from anywhere. Hold the resize keys and move to grow or shrink from the bottom-right; the top-left stays put. An MX Master with Control this Mac must be on — DualSense can move the pointer, but grab stays mouse-gated for now.")
                    }
                } else {
                    Section {
                        Text("Add an MX Master to set window move and resize chords.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Window Grab")
        }
    }

    private var windowMoveEnabledBinding: Binding<Bool> {
        Binding(
            get: { monitor.macMouseProfile.resolvedWindowMoveEnabled },
            set: { monitor.setWindowMoveEnabled($0) }
        )
    }

    private var windowResizeEnabledBinding: Binding<Bool> {
        Binding(
            get: { monitor.macMouseProfile.resolvedWindowResizeEnabled },
            set: { monitor.setWindowResizeEnabled($0) }
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

    private func modifierChordRow(_ title: String, flags: Binding<UInt64>) -> some View {
        HStack {
            Text(title)
            Spacer()
            modifierChip("⌃", .maskControl, flags)
            modifierChip("⇧", .maskShift, flags)
            modifierChip("⌥", .maskAlternate, flags)
            modifierChip("⌘", .maskCommand, flags)
        }
    }

    private func modifierChip(_ label: String, _ bit: CGEventFlags, _ flags: Binding<UInt64>) -> some View {
        let on = CGEventFlags(rawValue: flags.wrappedValue).contains(bit)
        return Button(label) {
            var next = CGEventFlags(rawValue: flags.wrappedValue)
            if on {
                next.remove(bit)
            } else {
                next.insert(bit)
            }
            flags.wrappedValue = next.rawValue
        }
        .buttonStyle(.bordered)
        .tint(on ? Color.accentColor : Color.secondary)
    }
}
