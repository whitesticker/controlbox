import AppKit
import CoreGraphics
import Darwin
import Foundation

enum SystemNavigation {
    static func perform(_ action: ControlAction) {
        switch action {
        case .missionControl:
            if coreDock("com.apple.expose.awake") { return }
            if sendSymbolicHotKey(32) { return }
            chord(virtualKey: 126, flags: .maskControl)
        case .appExpose:
            if coreDock("com.apple.expose.front.awake") { return }
            if sendSymbolicHotKey(33) { return }
            chord(virtualKey: 125, flags: .maskControl)
        case .showDesktop:
            if coreDock("com.apple.showdesktop.awake") { return }
            if sendSymbolicHotKey(36) { return }
            chord(virtualKey: 103, flags: .maskCommand)
        case .spaceLeft:
            DockSwipe.play(axis: .horizontal, offset: -1.5)
        case .spaceRight:
            DockSwipe.play(axis: .horizontal, offset: 1.5)
        case .switchApplication:
            AppSwitcher.step(back: false)
        case .switchApplicationBack:
            AppSwitcher.step(back: true)
        default:
            break
        }
    }

    private static func chord(virtualKey: UInt16, flags: CGEventFlags) {
        if flags.contains(.maskControl) {
            EventPoster.key(59, flags: .maskControl, down: true)
        }
        if flags.contains(.maskCommand) {
            EventPoster.key(55, flags: .maskCommand, down: true)
        }
        if flags.contains(.maskAlternate) {
            EventPoster.key(58, flags: .maskAlternate, down: true)
        }
        if flags.contains(.maskShift) {
            EventPoster.key(56, flags: .maskShift, down: true)
        }
        EventPoster.key(virtualKey, flags: flags, down: true)
        EventPoster.key(virtualKey, flags: flags, down: false)
        if flags.contains(.maskShift) {
            EventPoster.key(56, flags: [], down: false)
        }
        if flags.contains(.maskAlternate) {
            EventPoster.key(58, flags: [], down: false)
        }
        if flags.contains(.maskCommand) {
            EventPoster.key(55, flags: [], down: false)
        }
        if flags.contains(.maskControl) {
            EventPoster.key(59, flags: [], down: false)
        }
    }

    private static func coreDock(_ name: String) -> Bool {
        typealias Notify = @convention(c) (CFString, UnsafeRawPointer?) -> Void
        guard let symbol = skyLightSymbol("CoreDockSendNotification") else { return false }
        unsafeBitCast(symbol, to: Notify.self)(name as CFString, nil)
        return true
    }

    private static func skyLightHandle() -> UnsafeMutableRawPointer? {
        let paths = [
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
            "/System/Library/PrivateFrameworks/Dock.framework/Dock"
        ]
        if let existing = dlopen(paths[0], RTLD_NOLOAD | RTLD_NOW) ?? dlopen(paths[0], RTLD_NOW) {
            return existing
        }
        for path in paths.dropFirst() {
            if let handle = dlopen(path, RTLD_NOW) { return handle }
        }
        return UnsafeMutableRawPointer(bitPattern: -2)
    }

    private static func skyLightSymbol(_ name: String) -> UnsafeMutableRawPointer? {
        if let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) {
            return symbol
        }
        guard let handle = skyLightHandle() else { return nil }
        return dlsym(handle, name)
    }

    private static func sendSymbolicHotKey(_ id: Int) -> Bool {
        guard let domains = UserDefaults(suiteName: "com.apple.symbolichotkeys")?
            .dictionary(forKey: "AppleSymbolicHotKeys"),
              let entry = domains["\(id)"] as? [String: Any],
              (entry["enabled"] as? Bool) ?? ((entry["enabled"] as? Int) == 1),
              let value = entry["value"] as? [String: Any],
              let parameters = value["parameters"] as? [Any],
              parameters.count >= 3
        else { return false }

        let keyCode = intValue(parameters[1])
        let mods = intValue(parameters[2])
        guard keyCode > 0, keyCode < 128 else { return false }

        var flags = CGEventFlags(rawValue: 0)
        if mods & 0x0004_0000 != 0 { flags.insert(.maskControl) }
        if mods & 0x0008_0000 != 0 { flags.insert(.maskCommand) }
        if mods & 0x0002_0000 != 0 { flags.insert(.maskAlternate) }
        if mods & 0x0001_0000 != 0 { flags.insert(.maskShift) }
        chord(virtualKey: UInt16(keyCode), flags: flags)
        return true
    }

    private static func intValue(_ value: Any) -> Int {
        if let number = value as? Int { return number }
        if let number = value as? NSNumber { return number.intValue }
        return 0
    }
}

/// Command-Tab only shows the app switcher while Command stays down.
/// Shift must stay down too for Previous, or the bar never opens in reverse.
enum AppSwitcher {
    private static let queue = DispatchQueue(label: "controlbox.app-switcher")
    private static var commandHeld = false
    private static var shiftHeld = false
    private static var releaseWork: DispatchWorkItem?
    private static let holdAfterTap: TimeInterval = 1.15

    static func step(back: Bool) {
        queue.async {
            releaseWork?.cancel()
            releaseWork = nil
            if !commandHeld {
                EventPoster.key(55, flags: .maskCommand, down: true)
                commandHeld = true
                Thread.sleep(forTimeInterval: 0.03)
            }
            if back {
                if !shiftHeld {
                    EventPoster.key(56, flags: [.maskCommand, .maskShift], down: true)
                    shiftHeld = true
                    Thread.sleep(forTimeInterval: 0.02)
                }
            } else if shiftHeld {
                EventPoster.key(56, flags: .maskCommand, down: false)
                shiftHeld = false
            }
            var flags: CGEventFlags = .maskCommand
            if back { flags.insert(.maskShift) }
            EventPoster.key(48, flags: flags, down: true)
            EventPoster.key(48, flags: flags, down: false)
            let work = DispatchWorkItem {
                queue.async { releaseModifiers() }
            }
            releaseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + holdAfterTap, execute: work)
        }
    }

    static func cancel() {
        queue.sync {
            releaseWork?.cancel()
            releaseWork = nil
            releaseModifiers()
        }
    }

    private static func releaseModifiers() {
        if shiftHeld {
            EventPoster.key(56, flags: commandHeld ? .maskCommand : [], down: false)
            shiftHeld = false
        }
        if commandHeld {
            EventPoster.key(55, flags: [], down: false)
            commandHeld = false
        }
        releaseWork = nil
    }
}
