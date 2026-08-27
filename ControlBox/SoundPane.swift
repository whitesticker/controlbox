import ControlBoxCore
import SwiftUI

struct SoundPane: View {
    @Bindable var catalog: SoundCatalog

    var body: some View {
        NavigationStack {
            Form {
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
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Volume")
                                Spacer()
                                Text("\(Int((catalog.volume * 100).rounded()))%")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Slider(value: volumeBinding, in: 0...1)
                        }
                        Toggle("Mute", isOn: muteBinding)
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
                            Text("On a MacBook, grant System Audio Recording for Control Box. Screen Recording alone mutes the app and plays nothing back.")
                                .foregroundStyle(.secondary)
                            Button("Request Screen & System Audio Recording…") {
                                catalog.requestCaptureAccess()
                            }
                            Button("Open Screen Recording Settings") {
                                catalog.openCaptureSettings()
                            }
                        }
                        if catalog.apps.isEmpty {
                            Text("Play something, then move that app’s slider. It stays in this list after that.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(catalog.apps) { app in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(app.name)
                                        if app.isPlaying {
                                            Text("Playing")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        } else {
                                            Text("Saved")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text("\(Int((app.volume * 100).rounded()))%")
                                            .foregroundStyle(.secondary)
                                            .monospacedDigit()
                                    }
                                    Slider(value: appVolumeBinding(app), in: 0...1)
                                    Toggle("Mute", isOn: appMuteBinding(app))
                                }
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
                    Text("The first slider or mute keeps that app here. The saved level applies again the next time it plays.")
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

    private var muteBinding: Binding<Bool> {
        Binding(
            get: { catalog.isMuted },
            set: { catalog.setMuted($0) }
        )
    }

    private func appVolumeBinding(_ app: AttachedAudioApp) -> Binding<Double> {
        Binding(
            get: { catalog.apps.first { $0.id == app.id }?.volume ?? app.volume },
            set: { catalog.setAppVolume($0, id: app.id) }
        )
    }

    private func appMuteBinding(_ app: AttachedAudioApp) -> Binding<Bool> {
        Binding(
            get: { catalog.apps.first { $0.id == app.id }?.isMuted ?? app.isMuted },
            set: { catalog.setAppMuted($0, id: app.id) }
        )
    }
}
