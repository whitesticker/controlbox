import SwiftUI

struct SettingsPane: View {
    @Bindable private var settings = AppSettings.shared

    private let website = URL(string: "https://whitesticker.github.io/controlbox/")!

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Hide Dock icon", isOn: $settings.hideDockIcon)
                } footer: {
                    footerBullets(
                        "Stays in the menu bar.",
                        "Command-Q closes the window; the app keeps running.",
                        "Quit from the Control Box menu bar extra."
                    )
                }

                Section {
                    LabeledContent("Version", value: version)
                    Link("Website", destination: website)
                } footer: {
                    Text("Install instructions, screenshots, and source.")
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
