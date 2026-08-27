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
    var windowMoveFlags: UInt64
    var windowResizeFlags: UInt64

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
            windowMoveFlags: MappingProfile.defaultWindowMoveFlags,
            windowResizeFlags: MappingProfile.defaultWindowResizeFlags
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
            settings.windowMoveFlags = profile.resolvedWindowMoveFlags.rawValue
            settings.windowResizeFlags = profile.resolvedWindowResizeFlags.rawValue
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
        profile.windowMoveFlags = windowMoveFlags
        profile.windowResizeFlags = windowResizeFlags
    }

    var asProfile: MappingProfile {
        var profile = MappingProfile.makeDefault(isAppleTVRemote: false, isMXMaster: true)
        apply(to: &profile)
        return profile
    }
}
