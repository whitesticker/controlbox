import Foundation

public enum MouseAppCategory: String, Codable, Equatable, Sendable {
    case browsers
    case editors
}

public enum MouseAppCatalog: Sendable {
    public static let controlBoxBundleID = "com.whitesticker.controlbox"

    public static let browserBundleIDs: Set<String> = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "org.mozilla.nightly",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "company.thebrowser.Browser",
        "company.thebrowser.dia",
        "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi",
        "com.kagi.orion",
    ]

    public static let editorBundleIDs: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92",
        "com.exafunction.windsurf",
        "com.apple.dt.Xcode",
        "dev.zed.Zed",
        "com.sublimetext.4",
        "com.panic.Nova",
        "com.barebones.bbedit",
        "com.jetbrains.intellij",
        "com.jetbrains.WebStorm",
        "com.jetbrains.pycharm",
        "com.jetbrains.CLion",
        "com.jetbrains.goland",
        "com.jetbrains.PhpStorm",
        "com.jetbrains.Rider",
        "com.coteditor.CotEditor",
    ]

    public static func category(forBundleID bundleID: String) -> MouseAppCategory? {
        if browserBundleIDs.contains(bundleID) { return .browsers }
        if editorBundleIDs.contains(bundleID) { return .editors }
        return nil
    }

    /// Exact app row, else Default. Control Box keeps the last live mapping
    /// unless the user added a Control Box row.
    public static func liveProfile(
        profiles: [MappingProfile],
        defaultProfile: MappingProfile,
        frontmostBundleID: String?,
        lastLiveID: String?
    ) -> MappingProfile {
        let bundle = frontmostBundleID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if bundle.isEmpty {
            return defaultProfile
        }
        if let exact = profiles.first(where: { $0.frontmostAppBundleID == bundle }) {
            return exact
        }
        if bundle == controlBoxBundleID {
            if let lastLiveID, let last = profiles.first(where: { $0.id == lastLiveID }) {
                return last
            }
        }
        return defaultProfile
    }

    public enum AppProfileFamily: Sendable {
        case mouse
        case gamepad
        case remote
    }

    public static func profileForAddedApp(
        from defaultProfile: MappingProfile,
        bundleID: String,
        name: String,
        family: AppProfileFamily = .mouse
    ) -> MappingProfile {
        var next = defaultProfile.duplicated(as: name)
        next.frontmostAppBundleID = bundleID
        next.appCategory = nil
        next.isMXDefault = false
        next.name = name
        switch (family, category(forBundleID: bundleID)) {
        case (.mouse, .browsers):
            next.mxThumbWheelMode = .switchTabs
            next.bindings[.mxThumbLeft] = nil
            next.bindings[.mxThumbRight] = nil
            next.setGestureSet(
                GestureSet(
                    preset: .custom,
                    click: .missionControl,
                    up: .missionControl,
                    down: .appExpose,
                    left: .tabPrevious,
                    right: .tabNext
                ),
                for: .mxHaptic
            )
        case (.mouse, .editors):
            next.bindings[.mxBack] = .tabPrevious
            next.bindings[.mxForward] = .tabNext
        case (.gamepad, .browsers), (.gamepad, .editors):
            next.bindings[.l2] = .tabPrevious
            next.bindings[.r2] = .tabNext
        default:
            break
        }
        return next
    }
}

public extension MappingProfile {
    var treatsAsMXDefault: Bool { isMXDefault == true }

    var mxScopeTitle: String {
        if treatsAsMXDefault { return "Default" }
        return name
    }

    var isMXLeftoverNamedProfile: Bool {
        !treatsAsMXDefault && appCategory == nil && (frontmostAppBundleID ?? "").isEmpty
    }
}
