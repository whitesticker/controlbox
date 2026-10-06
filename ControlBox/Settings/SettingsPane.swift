import SwiftUI

struct SettingsPane: View {
    @Bindable private var settings = AppSettings.shared

    private let website = URL(string: "https://whitesticker.github.io/controlbox/")!

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $settings.hideDockIcon) {
                        SettingsRowLabel(
                            "Hide Dock icon",
                            "Stays in the menu bar."
                        )
                    }
                }

                Section {
                    LabeledContent("Version", value: version)
                    Link("Website", destination: website)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
        }
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
}
