import AppKit

/// Template ring for the Control Box menu extra, matching the app icon’s
/// centered annulus (not the orange squircle — menu bar items stay monochrome).
enum MenuBarRingIcon {
    static let image: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let lineWidth = rect.width * 0.16
            let inset = rect.width * 0.14 + lineWidth / 2
            let path = NSBezierPath(ovalIn: rect.insetBy(dx: inset, dy: inset))
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
