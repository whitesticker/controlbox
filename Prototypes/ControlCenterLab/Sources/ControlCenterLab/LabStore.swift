import AppKit
import SwiftUI

enum LabAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum CanvasTab: String, CaseIterable, Identifiable {
    case panel, pane
    var id: String { rawValue }
    var title: String { self == .panel ? "Control Center" : "Settings pane" }
}

/// Shared by the window canvas and the real menu bar extras, so both always
/// draw the same design and the same mock state.
final class LabStore: ObservableObject {
    @Published var design: CCDesign { didSet { save(design, Self.designKey) } }
    @Published var appearance = LabAppearance.system
    @Published var canvasTab = CanvasTab.panel

    // User layout (the Control Center pane).
    @Published var order: [ModuleKind] { didSet { UserDefaults.standard.set(order.map(\.rawValue), forKey: Self.orderKey) } }
    @Published var extras: Set<ModuleKind> { didSet { UserDefaults.standard.set(extras.map(\.rawValue), forKey: Self.extrasKey) } }

    // Mock state.
    @Published var displays: [MockDisplay] = [
        MockDisplay(id: "builtin", name: "Built-in Retina Display", brightness: 0.72, canAdjust: true),
        MockDisplay(id: "studio", name: "Studio Display", brightness: 0.55, canAdjust: true),
        MockDisplay(id: "dell", name: "DELL U2723QE", brightness: 0.40, canAdjust: true),
    ]
    @Published var linkedDisplays = false
    @Published var linkedBrightness = 0.7
    @Published var outputs: [MockOutput] = [
        MockOutput(id: "speakers", name: "MacBook Pro Speakers", symbol: "laptopcomputer"),
        MockOutput(id: "studio", name: "Studio Display Speakers", symbol: "display"),
        MockOutput(id: "airpods", name: "AirPods Pro", symbol: "airpods.pro"),
    ]
    @Published var selectedOutput = "studio"
    @Published var volume = 0.45
    @Published var apps: [MockApp] = [
        MockApp(id: "com.apple.Music", name: "Music", volume: 0.8, playing: true, muted: false),
        MockApp(id: "com.apple.Safari", name: "Safari", volume: 0.6, playing: true, muted: false),
        MockApp(id: "com.apple.FaceTime", name: "FaceTime", volume: 0.3, playing: false, muted: true),
    ]
    @Published var audioAccess = true
    @Published var appsPlaying = true
    @Published var caffeinateActive = false
    @Published var caffeinateDuration = CaffeinateDuration.oneHour
    @Published var caffeinateEnd: Date?
    @Published var nightShift = true
    @Published var nightShiftKelvin = 3400.0
    @Published var presets: [MockPreset] = [
        MockPreset(id: "desk", name: "Desk", screens: [
            CGRect(x: 0.05, y: 0.15, width: 0.42, height: 0.5),
            CGRect(x: 0.5, y: 0.1, width: 0.45, height: 0.6),
            CGRect(x: 0.32, y: 0.68, width: 0.28, height: 0.22),
        ]),
        MockPreset(id: "stacked", name: "Stacked", screens: [
            CGRect(x: 0.25, y: 0.05, width: 0.5, height: 0.42),
            CGRect(x: 0.2, y: 0.5, width: 0.6, height: 0.45),
        ]),
        MockPreset(id: "presenting", name: "Presenting", screens: [
            CGRect(x: 0.08, y: 0.3, width: 0.36, height: 0.4),
            CGRect(x: 0.5, y: 0.2, width: 0.44, height: 0.55),
        ]),
    ]
    @Published var currentPreset: String? = "desk"
    @Published var presetsMatch = true
    @Published var toast: String?

    private static let designKey = "ccLab.design"
    private static let orderKey = "ccLab.order"
    private static let extrasKey = "ccLab.extras"
    private var toastWork: DispatchWorkItem?

    init() {
        design = Self.loadDesign()
        let savedOrder = UserDefaults.standard.stringArray(forKey: Self.orderKey)?.compactMap(ModuleKind.init(rawValue:))
        order = savedOrder ?? [.caffeinate, .nightShift, .sleepNow, .arrangement, .display, .sound]
        let savedExtras = UserDefaults.standard.stringArray(forKey: Self.extrasKey)?.compactMap(ModuleKind.init(rawValue:))
        extras = Set(savedExtras ?? [])
    }

