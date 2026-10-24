import AppKit
import ControlBoxCore
import Observation
import SwiftUI

/// One control in the Control Center panel.
enum ControlCenterModule: String, CaseIterable, Identifiable, Codable {
    case caffeinate, arrangement, nightShift, sleepNow, display, sound

    enum Size {
        case small, large, slider
    }

    static let defaultOrder: [ControlCenterModule] = [.caffeinate, .sleepNow, .arrangement, .nightShift, .display, .sound]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .caffeinate: "Caffeinate"
        case .arrangement: "Arrangement"
        case .nightShift: "Night Shift"
        case .sleepNow: "Sleep Now"
        case .display: "Display"
        case .sound: "Sound"
        }
    }

    var size: Size {
        switch self {
        case .caffeinate, .arrangement: .large
        case .nightShift, .sleepNow: .small
        case .display, .sound: .slider
        }
    }

    var hasDetail: Bool {
        switch self {
        case .caffeinate, .arrangement, .display, .sound: true
        case .nightShift, .sleepNow: false
        }
    }

    /// The pane its settings link and context menu open.
    var pane: SidebarItem {
        switch self {
        case .caffeinate, .sleepNow: .caffeinate
        case .arrangement: .displayArrangement
        case .nightShift: .nightShift
        case .display: .displays
        case .sound: .sound
        }
    }

    /// Asset base name (`<name>-line` / `<name>-filled`); nil uses `symbol`.
    var assetName: String? {
        switch self {
        case .caffeinate: "caffeinate"
        case .arrangement: "display-arrangement"
        case .nightShift: "night-shift"
        case .display: "display-brightness"
        case .sound: "sound"
        case .sleepNow: nil
        }
    }

    var symbol: String {
        switch self {
        case .sleepNow: "moon.zzz"
        default: "circle"
        }
    }

    var tint: Color { pane.tint }
}

/// Layout and look of the panel, as picked in `Prototypes/ControlCenterLab`.
enum ControlCenterDesign {
    static let panelWidth: CGFloat = 320
    static let padding: CGFloat = 12
    static let panelCornerRadius: CGFloat = 24
    static let spacing: CGFloat = 10
    static let rowHeight: CGFloat = 66
    static let moduleCornerRadius: CGFloat = 18
    static let iconSize: CGFloat = 34
    static let titleSize: CGFloat = 13
    static let subtitleSize: CGFloat = 11
    static let extraWidth: CGFloat = 300
    static let columns = 4

    static var unitWidth: CGFloat {
        (panelWidth - 2 * padding - CGFloat(columns - 1) * spacing) / CGFloat(columns)
    }

    static func span(_ module: ControlCenterModule) -> (width: Int, height: Int) {
        switch module.size {
        case .small: (1, 1)
        case .large: (2, 1)
        case .slider: (columns, 1)
        }
    }
}

struct ControlCenterPlacement: Identifiable, Equatable {
    let module: ControlCenterModule
    let col: Int
    let row: Int
    let width: Int
    var id: String { module.rawValue }
}

/// Dense first-fit packing on a 4-column grid, in the user's order, so a
/// later small control backfills a gap an earlier large one left. Every row
/// is one height, so a frame is pure arithmetic.
struct ControlCenterGrid {
    let placements: [ControlCenterPlacement]
    let rows: Int

    init(order: [ControlCenterModule]) {
        let columns = ControlCenterDesign.columns
        var occupied: [[Bool]] = []
        var placements: [ControlCenterPlacement] = []
        for module in order {
            let width = ControlCenterDesign.span(module).width
            var row = 0
            search: while true {
                if row >= occupied.count { occupied.append(Array(repeating: false, count: columns)) }
                for col in 0...(columns - width) where !occupied[row][col..<(col + width)].contains(true) {
                    for c in col..<(col + width) { occupied[row][c] = true }
                    placements.append(ControlCenterPlacement(module: module, col: col, row: row, width: width))
                    break search
                }
                row += 1
            }
        }
        self.placements = placements
        rows = occupied.count
    }

    var size: CGSize {
        let width = ControlCenterDesign.panelWidth - 2 * ControlCenterDesign.padding
        let height = CGFloat(rows) * ControlCenterDesign.rowHeight + CGFloat(max(rows - 1, 0)) * ControlCenterDesign.spacing
        return CGSize(width: width, height: height)
    }

