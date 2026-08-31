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
                    footer
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

    private var footer: Text {
        footerBullets(
            "Caps Lock no longer toggles capitals.",
            "Hold it for the modifiers below (default: Control).",
            "Other apps do not see Caps Lock or a Hyper key.",
            "Input Monitoring must be on."
        )
    }
}
