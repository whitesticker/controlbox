import Combine
import Foundation

// MARK: - Row identity

/// The set of reorderable/hideable metric rows in the main menu. Date/Time
/// isn't included -- it's a fixed header, not a "metric" to reorder.
enum MetricRow: String, CaseIterable, Codable, Identifiable {
    case cpu, gpu, memory, network, disk, sensors, battery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .memory: return "Memory"
        case .network: return "Network"
        case .disk: return "Disk"
        case .sensors: return "Sensors"
        case .battery: return "Battery"
        }
    }

    var systemImage: String {
        switch self {
        case .cpu: return "cpu"
        case .gpu: return "cube.transparent"
        case .memory: return "memorychip"
        case .network: return "network"
        case .disk: return "internaldrive"
        case .sensors: return "thermometer.medium"
        case .battery: return "battery.100"
        }
    }
}

// MARK: - Persisted preferences

/// User-configurable row order/visibility for the main menu, persisted in
/// UserDefaults. `StatusItemController` builds every row's NSMenuItem once
/// (same reused-forever policy as everything else in that class) and just
/// re-inserts those existing items into the menu in this order whenever it
/// changes -- no view recreation, so no risk of the SwiftUI-in-NSMenuItem
/// memory leak that comes from rebuilding hosting views repeatedly.
final class PreferencesStore: ObservableObject {
    static let shared = PreferencesStore()

    @Published var rowOrder: [MetricRow] {
        didSet { save() }
    }
    @Published var hiddenRows: Set<MetricRow> {
        didSet { save() }
    }
    /// Separate from Control Box's gamecontroller menu extra. Off until the
    /// System Monitor pane turns it on, so we don't add a second icon by surprise.
    @Published var menuBarEnabled: Bool {
        didSet { save() }
    }
    /// Bundle IDs for the quick-launch row at the bottom of the menu, in
    /// order, at most `maxLauncherApps`. Empty hides the row.
    @Published private(set) var launcherApps: [String] {
        didSet { save() }
    }
    /// What the menu bar extra shows, left to right (pane → Menu Bar Icon).
    /// Empty shows a plain gauge icon.
    @Published private(set) var menuBarItems: [MenuBarItem] {
        didSet { save() }
    }

    // History submenu (System Monitor → History). The range is also the
    // 5m / 1h / 24h control inside the menu, so the last pick sticks.
    @Published var historyStyle: HistoryStyle {
        didSet { save() }
    }
    @Published var historyRange: HistoryRange {
        didSet { save() }
    }
    @Published var historyReadout: HistoryReadout {
        didSet { save() }
    }
    @Published var historyCompressSpikes: Bool {
        didSet { save() }
    }
    @Published var historyShowStats: Bool {
        didSet { save() }
    }
    @Published private(set) var historyBarSeconds: [HistoryRange: TimeInterval] {
        didSet { save() }
    }
    /// Layout from the hidden Design lab; not a user setting.
    @Published var historyDesign: HistoryDesign {
        didSet { save() }
    }

    static let maxLauncherApps = 8
    static let defaultLauncherApps = [
        Bundle.main.bundleIdentifier ?? "com.whitesticker.controlbox",
        "com.apple.ActivityMonitor",
        "com.apple.SystemProfiler",
        "com.apple.Terminal",
        "com.apple.Console",
    ]

    private let orderKey = "com.local.top.rowOrder"
    private let hiddenKey = "com.local.top.hiddenRows"
    private let enabledKey = "com.local.top.menuBarEnabled"
    private let launcherKey = "com.local.top.launcherApps"
    private let menuBarItemsKey = "com.local.top.menuBarItems"
    private let historyStyleKey = "com.local.top.history.style"
    private let historyRangeKey = "com.local.top.history.range"
    private let historyReadoutKey = "com.local.top.history.readout"
    private let historyCompressKey = "com.local.top.history.compressSpikes"
    private let historyStatsKey = "com.local.top.history.showStats"
    private let historyBarsKey = "com.local.top.history.barSeconds"
    private static let historyDesignKey = "com.local.top.history.design"

    private init() {
        let defaults = UserDefaults.standard
        menuBarEnabled = defaults.object(forKey: enabledKey) as? Bool ?? false
        launcherApps = Array(
            (defaults.stringArray(forKey: launcherKey) ?? Self.defaultLauncherApps).prefix(Self.maxLauncherApps)
        )
        menuBarItems = defaults.stringArray(forKey: menuBarItemsKey).map { saved in
            var seen: Set<MenuBarItem> = []
            return saved.compactMap(MenuBarItem.init(rawValue:)).filter { seen.insert($0).inserted }
        } ?? MenuBarItem.defaultShown

        historyStyle = defaults.string(forKey: historyStyleKey).flatMap(HistoryStyle.init(rawValue:)) ?? .candles
        historyRange = defaults.string(forKey: historyRangeKey).flatMap(HistoryRange.init(rawValue:)) ?? .oneHour
        historyReadout = defaults.string(forKey: historyReadoutKey).flatMap(HistoryReadout.init(rawValue:)) ?? .both
        historyCompressSpikes = defaults.object(forKey: historyCompressKey) as? Bool ?? true
        historyShowStats = defaults.object(forKey: historyStatsKey) as? Bool ?? true
        let savedBars = defaults.dictionary(forKey: historyBarsKey) as? [String: Double] ?? [:]
        historyBarSeconds = Dictionary(uniqueKeysWithValues: HistoryRange.allCases.map { range in
            let saved = savedBars[range.rawValue].flatMap { range.barChoices.contains($0) ? $0 : nil }
            return (range, saved ?? range.defaultBarSeconds)
        })
        historyDesign = Self.loadHistoryDesign()

        if let saved = defaults.stringArray(forKey: orderKey) {
            let parsed = saved.compactMap { MetricRow(rawValue: $0) }
            // Any case not present in saved data (e.g. a metric added in a
            // later app version) gets appended at the end rather than lost.
            let missing = MetricRow.allCases.filter { !parsed.contains($0) }
            rowOrder = parsed + missing
        } else {
            rowOrder = MetricRow.allCases
        }

        if let saved = defaults.stringArray(forKey: hiddenKey) {
            hiddenRows = Set(saved.compactMap { MetricRow(rawValue: $0) })
        } else {
            hiddenRows = []
        }
    }

