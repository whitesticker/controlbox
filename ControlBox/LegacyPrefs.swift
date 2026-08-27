import Foundation

/// Copies mappings from the previous app identity into this bundle’s defaults.
enum LegacyPrefs {
    static func migrateIfNeeded() {
        let flag = "controlbox.didMigrateLegacyPrefs"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        defer { UserDefaults.standard.set(true, forKey: flag) }

        let keyMap = [
            "iremote.deviceRecords.v1": "controlbox.deviceRecords.v1",
            "iremote.selectedDeviceID": "controlbox.selectedDeviceID",
            "iremote.suppressedDevices.v1": "controlbox.suppressedDevices.v1",
            "IRemote.appVolumes.v1": "controlbox.appVolumes.v1",
            "IRemote.monitorSettings.v1": "controlbox.monitorSettings.v1",
        ]

        copy(from: UserDefaults.standard.dictionaryRepresentation(), keyMap: keyMap)

        let oldPlist = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.iremote.app.plist")
        if let dict = NSDictionary(contentsOf: oldPlist) as? [String: Any] {
            copy(from: dict, keyMap: keyMap)
        }
    }

    private static func copy(from source: [String: Any], keyMap: [String: String]) {
        for (oldKey, newKey) in keyMap {
            guard UserDefaults.standard.object(forKey: newKey) == nil, let value = source[oldKey] else {
                continue
            }
            UserDefaults.standard.set(value, forKey: newKey)
        }
    }
}