    var available: [ModuleKind] {
        ModuleKind.allCases.filter { !order.contains($0) }
    }

    // MARK: Layout editing

    func hide(_ kind: ModuleKind) {
        order.removeAll { $0 == kind }
    }

    func show(_ kind: ModuleKind) {
        guard !order.contains(kind) else { return }
        order.append(kind)
    }

    func resetLayout() {
        order = [.caffeinate, .nightShift, .sleepNow, .arrangement, .display, .sound]
        extras = []
    }

    func resetDesign() {
        design = .defaults
    }

    // MARK: Caffeinate

    func startCaffeinate(_ duration: CaffeinateDuration) {
        caffeinateDuration = duration
        caffeinateActive = true
        caffeinateEnd = duration == .forever ? nil : Date().addingTimeInterval(TimeInterval(duration.rawValue))
    }

    func stopCaffeinate() {
        caffeinateActive = false
        caffeinateEnd = nil
    }

    /// Module body click: start with the last-used duration, or stop.
    func toggleCaffeinate() {
        caffeinateActive ? stopCaffeinate() : startCaffeinate(caffeinateDuration)
    }

    func caffeinateStatus(now: Date) -> String {
        guard caffeinateActive else { return "Off" }
        guard let caffeinateEnd else { return "Staying awake" }
        let remaining = caffeinateEnd.timeIntervalSince(now)
        if remaining <= 0 { return "Off" }
        return "\(CaffeinateDuration.countdownText(remaining: remaining)) left"
    }

    func sleepNow() {
        stopCaffeinate()
        flash("Would stop Caffeinate and sleep the Mac")
    }

    // MARK: Display

    var masterBrightness: Binding<Double> {
        Binding(
            get: { [unowned self] in
                if linkedDisplays { return linkedBrightness }
                switch design.displayScope {
                case .main: return displays.first?.brightness ?? 0
                case .all: return displays.map(\.brightness).max() ?? 0
                }
            },
            set: { [unowned self] value in
                if linkedDisplays {
                    linkedBrightness = value
                    return
                }
                switch design.displayScope {
                case .main:
                    if !displays.isEmpty { displays[0].brightness = value }
                case .all:
                    let top = displays.map(\.brightness).max() ?? 0
                    for index in displays.indices {
                        displays[index].brightness = top > 0.001 ? min(1, displays[index].brightness * value / top) : value
                    }
                }
            }
        )
    }

    func brightness(_ id: String) -> Binding<Double> {
        Binding(
            get: { [unowned self] in displays.first { $0.id == id }?.brightness ?? 0 },
            set: { [unowned self] value in
                if let index = displays.firstIndex(where: { $0.id == id }) { displays[index].brightness = value }
            }
        )
    }

    // MARK: Sound

    func appVolume(_ id: String) -> Binding<Double> {
        Binding(
            get: { [unowned self] in apps.first { $0.id == id }?.volume ?? 0 },
            set: { [unowned self] value in
                if let index = apps.firstIndex(where: { $0.id == id }) { apps[index].volume = value }
            }
        )
    }

    func toggleAppMute(_ id: String) {
        if let index = apps.firstIndex(where: { $0.id == id }) { apps[index].muted.toggle() }
    }

    // MARK: Misc

    func openPane(_ title: String) {
        flash("Would open \(title) in Control Box")
    }

    func flash(_ text: String) {
        toastWork?.cancel()
        toast = text
        let work = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
    }

    func copyDesignJSON() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(design), let json = String(data: data, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(json, forType: .string)
        flash("Design JSON copied")
    }

    /// Overlays the saved keys on the defaults, so adding a knob keeps every
    /// value already tuned instead of dropping the whole saved design.
    private static func loadDesign() -> CCDesign {
        guard let saved = UserDefaults.standard.data(forKey: designKey),
              let savedKeys = try? JSONSerialization.jsonObject(with: saved) as? [String: Any],
              let defaults = try? JSONEncoder().encode(CCDesign.defaults),
              var merged = try? JSONSerialization.jsonObject(with: defaults) as? [String: Any]
        else { return .defaults }
        merged.merge(savedKeys) { _, new in new }
        guard let data = try? JSONSerialization.data(withJSONObject: merged),
              let design = try? JSONDecoder().decode(CCDesign.self, from: data)
        else { return .defaults }
        return design
    }

    private func save(_ design: CCDesign, _ key: String) {
        if let data = try? JSONEncoder().encode(design) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
