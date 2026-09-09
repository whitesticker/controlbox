import CoreGraphics
import Foundation
import ControlBoxCore

/// Pointer, scroll, and window-grab settings for the Mac panes. These are
/// not tied to an MX Master being attached — HID++ still applies per mouse
/// when one is present.
struct MacMouseSettings: Codable, Equatable {
    var pointerSpeed: Double
    var wheelScrollSpeed: Double
    var thumbScrollSpeed: Double
    var naturalScrolling: Bool
    var smoothScrolling: Bool
    var windowMoveEnabled: Bool
    var windowResizeEnabled: Bool
    var windowThrowEnabled: Bool
    var windowOrganizeEnabled: Bool
    var windowMoveFlags: UInt64
    var windowResizeFlags: UInt64
    var windowThrowFlags: UInt64
    var windowOrganizeFlags: UInt64
    var windowOrganizeKey: UInt16
    var windowShakeEnabled: Bool
    var windowShakeScope: WindowShakeScope
    var windowDockClickMinimizeEnabled: Bool

    static let defaultsKey = "controlbox.macMouse.v1"

    static var factory: MacMouseSettings {
        MacMouseSettings(
            pointerSpeed: 0.21,
            wheelScrollSpeed: 0.5,
            thumbScrollSpeed: 0.5,
            naturalScrolling: false,
            smoothScrolling: true,
            windowMoveEnabled: true,
            windowResizeEnabled: true,
            windowThrowEnabled: false,
            windowOrganizeEnabled: false,
            windowMoveFlags: MappingProfile.defaultWindowMoveFlags,
            windowResizeFlags: MappingProfile.defaultWindowResizeFlags,
            windowThrowFlags: MappingProfile.defaultWindowThrowFlags,
            windowOrganizeFlags: MappingProfile.defaultWindowOrganizeFlags,
            windowOrganizeKey: MappingProfile.defaultWindowOrganizeKey,
            windowShakeEnabled: false,
            windowShakeScope: .thisDisplay,
            windowDockClickMinimizeEnabled: false
        )
    }

    static func load(seedingFrom profile: MappingProfile?) -> MacMouseSettings {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode(MacMouseSettings.self, from: data) {
            return saved
        }
        var settings = factory
        if let profile {
            settings.pointerSpeed = profile.resolvedPointerSpeed
            settings.wheelScrollSpeed = profile.resolvedWheelScrollSpeed
            settings.thumbScrollSpeed = profile.resolvedThumbScrollSpeed
            settings.naturalScrolling = profile.resolvedNaturalScrolling
            settings.smoothScrolling = profile.resolvedSmoothScrolling
            settings.windowMoveEnabled = profile.resolvedWindowMoveEnabled
            settings.windowResizeEnabled = profile.resolvedWindowResizeEnabled
            settings.windowThrowEnabled = profile.resolvedWindowThrowEnabled
            settings.windowOrganizeEnabled = profile.resolvedWindowOrganizeEnabled
            settings.windowMoveFlags = profile.resolvedWindowMoveFlags.rawValue
            settings.windowResizeFlags = profile.resolvedWindowResizeFlags.rawValue
            settings.windowThrowFlags = profile.resolvedWindowThrowFlags.rawValue
            settings.windowOrganizeFlags = profile.resolvedWindowOrganizeFlags.rawValue
            settings.windowOrganizeKey = profile.resolvedWindowOrganizeKey
            settings.windowShakeEnabled = profile.resolvedWindowShakeEnabled
            settings.windowShakeScope = profile.resolvedWindowShakeScope
            settings.windowDockClickMinimizeEnabled = profile.resolvedWindowDockClickMinimizeEnabled
        } else {
            settings.pointerSpeed = 0.5
            settings.naturalScrolling = true
        }
        return settings
    }

    func persist() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    func apply(to profile: inout MappingProfile) {
        profile.pointerSpeed = pointerSpeed
        profile.wheelScrollSpeed = wheelScrollSpeed
        profile.thumbScrollSpeed = thumbScrollSpeed
        profile.naturalScrolling = naturalScrolling
        profile.smoothScrolling = smoothScrolling
        profile.windowMoveEnabled = windowMoveEnabled
        profile.windowResizeEnabled = windowResizeEnabled
        profile.windowThrowEnabled = windowThrowEnabled
        profile.windowOrganizeEnabled = windowOrganizeEnabled
        profile.windowMoveFlags = windowMoveFlags
        profile.windowResizeFlags = windowResizeFlags
        profile.windowThrowFlags = windowThrowFlags
        profile.windowOrganizeFlags = windowOrganizeFlags
        profile.windowOrganizeKey = windowOrganizeKey
        profile.windowShakeEnabled = windowShakeEnabled
        profile.windowShakeScope = windowShakeScope
        profile.windowDockClickMinimizeEnabled = windowDockClickMinimizeEnabled
    }

