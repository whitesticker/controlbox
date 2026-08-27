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
                         ? "Control Box can listen to input, inject keyboard, pointer, and scroll events, and stay allowed in the background."
                         : "Turn on Accessibility, Input Monitoring, and Allow in the Background. Accessibility and Input Monitoring need a relaunch after you grant them.")
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
                    permissionRow(
                        title: "Background",
                        allowed: monitor.backgroundAllowed
                    )
                    if !monitor.backgroundAllowed {
                        Button("Request Background Access…") {
                            monitor.promptForBackgroundActivity()
                        }
                        Button("Open Login Items & Background Settings") {
                            monitor.openBackgroundSettings()
                        }
                    }
                } footer: {
                    Text("Needed so Control Box can keep mapping devices after you close the window, and can start again after login. macOS lists this under System Settings → General → Login Items & Extensions → Allow in the Background.")
                }

                Section {
                    permissionRow(
                        title: "Screen & System Audio Recording",
                        allowed: monitor.screenCaptureTrusted
                    )
                    if !monitor.screenCaptureTrusted {
                        Button("Request Screen & System Audio Recording…") {
                            monitor.promptForScreenCapture()
                        }
                        Button("Open Screen Recording Settings") {
                            monitor.openScreenCaptureSettings()
                        }
                    }
                } footer: {
                    Text("Needed only for per-app volume on Sound. On macOS 15, Control Box needs System Audio Recording — Screen Recording by itself leaves sliders silent. Input mapping does not use this.")
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