    func frame(_ placement: ControlCenterPlacement) -> CGRect {
        let unit = ControlCenterDesign.unitWidth
        let spacing = ControlCenterDesign.spacing
        return CGRect(
            x: CGFloat(placement.col) * (unit + spacing),
            y: CGFloat(placement.row) * (ControlCenterDesign.rowHeight + spacing),
            width: CGFloat(placement.width) * unit + CGFloat(placement.width - 1) * spacing,
            height: ControlCenterDesign.rowHeight
        )
    }
}

/// Which controls are shown, in what order, and Caffeinate's last duration.
@Observable
@MainActor
final class ControlCenterSettings {
    static let shared = ControlCenterSettings()

    var order: [ControlCenterModule] {
        didSet { UserDefaults.standard.set(order.map(\.rawValue), forKey: Keys.order) }
    }

    /// What a click on the Caffeinate module starts.
    var lastCaffeinateDuration: CaffeinateDuration {
        didSet { UserDefaults.standard.set(lastCaffeinateDuration.rawValue, forKey: Keys.lastDuration) }
    }

    private enum Keys {
        static let order = "controlbox.controlCenter.order"
        static let lastDuration = "controlbox.controlCenter.lastCaffeinateDuration"
    }

    private init() {
        let defaults = UserDefaults.standard
        if let saved = defaults.stringArray(forKey: Keys.order) {
            var seen = Set<ControlCenterModule>()
            order = saved.compactMap(ControlCenterModule.init(rawValue:)).filter { seen.insert($0).inserted }
        } else {
            order = ControlCenterModule.defaultOrder
        }
        if defaults.object(forKey: Keys.lastDuration) != nil,
           let duration = CaffeinateDuration(rawValue: defaults.integer(forKey: Keys.lastDuration)) {
            lastCaffeinateDuration = duration
        } else {
            lastCaffeinateDuration = .oneHour
        }
    }

    var available: [ControlCenterModule] {
        ControlCenterModule.allCases.filter { !order.contains($0) }
    }

    func hide(_ module: ControlCenterModule) {
        order.removeAll { $0 == module }
    }

    func show(_ module: ControlCenterModule, before target: ControlCenterModule? = nil) {
        guard !order.contains(module) else { return }
        if let target, let index = order.firstIndex(of: target) {
            order.insert(module, at: index)
        } else {
            order.append(module)
        }
    }

    func resetLayout() {
        order = ControlCenterModule.defaultOrder
    }
}

/// The catalogs and window actions the panel drives.
@MainActor
struct ControlCenterContext {
    let displays: DisplayCatalog
    let sound: SoundCatalog
    let caffeinate: CaffeinateCatalog
    let nightShift: NightShiftCatalog
    let arrangement: ArrangementCatalog
    func openPane(_ item: SidebarItem) {
        PaneNavigation.open(item)
    }

    func openMainWindow() {
        WindowActions.showMain()
    }

    func startCaffeinate(_ duration: CaffeinateDuration) {
        ControlCenterSettings.shared.lastCaffeinateDuration = duration
        caffeinate.start(duration)
    }

    func toggleCaffeinate() {
        if caffeinate.isActive {
            caffeinate.stop()
        } else {
            caffeinate.start(ControlCenterSettings.shared.lastCaffeinateDuration)
        }
    }

    /// Short countdown for the module and detail header.
    func caffeinateStatus(now: Date) -> String {
        guard caffeinate.isActive else { return "Off" }
        guard let end = caffeinate.endDate, caffeinate.duration != .forever else { return "Staying awake" }
        return "\(CaffeinateDuration.countdownText(remaining: max(0, end.timeIntervalSince(now)))) left"
    }

    func sleepNow() {
        guard !caffeinate.sleepNow() else { return }
        let alert = NSAlert()
        alert.messageText = "Couldn’t Put This Mac to Sleep"
        alert.informativeText = "macOS did not accept the sleep request."
        alert.alertStyle = .warning
        alert.runModal()
    }

    /// The saved arrangement the displays are in right now, if any.
    var liveArrangement: ArrangementPreset? {
        arrangement.applicablePresets.first { arrangement.matchesLive($0) }
    }
}
