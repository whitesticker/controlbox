import SwiftUI

struct PrivacyPane: View {
    @Bindable var monitor: DualSenseMonitor
    @Bindable private var settings = AppSettings.shared

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
                         ? "Control Box can listen to input, inject keyboard, pointer, and scroll events."
                         : "Turn on Accessibility and Input Monitoring. Both need a relaunch after you grant them.")
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

                Section {
                    Toggle("Launch at Login", isOn: launchAtLoginBinding)
                    if monitor.backgroundNeedsApproval {
                        permissionRow(
                            title: "Background",
                            allowed: false
                        )
                        Button("Open Login Items & Background Settings") {
                            monitor.openBackgroundSettings()
                        }
                    }
                } footer: {
                    Text("Starts Control Box when you log in to this Mac. macOS lists this under System Settings → General → Login Items & Extensions. You may also need Allow in the Background.")
                }

                Section {
                    Toggle("Hide Dock icon", isOn: $settings.hideDockIcon)
                } footer: {
                    Text("Control Box stays in the menu bar. Command-Q closes the window and leaves the app running. Quit from the Control Box menu bar icon.")
                }

                Section {
                    permissionRow(
                        title: "System Audio Recording",
                        allowed: monitor.screenCaptureTrusted
                    )
                    if !monitor.screenCaptureTrusted {
                        Button("Request System Audio Recording…") {
                            monitor.promptForScreenCapture()
                        }
                        Button("Open System Audio Recording Settings") {
                            monitor.openScreenCaptureSettings()
                        }
                    }
                } footer: {
                    Text("Needed only for per-app volume on Sound. Control Box does not need Screen Recording. Input mapping does not use this.")
                }

                if monitor.needsRelaunchForPermissions {
                    Section {
                        Button("Relaunch Control Box") {
                            monitor.relaunchApp()
                        }
                    } footer: {
                        Text("After you enable Control Box in System Settings, relaunch so this running copy picks up the new permission. Debug builds are signed with your Apple Development certificate, so later rebuilds keep the same grant. Remove leftover ad-hoc Control Box rows if macOS still shows more than one.")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Permissions")
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { monitor.launchAtLoginOn },
            set: { monitor.setLaunchAtLogin($0) }
        )
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
