import IRemoteControl
import Observation
import SwiftUI

@Observable
@MainActor
final class SoundCatalog {
    var outputs: [AudioOutput] = []
    var selectedOutputID = ""
    var volume: Double = 1
    var isMuted = false
    var apps: [AttachedAudioApp] = []
    var hasCaptureAccess = false
    var mixSupported = AppVolumeMixer.isSupported
    var mixError: String?
    var conflictingMixers: [String] = []
    private var writeWork: [String: DispatchWorkItem] = [:]

    func refresh() {
        let live = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, ($0.volume, $0.isMuted)) })
        outputs = SystemAudio.outputs()
        selectedOutputID = SystemAudio.defaultOutputUID() ?? outputs.first?.id ?? ""
        volume = SystemAudio.volume()
        isMuted = SystemAudio.isMuted()
        hasCaptureAccess = AppVolumeMixer.hasCaptureAccess
        var next = AppVolumeMixer.apps()
        for index in next.indices {
            if let held = live[next[index].id] {
                next[index].volume = held.0
                next[index].isMuted = held.1
            }
        }
        apps = next
        mixError = AppVolumeMixer.lastError()
        conflictingMixers = AppVolumeMixer.conflictingMixerNames()
    }

    func setOutput(_ id: String) {
        selectedOutputID = id
        SystemAudio.setDefaultOutput(uid: id)
        refresh()
    }

    func setVolume(_ value: Double) {
        volume = value
        debounce("system-volume") { SystemAudio.setVolume(value) }
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        SystemAudio.setMuted(muted)
    }

    func setAppVolume(_ value: Double, id: String) {
        if let index = apps.firstIndex(where: { $0.id == id }) {
            apps[index].volume = value
        }
        AppVolumeMixer.setVolume(value, id: id)
        mixError = AppVolumeMixer.lastError()
    }

    func setAppMuted(_ muted: Bool, id: String) {
        if let index = apps.firstIndex(where: { $0.id == id }) {
            apps[index].isMuted = muted
        }
        AppVolumeMixer.setMuted(muted, id: id)
        mixError = AppVolumeMixer.lastError()
    }

    func requestCaptureAccess() {
        _ = AppVolumeMixer.requestCaptureAccess()
        refresh()
    }

    func openCaptureSettings() {
        AppVolumeMixer.openCaptureSettings()
    }

    private func debounce(_ token: String, write: @escaping () -> Void) {
        writeWork[token]?.cancel()
        let work = DispatchWorkItem(block: write)
        writeWork[token] = work
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.05, execute: work)
    }
}
