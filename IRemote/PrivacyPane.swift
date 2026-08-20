import SwiftUI

struct PrivacyPane: View {
    @Bindable var monitor: DualSenseMonitor

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Accessibility") {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(monitor.accessibilityTrusted ? Palette.good : Palette.bad)
                                .frame(width: 8, height: 8)
                            Text(monitor.accessibilityTrusted ? "Allowed" : "Not allowed")
                        }
                    }
                    if !monitor.accessibilityTrusted {
                        Button("Request Accessibility Access…") {
                            monitor.promptForAccessibility()
                        }
                        Button("Relaunch VibeRemote") {
                            monitor.relaunchApp()
                        }
                    }
                } footer: {
                    Text(monitor.accessibilityTrusted
                         ? "This running copy of VibeRemote can inject keyboard, pointer, and scroll events."
                         : "After you enable VibeRemote in System Settings, relaunch the app. macOS does not apply Accessibility to a process that is already running.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Privacy & Security")
        }
    }
}
