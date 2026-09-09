import Foundation

/// Pinned Dock tiles store the hover name in `tile-data.file-label`.
/// Clearing that string hides the native tooltip; we snapshot first so it can come back.
public enum DockFileLabel {
    public struct BackupItem: Codable, Equatable, Sendable {
        public var section: String
        public var guid: String
        public var label: String

        public init(section: String, guid: String, label: String) {
            self.section = section
            self.guid = guid
            self.label = label
        }
    }

    private static let domain = "com.apple.dock" as CFString
    private static let sections = [
        "persistent-apps",
        "persistent-others",
        "recent-apps",
        "recent-others"
    ]

    /// Empty every pinned `file-label`. Keeps existing backups and adds new ones.
    public static func hide(existing: [BackupItem]) -> [BackupItem] {
        var backup = existing
        for section in sections {
            guard var tiles = copyTiles(section) else { continue }
            var changed = false
            for index in tiles.indices {
                guard var tile = tiles[index] as? [String: Any] else { continue }
                let id = guid(of: tile, fallback: "\(section)-\(index)")
                var data = (tile["tile-data"] as? [String: Any]) ?? [:]
                let current = data["file-label"] as? String ?? ""
                guard !current.isEmpty else { continue }
                if !backup.contains(where: { $0.section == section && $0.guid == id }) {
                    backup.append(BackupItem(section: section, guid: id, label: current))
                }
                data["file-label"] = ""
                tile["tile-data"] = data
                tiles[index] = tile
                changed = true
            }
            if changed {
                writeTiles(section, tiles)
            }
        }
        publish()
        return backup
    }

    public static func restore(_ backup: [BackupItem]) {
        guard !backup.isEmpty else { return }
        let bySection = Dictionary(grouping: backup, by: \.section)
        for section in sections {
            guard var tiles = copyTiles(section) else { continue }
            let items = bySection[section] ?? []
            guard !items.isEmpty else { continue }
            var changed = false
            for index in tiles.indices {
                guard var tile = tiles[index] as? [String: Any] else { continue }
                let id = guid(of: tile, fallback: "\(section)-\(index)")
                guard let item = items.first(where: { $0.guid == id }) else { continue }
                var data = (tile["tile-data"] as? [String: Any]) ?? [:]
                data["file-label"] = item.label
                tile["tile-data"] = data
                tiles[index] = tile
                changed = true
            }
            if changed {
                writeTiles(section, tiles)
            }
        }
        publish()
    }

    private static func copyTiles(_ key: String) -> [Any]? {
        guard let raw = CFPreferencesCopyAppValue(key as CFString, domain) else { return nil }
        return raw as? [Any]
    }

    private static func writeTiles(_ key: String, _ tiles: [Any]) {
        CFPreferencesSetAppValue(key as CFString, tiles as CFArray, domain)
    }

    private static func guid(of tile: [String: Any], fallback: String) -> String {
        if let value = tile["GUID"] as? String, !value.isEmpty { return value }
        if let value = tile["GUID"] as? NSNumber { return value.stringValue }
        let data = tile["tile-data"] as? [String: Any] ?? [:]
        if let value = data["bundle-identifier"] as? String, !value.isEmpty { return value }
        if let file = data["file-data"] as? [String: Any] {
            if let url = file["_CFURLString"] as? String, !url.isEmpty { return url }
        }
        return fallback
    }

    private static func publish() {
        CFPreferencesAppSynchronize(domain)
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.apple.dock.prefchanged"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }
}
