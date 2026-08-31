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

    private let orderKey = "com.local.top.rowOrder"
    private let hiddenKey = "com.local.top.hiddenRows"
    private let enabledKey = "com.local.top.menuBarEnabled"

    private init() {
        let defaults = UserDefaults.standard
        menuBarEnabled = defaults.object(forKey: enabledKey) as? Bool ?? false

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

    private func save() {
        UserDefaults.standard.set(rowOrder.map(\.rawValue), forKey: orderKey)
        UserDefaults.standard.set(hiddenRows.map(\.rawValue), forKey: hiddenKey)
        UserDefaults.standard.set(menuBarEnabled, forKey: enabledKey)
    }
}
