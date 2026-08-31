import AppKit

/// Template D-segments for the Control Box menu extra, matching the app icon
/// mark (not the orange squircle — menu bar items stay monochrome).
enum MenuBarRingIcon {
    static let image: NSImage = {
        let image = NSImage(named: "menu-bar-icon-template") ?? NSImage(size: NSSize(width: 14, height: 14))
        image.isTemplate = true
        image.size = NSSize(width: 14, height: 14)
        return image
    }()
}
