import SwiftUI

struct PrivacyPane: View {
    @Bindable var monitor: DualSenseMonitor

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(monitor.allPermissionsGranted ? Palette.good : Palette.bad)
                                .frame(width: 8, height: 8)
                            Text(monitor.allPermissionsGranted ? "All granted" : "Action needed")
                        }
                    } label: {
                        SettingsRowLabel(
                            "Status",
                            monitor.allPermissionsGranted ? nil : "Relaunch after granting."
                        )
                    }
                }

                Section {
                    permissionRow(
                        title: "Accessibility",
                        subtitle: "Devices, Window Management, Display Arrangement, Dock Previews.",
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
                }

                Section {
                    permissionRow(
                        title: "Input Monitoring",
                        subtitle: "Pointer & Scroll wheel speed and Caps Lock.",
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
                }

                Section {
                    Toggle("Launch at Login", isOn: launchAtLoginBinding)
                    if monitor.backgroundNeedsApproval {
                        permissionRow(
                            title: "Background",
                            subtitle: "Turn on Allow in the Background for Control Box.",
                            allowed: false
                        )
                        Button("Open Login Items & Background Settings") {
                            monitor.openBackgroundSettings()
                        }
                    }
                }

                Section {
                    permissionRow(
                        title: "System Audio Recording",
                        subtitle: "Sound per-app volume.",
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
                }

                Section {
                    permissionRow(
                        title: "Screen Recording",
                        subtitle: "Dock Preview thumbnails.",
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
                }

                if monitor.needsRelaunchForPermissions {
                    Section {
                        Button("Relaunch Control Box") {
                            monitor.relaunchApp()
                        }
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

    private func permissionRow(title: String, subtitle: String, allowed: Bool) -> some View {
        LabeledContent {
            HStack(spacing: 8) {
                Circle()
                    .fill(allowed ? Palette.good : Palette.bad)
                    .frame(width: 8, height: 8)
                Text(allowed ? "Allowed" : "Not allowed")
            }
        } label: {
            SettingsRowLabel(title, subtitle)
        }
    }
}