    var asProfile: MappingProfile {
        var profile = MappingProfile.makeDefault(isAppleTVRemote: false, isMXMaster: true)
        apply(to: &profile)
        return profile
    }

    init(
        pointerSpeed: Double,
        wheelScrollSpeed: Double,
        thumbScrollSpeed: Double,
        naturalScrolling: Bool,
        smoothScrolling: Bool,
        windowMoveEnabled: Bool,
        windowResizeEnabled: Bool,
        windowThrowEnabled: Bool,
        windowOrganizeEnabled: Bool,
        windowMoveFlags: UInt64,
        windowResizeFlags: UInt64,
        windowThrowFlags: UInt64,
        windowOrganizeFlags: UInt64,
        windowOrganizeKey: UInt16,
        windowShakeEnabled: Bool,
        windowShakeScope: WindowShakeScope,
        windowDockClickMinimizeEnabled: Bool
    ) {
        self.pointerSpeed = pointerSpeed
        self.wheelScrollSpeed = wheelScrollSpeed
        self.thumbScrollSpeed = thumbScrollSpeed
        self.naturalScrolling = naturalScrolling
        self.smoothScrolling = smoothScrolling
        self.windowMoveEnabled = windowMoveEnabled
        self.windowResizeEnabled = windowResizeEnabled
        self.windowThrowEnabled = windowThrowEnabled
        self.windowOrganizeEnabled = windowOrganizeEnabled
        self.windowMoveFlags = windowMoveFlags
        self.windowResizeFlags = windowResizeFlags
        self.windowThrowFlags = windowThrowFlags
        self.windowOrganizeFlags = windowOrganizeFlags
        self.windowOrganizeKey = windowOrganizeKey
        self.windowShakeEnabled = windowShakeEnabled
        self.windowShakeScope = windowShakeScope
        self.windowDockClickMinimizeEnabled = windowDockClickMinimizeEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pointerSpeed = try container.decode(Double.self, forKey: .pointerSpeed)
        wheelScrollSpeed = try container.decode(Double.self, forKey: .wheelScrollSpeed)
        thumbScrollSpeed = try container.decode(Double.self, forKey: .thumbScrollSpeed)
        naturalScrolling = try container.decode(Bool.self, forKey: .naturalScrolling)
        smoothScrolling = try container.decode(Bool.self, forKey: .smoothScrolling)
        windowMoveEnabled = try container.decode(Bool.self, forKey: .windowMoveEnabled)
        windowResizeEnabled = try container.decode(Bool.self, forKey: .windowResizeEnabled)
        windowThrowEnabled = try container.decodeIfPresent(Bool.self, forKey: .windowThrowEnabled) ?? false
        windowOrganizeEnabled = try container.decodeIfPresent(Bool.self, forKey: .windowOrganizeEnabled) ?? false
        windowMoveFlags = try container.decode(UInt64.self, forKey: .windowMoveFlags)
        windowResizeFlags = try container.decode(UInt64.self, forKey: .windowResizeFlags)
        windowThrowFlags = try container.decodeIfPresent(UInt64.self, forKey: .windowThrowFlags)
            ?? MappingProfile.defaultWindowThrowFlags
        if container.contains(.windowOrganizeKey) {
            windowOrganizeFlags = try container.decodeIfPresent(UInt64.self, forKey: .windowOrganizeFlags)
                ?? MappingProfile.defaultWindowOrganizeFlags
            windowOrganizeKey = try container.decodeIfPresent(UInt16.self, forKey: .windowOrganizeKey)
                ?? MappingProfile.defaultWindowOrganizeKey
        } else {
            windowOrganizeFlags = MappingProfile.defaultWindowOrganizeFlags
            windowOrganizeKey = MappingProfile.defaultWindowOrganizeKey
        }
        windowShakeEnabled = try container.decodeIfPresent(Bool.self, forKey: .windowShakeEnabled) ?? false
        windowShakeScope = try container.decodeIfPresent(WindowShakeScope.self, forKey: .windowShakeScope)
            ?? .thisDisplay
        windowDockClickMinimizeEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .windowDockClickMinimizeEnabled
        ) ?? false
    }
}
