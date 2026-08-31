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

    private var mix: [String: Double] = [:]
    private var lastScreenSignature = ""
    private var lastUserWrite = Date.distantPast
    private var fetching = false
    private static let defaultsKey = "controlbox.displayBrightness.v1"
    private static let ddcQueue = DispatchQueue(label: "controlbox.display-ddc", qos: .userInteractive)
    private static let ddcLock = NSLock()
    private static var pendingDDC: [String: (value: Double, id: String, field: String)] = [:]
    private static var inflightDDC: Set<String> = []

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let store = try? JSONDecoder().decode(Store.self, from: data) {
            unifiedEnabled = store.unifiedEnabled
        }
    }

    var adjustableDisplays: [AttachedDisplay] {
        displays.filter(\.canAdjustBrightness)
    }

    var canUnify: Bool { adjustableDisplays.count >= 2 }

    func refresh(readHardware: Bool = true) {
        let signature = Self.screenSignature()
        if !readHardware, signature == lastScreenSignature, !displays.isEmpty {
            return
        }
        guard !fetching else { return }
        fetching = true
        let screens = DisplayBrightness.snapshotScreens()
        Task.detached(priority: .userInitiated) {
            let list = DisplayBrightness.connectedDisplays(screens: screens, readHardware: true)
            await MainActor.run {
                self.fetching = false
                self.lastScreenSignature = Self.screenSignature()
                self.applyFetched(list)
            }
        }
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
        setValue(value, id: id, field: "brightness", origin: origin)
    }

    func setContrast(_ value: Double, id: String) {
        setValue(value, id: id, field: "contrast", origin: .user)
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
                field: "brightness",
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
        field: String,
        origin: BrightnessOrigin
    ) {
        lastUserWrite = Date()
        if origin == .user, field == "brightness" {
            onUserBrightnessChange?(id, value)
        }
        if let index = displays.firstIndex(where: { $0.id == id }) {
            if field == "brightness" {
                displays[index].brightness = value
            } else {
                displays[index].contrast = value
            }
        }
        if id.hasPrefix("cg:") {
            if field == "brightness" {
                DisplayBrightness.setBrightness(value, id: id)
            } else {
                DisplayBrightness.setContrast(value, id: id)
            }
            return
        }
        let token = "\(id):\(field)"
        Self.ddcLock.lock()
        Self.pendingDDC[token] = (value, id, field)
        Self.ddcLock.unlock()
        Self.pumpDDC(token)
    }

    private static func pumpDDC(_ token: String) {
        ddcQueue.async {
            ddcLock.lock()
            guard !inflightDDC.contains(token),
                  let pending = pendingDDC.removeValue(forKey: token) else {
                ddcLock.unlock()
                return
            }
            inflightDDC.insert(token)
            ddcLock.unlock()

            if pending.field == "brightness" {
                DisplayBrightness.setBrightness(pending.value, id: pending.id)
            } else {
                DisplayBrightness.setContrast(pending.value, id: pending.id)
            }

            ddcLock.lock()
            inflightDDC.remove(token)
            let again = pendingDDC[token] != nil
            ddcLock.unlock()
            if again {
                pumpDDC(token)
            }
        }
    }

    private static func screenSignature() -> String {
        NSScreen.screens.compactMap { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue
        }
        .sorted()
        .joined(separator: ",")
    }

    private struct Store: Codable {
        var unifiedEnabled: Bool
    }
}
