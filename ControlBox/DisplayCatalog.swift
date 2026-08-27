import ControlBoxCore
import Foundation
import Observation

@Observable
@MainActor
final class DisplayCatalog {
    var displays: [AttachedDisplay] = []
    var unifiedEnabled = false
    var unifiedBrightness = 1.0

    private var writeWork: [String: DispatchWorkItem] = [:]
    private var mix: [String: Double] = [:]
    private static let defaultsKey = "controlbox.displayBrightness.v1"

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

    func refresh() {
        displays = DisplayBrightness.connectedDisplays()
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
        applyMix()
    }

    func setBrightness(_ value: Double, id: String) {
        setValue(value, id: id, field: "brightness") { DisplayBrightness.setBrightness($0, id: $1) }
    }

    func setContrast(_ value: Double, id: String) {
        setValue(value, id: id, field: "contrast") { DisplayBrightness.setContrast($0, id: $1) }
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
            setBrightness(min(max(unifiedBrightness * ratio, 0), 1), id: display.id)
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
        write: @escaping (Double, String) -> Void
    ) {
        if let index = displays.firstIndex(where: { $0.id == id }) {
            if field == "brightness" {
                displays[index].brightness = value
            } else {
                displays[index].contrast = value
            }
        }
        let token = "\(id):\(field)"
        writeWork[token]?.cancel()
        let work = DispatchWorkItem {
            write(value, id)
        }
        writeWork[token] = work
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    private struct Store: Codable {
        var unifiedEnabled: Bool
    }
}
