import AppKit
import Foundation
import Observation

/// App-lifecycle and extra-icon prefs. Launch at Login is `SMAppService`, not here.
@Observable
@MainActor
final class AppSettings {
    static let shared = AppSettings()

    var hideDockIcon: Bool {
        didSet {
            UserDefaults.standard.set(hideDockIcon, forKey: Keys.hideDock)
            applyDockPolicy()
        }
    }

    var brightnessMenuBarEnabled: Bool {
        didSet {
            UserDefaults.standard.set(brightnessMenuBarEnabled, forKey: Keys.brightnessExtra)
            MenuBarExtrasHost.shared.apply()
        }
    }

    var soundMenuBarEnabled: Bool {
        didSet {
            UserDefaults.standard.set(soundMenuBarEnabled, forKey: Keys.soundExtra)
            MenuBarExtrasHost.shared.apply()
        }
    }

    var caffeinateMenuBarEnabled: Bool {
        didSet {
            UserDefaults.standard.set(caffeinateMenuBarEnabled, forKey: Keys.caffeinateExtra)
            CaffeinateMenuBarHost.shared.apply()
        }
    }

    private enum Keys {
        static let hideDock = "controlbox.hideDockIcon"
        static let brightnessExtra = "controlbox.displays.menuBarEnabled"
        static let soundExtra = "controlbox.sound.menuBarEnabled"
        static let caffeinateExtra = "controlbox.caffeinate.menuBarEnabled"
    }

    private init() {
        let defaults = UserDefaults.standard
        hideDockIcon = defaults.bool(forKey: Keys.hideDock)
        brightnessMenuBarEnabled = defaults.bool(forKey: Keys.brightnessExtra)
        soundMenuBarEnabled = defaults.bool(forKey: Keys.soundExtra)
        caffeinateMenuBarEnabled = defaults.bool(forKey: Keys.caffeinateExtra)
    }

    func applyDockPolicy() {
        NSApp.setActivationPolicy(hideDockIcon ? .accessory : .regular)
        if !hideDockIcon {
            NSApp.activate()
        }
    }
}

enum AppQuit {
    @MainActor
    static func quitNow() {
        NSApp.terminate(nil)
    }
}

enum PaneNavigation {
    static var pending: SidebarItem?

    @MainActor
    static func open(_ item: SidebarItem) {
        pending = item
        WindowActions.openMain?("main")
        NotificationCenter.default.post(name: .controlBoxOpenPane, object: nil)
        NSApp.activate()
    }
}
