import AppKit
import Darwin
import Foundation

/// Light / Dark / Auto appearance. Night Shift take-over can flip Auto dark mode
/// because it shares sunset scheduling; pin the look we captured and restore Auto later.
public enum MacAppearance {
    public struct Snapshot: Codable, Equatable, Sendable {
        public var automatic: Bool
        public var dark: Bool

        public init(automatic: Bool, dark: Bool) {
            self.automatic = automatic
            self.dark = dark
        }
    }

    private static let autoKey = "AppleInterfaceStyleSwitchesAutomatically"
    private static let styleKey = "AppleInterfaceStyle"
    private static let sky = dlopen(
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
        RTLD_LAZY
    )

    public static func snapshot() -> Snapshot {
        Snapshot(automatic: automatic(), dark: isDark())
    }

    public static func isCurrentlyDark() -> Bool {
        isDark()
    }

    public static func applyDark(_ dark: Bool) {
        pin(Snapshot(automatic: false, dark: dark))
    }

    /// Freeze Light or Dark so Auto cannot follow Night Shift.
    public static func pin(_ snapshot: Snapshot) {
        if automatic() {
            setAutomatic(false)
        }
        // Turning Auto off applies the stored legacy theme, which stays Dark
        // while Auto is showing Light. Always write the captured look.
        setDark(snapshot.dark)
    }

    public static func restore(_ snapshot: Snapshot) {
        if snapshot.automatic {
            setAutomatic(true)
        } else {
            setAutomatic(false)
            setDark(snapshot.dark)
        }
    }

    private static func automatic() -> Bool {
        guard let value = CFPreferencesCopyValue(
            autoKey as CFString,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        ) else { return false }
        if let flag = value as? Bool { return flag }
        if let number = value as? NSNumber { return number.boolValue }
        return false
    }

    private static func isDark() -> Bool {
        let appearance: NSAppearance
        if Thread.isMainThread {
            appearance = NSApp.effectiveAppearance
        } else {
            var value: NSAppearance?
            DispatchQueue.main.sync {
                value = NSApp.effectiveAppearance
            }
            appearance = value ?? NSAppearance(named: .aqua) ?? NSAppearance()
        }
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private static func setAutomatic(_ on: Bool) {
        setGlobal(autoKey, on ? kCFBooleanTrue : kCFBooleanFalse)
    }

    private static func setDark(_ on: Bool) {
        if on {
            setGlobal(styleKey, "Dark" as CFString)
        } else {
            setGlobal(styleKey, nil)
        }
        if let setNotifying = dlsym(sky, "SLSSetAppearanceThemeNotifying") {
            typealias Fn = @convention(c) (Bool, Bool) -> Bool
            _ = unsafeBitCast(setNotifying, to: Fn.self)(on, true)
            return
        }
        if let setLegacy = dlsym(sky, "SLSSetAppearanceThemeLegacy") {
            typealias Fn = @convention(c) (Bool) -> Bool
            _ = unsafeBitCast(setLegacy, to: Fn.self)(on)
        }
    }

    private static func setGlobal(_ key: String, _ value: CFPropertyList?) {
        CFPreferencesSetValue(
            key as CFString,
            value,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        CFPreferencesSynchronize(
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
    }
}
