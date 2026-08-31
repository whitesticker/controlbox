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
                    if monitor.allPermissionsGranted {
                        Text("Accessibility and Input Monitoring are on.")
                    } else {
                        footerBullets(
                            "Accessibility and Input Monitoring are required for most features.",
                            "Relaunch after granting those two."
                        )
                    }
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
                    footerBullets(
                        "Devices: keys, clicks, gestures, and volume.",
                        "Window Management.",
                        "Display Arrangement shortcut.",
                        "Dock Previews: which Dock icon the pointer is on."
                    )
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
                    footerBullets(
                        "Pointer & Scroll: wheel speed and direction.",
                        "Caps Lock as a modifier."
                    )
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
                    footerBullets(
                        "Starts Control Box at login.",
                        "Listed under System Settings → General → Login Items & Extensions.",
                        "You may also need Allow in the Background."
                    )
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
                    footerBullets(
                        "Sound: per-app volume only.",
                        "Not Screen Recording. Devices do not use this."
                    )
                }

                Section {
                    permissionRow(
                        title: "Screen Recording",
                        allowed: monitor.screenRecordingTrusted
                    )
                    if !monitor.screenRecordingTrusted {
                        Button("Request Screen Recording…") {
                            monitor.promptForScreenRecording()
                        }
                        Button("Open Screen Recording Settings") {
                            monitor.openScreenRecordingSettings()
                        }
                    }
                } footer: {
                    footerBullets(
                        "Dock Previews: live thumbnails.",
                        "Titles still work without it.",
                        "Not the System Audio Recording grant used by Sound."
                    )
                }

                if monitor.needsRelaunchForPermissions {
                    Section {
                        Button("Relaunch Control Box") {
                            monitor.relaunchApp()
                        }
                    } footer: {
                        footerBullets(
                            "Relaunch so this copy picks up new grants.",
                            "Debug builds keep the same Apple Development identity.",
                            "Remove leftover ad-hoc Control Box rows if macOS lists more than one."
                        )
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
