import AppKit
import CoreGraphics
import Foundation

enum VolumeHUD {
    static func show(level: Double) {
        let clamped = min(max(level, 0), 1)
        if Thread.isMainThread {
            Controller.shared.show(level: clamped)
        } else {
            DispatchQueue.main.async {
                Controller.shared.show(level: clamped)
            }
        }
    }

    private final class Controller {
        static let shared = Controller()

        private var window: HUDWindow?
        private var hideWork: DispatchWorkItem?

        func show(level: Double) {
            if window == nil {
                window = HUDWindow()
            }
            window?.update(level: level)

            hideWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.window?.orderOut(nil)
            }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.15, execute: work)
        }
    }
}

private final class HUDWindow {
    private let panel: NSPanel
    private let hud: HUDView

    init() {
        hud = HUDView(frame: NSRect(origin: .zero, size: HUDView.preferredSize))
        panel = NSPanel(
            contentRect: hud.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hud
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .transient,
            .stationary
        ]
        panel.isExcludedFromWindowsMenu = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.setAccessibilityElement(false)
        hud.setAccessibilityElement(false)
    }

    func update(level: Double) {
        hud.level = level
        let size = HUDView.preferredSize
        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let origin = NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.minY + frame.height * 0.22
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    func orderOut(_ sender: Any?) {
        panel.orderOut(sender)
    }
}

private final class HUDView: NSView {
    static let preferredSize = NSSize(width: 220, height: 214)

    var level: Double = 0 {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }
    override var wantsUpdateLayer: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let card = bounds.insetBy(dx: 8, dy: 8)
        let background = NSBezierPath(roundedRect: card, xRadius: 22, yRadius: 22)
        NSColor.black.withAlphaComponent(0.72).setFill()
        background.fill()

        let muted = level < 0.001
        let symbolName: String
        if muted {
            symbolName = "speaker.slash.fill"
        } else if level < 0.34 {
            symbolName = "speaker.wave.1.fill"
        } else if level < 0.67 {
            symbolName = "speaker.wave.2.fill"
        } else {
            symbolName = "speaker.wave.3.fill"
        }

        let config = NSImage.SymbolConfiguration(pointSize: 52, weight: .medium)
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            let imageSize = image.size
            let imageRect = NSRect(
                x: card.midX - imageSize.width / 2,
                y: card.maxY - 92,
                width: imageSize.width,
                height: imageSize.height
            )
            image.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 0.95)
        }

        let track = NSRect(x: card.minX + 28, y: card.minY + 58, width: card.width - 56, height: 8)
        let trackPath = NSBezierPath(roundedRect: track, xRadius: 4, yRadius: 4)
        NSColor.white.withAlphaComponent(0.18).setFill()
        trackPath.fill()

        if !muted {
            var fill = track
            fill.size.width = max(8, track.width * CGFloat(level))
            let fillPath = NSBezierPath(roundedRect: fill, xRadius: 4, yRadius: 4)
            NSColor.white.withAlphaComponent(0.92).setFill()
            fillPath.fill()
        }

        let percent = muted ? "Muted" : "\(Int((level * 100).rounded()))%"
        let text = NSAttributedString(
            string: percent,
            attributes: [
                .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
                .foregroundColor: NSColor.white.withAlphaComponent(0.92)
            ]
        )
        let textSize = text.size()
        text.draw(at: NSPoint(
            x: card.midX - textSize.width / 2,
            y: card.minY + 28
        ))
    }
}
