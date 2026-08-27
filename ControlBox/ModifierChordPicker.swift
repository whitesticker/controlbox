import CoreGraphics
import ControlBoxCore
import SwiftUI

struct ModifierChordPicker: View {
    var title: String
    @Binding var flags: UInt64
    var minimumCount: Int = 0
    var occupied: [(name: String, flags: CGEventFlags)] = []
    @Binding var message: String?
    var onConflict: ((String) -> Void)? = nil

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
                message = nil
                onConflict?(name)
                return
            }
            message = nil
            flags = next.rawValue
        }
        .buttonStyle(.plain)
        .font(.body.weight(.semibold))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(on ? Color.accentColor : Color.secondary.opacity(0.16))
        )
        .foregroundStyle(on ? Color.white : Color.primary)
    }
}

extension View {
    func modifierConflictAlert(_ name: Binding<String?>) -> some View {
        alert(
            "Pick another set",
            isPresented: Binding(
                get: { name.wrappedValue != nil },
                set: { if !$0 { name.wrappedValue = nil } }
            )
        ) {
            Button("OK", role: .cancel) { name.wrappedValue = nil }
        } message: {
            if let used = name.wrappedValue {
                Text("Those keys are already used by \(used). Pick another set.")
            }
        }
    }
}
