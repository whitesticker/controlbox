import ControlBoxCore
import SwiftUI

struct SoundPane: View {
    @Bindable var catalog: SoundCatalog
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Show in menu bar", isOn: $settings.soundMenuBarEnabled)
                } footer: {
                    footerBullets(
                        "Separate extra. The Control Box icon stays.",
                        "Click for output and per-app volume.",
                        "Hide from Menu Bar turns this extra off; it does not quit Control Box."
                    )
                }

                Section {
                    if catalog.outputs.isEmpty {
                        Text("No output devices.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Output", selection: outputBinding) {
                            ForEach(catalog.outputs) { output in
                                Text(output.name).tag(output.id)
                            }
                        }
                        SettingsSlider("Volume", value: volumeBinding)
                    }
                } header: {
                    Text("Output")
                }

                Section {
                    if !catalog.mixSupported {
                        Text("Per-app volume needs macOS 14.2 or later.")
                            .foregroundStyle(.secondary)
                    } else {
                        if !catalog.conflictingMixers.isEmpty {
                            Text("Quit \(catalog.conflictingMixers.joined(separator: ", ")) first. Only one app can tap a process at a time, so these sliders do nothing while that mixer is open.")
                                .foregroundStyle(.secondary)
                        }
                        if !catalog.hasCaptureAccess {
                            Text("Grant System Audio Recording for Control Box. Screen Recording is not required.")
                                .foregroundStyle(.secondary)
                            Button("Request System Audio Recording…") {
                                catalog.requestCaptureAccess()
                            }
                            Button("Open System Audio Recording Settings") {
                                catalog.openCaptureSettings()
                            }
                        }
                        if catalog.apps.isEmpty {
                            Text("Play something, then move that app’s slider. It stays in this list after that.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(catalog.apps) { app in
                                SettingsSlider(
                                    app.name,
                                    description: appStatus(app),
                                    value: appVolumeBinding(app)
                                )
                            }
                        }
                        if let mixError = catalog.mixError {
                            Text(mixError)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Apps")
                } footer: {
                    footerBullets(
                        "Moving a slider keeps that app here.",
                        "The saved level applies the next time it plays."
                    )
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Sound")
            .onAppear { catalog.refresh() }
            .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in
                catalog.refresh()
            }
        }
    }

    private func appStatus(_ app: AttachedAudioApp) -> String {
        if app.isMuted { return "Muted" }
        return app.isPlaying ? "Playing" : "Saved"
    }

    private var outputBinding: Binding<String> {
        Binding(
            get: { catalog.selectedOutputID },
            set: { catalog.setOutput($0) }
        )
    }

    private var volumeBinding: Binding<Double> {
        Binding(
            get: { catalog.volume },
            set: { catalog.setVolume($0) }
        )
    }

    private func appVolumeBinding(_ app: AttachedAudioApp) -> Binding<Double> {
        Binding(
            get: { catalog.apps.first { $0.id == app.id }?.volume ?? app.volume },
            set: { catalog.setAppVolume($0, id: app.id) }
        )
    }
}
