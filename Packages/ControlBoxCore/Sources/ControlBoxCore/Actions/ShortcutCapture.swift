import Foundation

/// True while a shortcut recorder is capturing a key, until that key is released.
/// Mac hotkeys must not fire during that window.
public enum ShortcutCapture {
    private static let lock = NSLock()
    private static var active = false

    public static var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return active
    }

    public static func setActive(_ value: Bool) {
        lock.lock()
        active = value
        lock.unlock()
    }
}
