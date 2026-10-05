import AppKit
import ControlBoxCore
import Foundation
import Observation

@Observable
@MainActor
final class DisplayCatalog {
    var displays: [AttachedDisplay] = []
    var unifiedEnabled = false
    var unifiedBrightness = 1.0
    /// Bumped when engine settings change so settings rows re-read `prefs`.
    var settingsRevision = 0

    @ObservationIgnored let engine = DisplayEngine()
    private var mix: [String: Double] = [:]
    private var lastUserWrite = Date.distantPast
    private static let defaultsKey = "controlbox.displayBrightness.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let store = try? JSONDecoder().decode(Store.self, from: data) {
            unifiedEnabled = store.unifiedEnabled
        }
        engine.onDisplaysChanged = { [weak self] in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    func start() {
        engine.start()
    }

    var adjustableDisplays: [AttachedDisplay] {
        displays.filter(\.canAdjustBrightness)
    }

    var canUnify: Bool { adjustableDisplays.count >= 2 }

    func refresh(readHardware: Bool = true) {
        reload()
    }

    /// Re-runs the engine's display setup after a settings change that needs it.
    func reconfigure() {
        engine.configure()
        settingsRevision += 1
    }

    func noteSettingsChanged() {
        settingsRevision += 1
        reload()
    }

    func engineDisplay(id: String) -> Display? {
        DisplayManager.shared.displays.first { $0.prefsId == id }
    }

    func setUnifiedEnabled(_ on: Bool) {
        guard on == false || canUnify else { return }
        unifiedEnabled = on
        if on {
            captureMix()
        } else {
            mix = [:]
        }
        persist()
    }

    func setUnifiedBrightness(_ value: Double) {
        unifiedBrightness = min(max(value, 0), 1)
        lastUserWrite = Date()
        applyMix()
    }

    enum BrightnessOrigin {
        case user
        case nightShift
    }

    var onUserBrightnessChange: ((String, Double) -> Void)?
    var onDisplaysChanged: (() -> Void)?

    func setBrightness(_ value: Double, id: String, origin: BrightnessOrigin = .user) {
        setValue(value, id: id, command: .brightness, origin: origin)
    }

    func setContrast(_ value: Double, id: String) {
        setValue(value, id: id, command: .contrast, origin: .user)
    }

    func setVolume(_ value: Double, id: String) {
        setValue(value, id: id, command: .audioSpeakerVolume, origin: .user)
    }

    private func reload() {
        let list = DisplayManager.shared.displays.filter { !$0.isDummy }.map(Self.attached)
        for display in DisplayManager.shared.displays {
            let id = display.prefsId
            for command in [Command.brightness, .contrast, .audioSpeakerVolume] {
                display.sliderHandler[command] = SliderHandler { [weak self] value, _ in
                    MainActor.assumeIsolated {
                        self?.engineValueChanged(id: id, command: command, value: Double(value))
                    }
                }
            }
        }
        applyFetched(list)
    }

    private static func attached(_ display: Display) -> AttachedDisplay {
        let friendly = display.readPrefAsString(key: .friendlyName)
        let name = friendly.isEmpty ? display.name : friendly
        let enabled = !display.readPrefAsBool(key: .isDisabled)
        if let apple = display as? AppleDisplay {
            return AttachedDisplay(
                id: display.prefsId,
                name: name,
                detail: apple.isBuiltIn() ? "Built-in Display" : "Apple Display",
                brightness: Double(apple.getBrightness()),
                canAdjustBrightness: enabled,
                isBuiltIn: apple.isBuiltIn()
            )
        }
        guard let other = display as? OtherDisplay else {
            return AttachedDisplay(
                id: display.prefsId,
                name: name,
                detail: "No Control",
                brightness: 1,
                canAdjustBrightness: false,
                isBuiltIn: display.isBuiltIn()
            )
        }
        let hardware = !other.isSw()
        let detail: String
        if other.isSwOnly() {
            detail = "No Control"
        } else if other.isSw() {
            detail = "Hardware (DDC) disabled"
        } else {
            detail = "Hardware (DDC)"
        }
        return AttachedDisplay(
            id: display.prefsId,
            name: name,
            detail: detail,
            brightness: Double(other.getBrightness()),
            contrast: Double(other.readPrefAsFloat(for: .contrast)),
            volume: Double(other.setupSliderCurrentValue(command: .audioSpeakerVolume)),
            canAdjustBrightness: enabled && hardware && !other.readPrefAsBool(key: .unavailableDDC, for: .brightness),
            canAdjustContrast: enabled && hardware && !other.readPrefAsBool(key: .unavailableDDC, for: .contrast),
            canAdjustVolume: enabled && hardware && !other.readPrefAsBool(key: .unavailableDDC, for: .audioSpeakerVolume),
            isBuiltIn: false
        )
    }

    private func engineValueChanged(id: String, command: Command, value: Double) {
        guard let index = displays.firstIndex(where: { $0.id == id }) else { return }
        switch command {
        case .brightness: displays[index].brightness = value
        case .contrast: displays[index].contrast = value
        case .audioSpeakerVolume: displays[index].volume = value
        default: break
        }
    }

    private func applyFetched(_ next: [AttachedDisplay]) {
        var next = next
        if Date().timeIntervalSince(lastUserWrite) < 2 {
            let live = Dictionary(uniqueKeysWithValues: displays.map { ($0.id, ($0.brightness, $0.contrast)) })
            for index in next.indices {
                if let held = live[next[index].id] {
                    next[index].brightness = held.0
                    next[index].contrast = held.1
                }
            }
        }
        displays = next
        if unifiedEnabled, canUnify {
            if mix.isEmpty {
                captureMix()
            } else {
                syncMixAfterRefresh()
            }
        } else if unifiedEnabled, !canUnify {
            unifiedEnabled = false
            mix = [:]
            persist()
        }
        onDisplaysChanged?()
    }

    private func captureMix() {
        let adjustable = adjustableDisplays
        let peak = adjustable.map(\.brightness).max() ?? 0
        unifiedBrightness = peak
        if peak < 0.001 {
            mix = Dictionary(uniqueKeysWithValues: adjustable.map { ($0.id, 1.0) })
        } else {
            mix = Dictionary(uniqueKeysWithValues: adjustable.map { ($0.id, $0.brightness / peak) })
        }
    }

    private func syncMixAfterRefresh() {
        let adjustable = adjustableDisplays
        guard !adjustable.isEmpty else { return }
        var next: [String: Double] = [:]
        for display in adjustable {
            if let ratio = mix[display.id] {
                next[display.id] = ratio
            } else if unifiedBrightness > 0.001 {
                next[display.id] = min(max(display.brightness / unifiedBrightness, 0), 1)
            } else {
                next[display.id] = 1
            }
        }
        mix = next
        applyMix()
    }

    private func applyMix() {
        for display in adjustableDisplays {
            let ratio = mix[display.id] ?? 1
            setValue(
                min(max(unifiedBrightness * ratio, 0), 1),
                id: display.id,
                command: .brightness,
                origin: .user
            )
        }
    }

    private func persist() {
        let store = Store(unifiedEnabled: unifiedEnabled)
        if let data = try? JSONEncoder().encode(store) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    private func setValue(
        _ value: Double,
        id: String,
        command: Command,
        origin: BrightnessOrigin
    ) {
        lastUserWrite = Date()
        if origin == .user, command == .brightness {
            onUserBrightnessChange?(id, value)
        }
        engineValueChanged(id: id, command: command, value: value)
        guard app != nil, engine.sleepID == 0, engine.reconfigureID == 0, let display = engineDisplay(id: id) else { return }
        let value = Float(value)
        if command == .brightness, let appleDisplay = display as? AppleDisplay {
            _ = appleDisplay.setBrightness(value)
        } else if let otherDisplay = display as? OtherDisplay {
            Self.valueChangedOtherDisplay(otherDisplay: otherDisplay, command: command, value: value)
        }
    }

    private static func valueChangedOtherDisplay(otherDisplay: OtherDisplay, command: Command, value: Float) {
        // For the speaker volume slider, also set/unset the mute command when the value is changed from/to 0
        if command == .audioSpeakerVolume, (otherDisplay.readPrefAsInt(for: .audioMuteScreenBlank) == 1 && value > 0) || (otherDisplay.readPrefAsInt(for: .audioMuteScreenBlank) != 1 && value == 0) {
            otherDisplay.toggleMute(fromVolumeSlider: true)
        }
        if command == Command.brightness {
            _ = otherDisplay.setBrightness(value)
            return
        } else if !otherDisplay.isSw() {
            if command == Command.audioSpeakerVolume {
                if !otherDisplay.readPrefAsBool(key: .enableMuteUnmute) || value != 0 {
                    otherDisplay.writeDDCValues(command: command, value: otherDisplay.convValueToDDC(for: command, from: value))
                }
            } else {
                otherDisplay.writeDDCValues(command: command, value: otherDisplay.convValueToDDC(for: command, from: value))
            }
            otherDisplay.savePref(value, for: command)
        }
    }

    private struct Store: Codable {
        var unifiedEnabled: Bool
    }
}
