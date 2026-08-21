import SwiftUI

struct PrivacyPane: View {
    @Bindable var monitor: DualSenseMonitor

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Status") {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(monitor.allPermissionsGranted ? Palette.good : Palette.bad)
                                .frame(width: 8, height: 8)
                            Text(monitor.allPermissionsGranted ? "All granted" : "Action needed")
                        }
                    }
                } footer: {
                    Text(monitor.allPermissionsGranted
                         ? "VibeRemote can listen to input and inject keyboard, pointer, and scroll events."
                         : "Turn on both Accessibility and Input Monitoring, then relaunch VibeRemote. macOS does not apply a new grant to a process that is already running.")
                }

                Section {
                    permissionRow(
                        title: "Accessibility",
                        allowed: monitor.accessibilityTrusted
                    )
                    if !monitor.accessibilityTrusted {
                        Button("Request Accessibility Access…") {
                            monitor.promptForAccessibility()
                        }
                        Button("Open Accessibility Settings") {
                            monitor.openAccessibilitySettings()
                        }
                    }
                } footer: {
                    Text("Needed to send keys, clicks, gestures, and volume to this Mac.")
                }

                Section {
                    permissionRow(
                        title: "Input Monitoring",
                        allowed: monitor.inputMonitoringTrusted
                    )
                    if !monitor.inputMonitoringTrusted {
                        Button("Request Input Monitoring Access…") {
                            monitor.promptForInputMonitoring()
                        }
                        Button("Open Input Monitoring Settings") {
                            monitor.openInputMonitoringSettings()
                        }
                    }
                } footer: {
                    Text("Needed to intercept the mouse wheel so scroll speed and direction can be applied.")
                }

                if !monitor.allPermissionsGranted {
                    Section {
                        Button("Relaunch VibeRemote") {
                            monitor.relaunchApp()
                        }
                    } footer: {
                        Text("After you enable VibeRemote in System Settings, relaunch so this running copy picks up the new permission. Rebuilds can leave extra VibeRemote entries — turn on the one that is running now.")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Permissions")
        }
    }

    private func permissionRow(title: String, allowed: Bool) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Circle()
                    .fill(allowed ? Palette.good : Palette.bad)
                    .frame(width: 8, height: 8)
                Text(allowed ? "Allowed" : "Not allowed")
            }
        }
    }
}
