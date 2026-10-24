import AppKit
import SwiftUI

enum ModuleSize {
    case small, large, slider
}

/// The v1 module set agreed for the Control Box Control Center.
enum ModuleKind: String, CaseIterable, Identifiable, Codable {
    case caffeinate, arrangement, nightShift, sleepNow, display, sound

    var id: String { rawValue }

    var title: String {
        switch self {
        case .caffeinate: "Caffeinate"
        case .arrangement: "Arrangement"
        case .nightShift: "Night Shift"
        case .sleepNow: "Sleep"
        case .display: "Display"
        case .sound: "Sound"
        }
    }

    /// The Control Box pane the module's settings link opens.
    var paneTitle: String {
        switch self {
        case .caffeinate: "Caffeinate"
        case .arrangement: "Display Arrangement"
        case .nightShift: "Night Shift"
        case .sleepNow: "Caffeinate"
        case .display: "Display Brightness"
        case .sound: "Sound"
        }
    }

    var size: ModuleSize {
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

    /// Modules that can also be their own menu bar extra.
    var canBeExtra: Bool {
        switch self {
        case .caffeinate, .display, .sound: true
        default: false
        }
    }

    /// Control Box asset base name (`<name>-line` / `<name>-filled`).
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
        case .caffeinate: "cup.and.saucer"
        case .arrangement: "rectangle.on.rectangle"
        case .nightShift: "moon"
        case .sleepNow: "moon.zzz"
        case .display: "sun.max"
        case .sound: "speaker.wave.2"
        }
    }

    /// Sidebar tints from Control Box `SidebarItem.tint`.
    var tint: Color {
        switch self {
        case .display: Color(red: 0.20, green: 0.48, blue: 0.96)
        case .nightShift: Color(red: 0.96, green: 0.48, blue: 0.18)
        case .arrangement: Color(red: 0.12, green: 0.40, blue: 0.78)
        case .sound: Color(red: 0.35, green: 0.34, blue: 0.84)
        case .caffeinate: Color(red: 0.62, green: 0.40, blue: 0.22)
        case .sleepNow: Color(red: 0.32, green: 0.30, blue: 0.62)
        }
    }
}

/// Copy of Control Box `CaffeinateDuration`.
enum CaffeinateDuration: Int, CaseIterable, Identifiable {
    case oneMinute = 60
    case fiveMinutes = 300
    case tenMinutes = 600
    case twentyMinutes = 1_200
    case thirtyMinutes = 1_800
    case fortyMinutes = 2_400
    case fiftyMinutes = 3_000
    case oneHour = 3_600
    case twoHours = 7_200
    case threeHours = 10_800
    case oneDay = 86_400
    case forever = 0

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .oneMinute: "1 Minute"
        case .fiveMinutes: "5 Minutes"
        case .tenMinutes: "10 Minutes"
        case .twentyMinutes: "20 Minutes"
        case .thirtyMinutes: "30 Minutes"
        case .fortyMinutes: "40 Minutes"
        case .fiftyMinutes: "50 Minutes"
        case .oneHour: "1 Hour"
        case .twoHours: "2 Hours"
        case .threeHours: "3 Hours"
        case .oneDay: "1 Day"
        case .forever: "Forever"
        }
    }

    var short: String {
        switch self {
        case .oneMinute: "1m"
        case .fiveMinutes: "5m"
        case .tenMinutes: "10m"
        case .twentyMinutes: "20m"
        case .thirtyMinutes: "30m"
        case .fortyMinutes: "40m"
        case .fiftyMinutes: "50m"
        case .oneHour: "1h"
        case .twoHours: "2h"
        case .threeHours: "3h"
        case .oneDay: "1d"
        case .forever: "∞"
        }
    }

    static func countdownText(remaining: TimeInterval) -> String {
        let total = max(0, Int(remaining.rounded(.down)))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct MockDisplay: Identifiable, Equatable {
    let id: String
    var name: String
    var brightness: Double
    var canAdjust: Bool
}

struct MockOutput: Identifiable, Equatable {
    let id: String
    var name: String
    var symbol: String
}

struct MockApp: Identifiable, Equatable {
    let id: String
    var name: String
    var volume: Double
    var playing: Bool
    var muted: Bool
}

/// A saved arrangement: normalized screen rects for the thumbnail.
struct MockPreset: Identifiable, Equatable {
    let id: String
    var name: String
    var screens: [CGRect]
}

enum LabIcons {
    private static var cache: [String: NSImage] = [:]
    private static let iconsDir: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("ControlBox/Assets.xcassets/Icons")
    }()

    static func image(_ name: String) -> NSImage? {
        if let hit = cache[name] { return hit }
        let url = iconsDir.appendingPathComponent("\(name).imageset/\(name).svg")
        guard let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        cache[name] = image
        return image
    }

    static func appIcon(bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    static let ring: NSImage? = image("menu-bar-icon-template")
}
