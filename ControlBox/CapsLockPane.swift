import ControlBoxCore
import SwiftUI

struct CapsLockPane: View {
    @Bindable var catalog: CapsLockCatalog
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Use Caps Lock as a modifier", isOn: enabledBinding)
                    ModifierChordPicker(
                        title: "Caps Lock acts as",
                        flags: flagsBinding,
                        minimumCount: 1,
                        message: $message
                    )
                    .disabled(!catalog.enabled)
                    if catalog.enabled {
                        LabeledContent("Caps Lock") {
                            Text(catalog.isHeld ? "Held" : "Up")
                                .foregroundStyle(catalog.isHeld ? Palette.good : .secondary)
                        }
                    }
                    if let message {
                        Text(message)
                            .foregroundStyle(.red)
                    }
                } footer: {
                    Text(footer)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Caps Lock")
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { catalog.enabled },
            set: { catalog.setEnabled($0) }
        )
    }

    private var flagsBinding: Binding<UInt64> {
        Binding(
            get: { catalog.flags },
            set: { catalog.setFlags($0) }
        )
    }

    private var footer: String {
        "When this is on, Caps Lock no longer toggles capital letters. Hold it and Control Box treats that as the modifiers you pick here — same as holding those keys for Window Management and Display Arrangement. Default is Control, so Move works immediately. Other apps do not see Caps Lock or a Hyper key. Off until this toggle is on. Input Monitoring must be on."
    }
}