    var visibleRowsInOrder: [MetricRow] {
        rowOrder.filter { !hiddenRows.contains($0) }
    }

    func isHidden(_ row: MetricRow) -> Bool {
        hiddenRows.contains(row)
    }

    func setHidden(_ hidden: Bool, for row: MetricRow) {
        if hidden {
            hiddenRows.insert(row)
        } else {
            hiddenRows.remove(row)
        }
    }

    func move(fromOffsets: IndexSet, toOffset: Int) {
        rowOrder.move(fromOffsets: fromOffsets, toOffset: toOffset)
    }

    var canAddLauncherApp: Bool {
        launcherApps.count < Self.maxLauncherApps
    }

    func addLauncherApp(_ bundleID: String) {
        guard canAddLauncherApp, !launcherApps.contains(bundleID) else { return }
        launcherApps.append(bundleID)
    }

    func removeLauncherApp(_ bundleID: String) {
        launcherApps.removeAll { $0 == bundleID }
    }

    func moveLauncherApps(fromOffsets: IndexSet, toOffset: Int) {
        launcherApps.move(fromOffsets: fromOffsets, toOffset: toOffset)
    }

    func resetLauncherApps() {
        launcherApps = Self.defaultLauncherApps
    }

    /// Puts `item` in the menu bar at `index` (moving it if already there).
    func showMenuBarItem(_ item: MenuBarItem, at index: Int? = nil) {
        var items = menuBarItems
        if let from = items.firstIndex(of: item) {
            items.remove(at: from)
        }
        items.insert(item, at: min(index ?? items.count, items.count))
        if items != menuBarItems { menuBarItems = items }
    }

    func hideMenuBarItem(_ item: MenuBarItem) {
        menuBarItems.removeAll { $0 == item }
    }

    func resetMenuBarItems() {
        menuBarItems = MenuBarItem.defaultShown
    }

    func historyBarSeconds(for range: HistoryRange) -> TimeInterval {
        historyBarSeconds[range] ?? range.defaultBarSeconds
    }

    func setHistoryBarSeconds(_ seconds: TimeInterval, for range: HistoryRange) {
        historyBarSeconds[range] = seconds
    }

    var historySettings: HistorySettings {
        HistorySettings(
            style: historyStyle,
            readout: historyReadout,
            compressSpikes: historyCompressSpikes,
            showStats: historyShowStats,
            barSeconds: historyBarSeconds(for: historyRange)
        )
    }

    var historyIsDefault: Bool {
        historyStyle == .candles && historyRange == .oneHour && historyReadout == .both
            && historyCompressSpikes && historyShowStats
            && HistoryRange.allCases.allSatisfy { historyBarSeconds(for: $0) == $0.defaultBarSeconds }
    }

    func resetHistory() {
        historyStyle = .candles
        historyRange = .oneHour
        historyReadout = .both
        historyCompressSpikes = true
        historyShowStats = true
        historyBarSeconds = Dictionary(uniqueKeysWithValues: HistoryRange.allCases.map { ($0, $0.defaultBarSeconds) })
    }

    /// Saved keys over the tuned values, so a value added later keeps the
    /// rest of a saved design instead of discarding it.
    private static func loadHistoryDesign() -> HistoryDesign {
        guard let saved = UserDefaults.standard.data(forKey: historyDesignKey),
              let savedKeys = try? JSONSerialization.jsonObject(with: saved) as? [String: Any],
              let tuned = try? JSONEncoder().encode(HistoryDesign.tuned),
              var merged = try? JSONSerialization.jsonObject(with: tuned) as? [String: Any]
        else { return .tuned }
        merged.merge(savedKeys) { _, new in new }
        guard let data = try? JSONSerialization.data(withJSONObject: merged),
              let design = try? JSONDecoder().decode(HistoryDesign.self, from: data)
        else { return .tuned }
        return design
    }

    private func save() {
        let defaults = UserDefaults.standard
        if let design = try? JSONEncoder().encode(historyDesign) {
            defaults.set(design, forKey: Self.historyDesignKey)
        }
        defaults.set(rowOrder.map(\.rawValue), forKey: orderKey)
        defaults.set(hiddenRows.map(\.rawValue), forKey: hiddenKey)
        defaults.set(menuBarEnabled, forKey: enabledKey)
        defaults.set(launcherApps, forKey: launcherKey)
        defaults.set(menuBarItems.map(\.rawValue), forKey: menuBarItemsKey)
        defaults.set(historyStyle.rawValue, forKey: historyStyleKey)
        defaults.set(historyRange.rawValue, forKey: historyRangeKey)
        defaults.set(historyReadout.rawValue, forKey: historyReadoutKey)
        defaults.set(historyCompressSpikes, forKey: historyCompressKey)
        defaults.set(historyShowStats, forKey: historyStatsKey)
        defaults.set(
            Dictionary(uniqueKeysWithValues: historyBarSeconds.map { ($0.key.rawValue, $0.value) }),
            forKey: historyBarsKey
        )
    }
}
