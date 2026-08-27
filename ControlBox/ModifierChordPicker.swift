import CoreGraphics
import ControlBoxCore
import SwiftUI

struct ModifierChordPicker: View {
    var title: String
    @Binding var flags: UInt64
    var minimumCount: Int = 0
    var occupied: [(name: String, flags: CGEventFlags)] = []
    @Binding var message: String?

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            chip("⌃", .maskControl)
            chip("⇧", .maskShift)
            chip("⌥", .maskAlternate)
            chip("⌘", .maskCommand)
        }
    }

    private func chip(_ label: String, _ bit: CGEventFlags) -> some View {
        let on = CGEventFlags(rawValue: flags).contains(bit)
        return Button(label) {
            var next = ModifierChords.normalized(flags)
            if on {
                next.remove(bit)
            } else {
                next.insert(bit)
            }
            if ModifierChords.count(next) < minimumCount {
                message = "Choose at least \(minimumCount) modifier keys."
                return
            }
            if let name = ModifierChords.collision(next, occupied: occupied) {
                message = "Those keys are already used by \(name)."
                return
            }
            message = nil
            flags = next.rawValue
        }
        .buttonStyle(.bordered)
        .tint(on ? Color.accentColor : Color.secondary)
    }
}
