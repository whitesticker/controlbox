import AppKit
import CoreGraphics
import Foundation

enum WindowThrowOverlay {
    static let windowTitle = "Control Box Throw"

    static func show(quartzVisible: CGRect, zone: ThrowZone) {
        if Thread.isMainThread {
            Controller.shared.show(quartzVisible: quartzVisible, zone: zone)
        } else {
            DispatchQueue.main.async {
                Controller.shared.show(quartzVisible: quartzVisible, zone: zone)
            }
        }
    }

    static func hide() {
        if Thread.isMainThread {
            Controller.shared.hide()
        } else {
            DispatchQueue.main.async {
                Controller.shared.hide()
            }
        }
    }

    private final class Controller {
        static let shared = Controller()

        private var panel: NSPanel?
        private var grid: ThrowGridView?

        func show(quartzVisible: CGRect, zone: ThrowZone) {
            let cocoa = WindowLayout.cocoaFrame(from: quartzVisible)
            if let panel, let grid {
                if !panel.frame.equalTo(cocoa) {
                    panel.setFrame(cocoa, display: true)
                }
                grid.zone = zone
                if !panel.isVisible {
                    panel.orderFrontRegardless()
                }
                return
            }
            let gridView = ThrowGridView(frame: CGRect(origin: .zero, size: cocoa.size))
            gridView.zone = zone
            let next = NSPanel(
                contentRect: cocoa,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            next.title = WindowThrowOverlay.windowTitle
            next.isFloatingPanel = true
            next.level = .statusBar
            next.isOpaque = false
            next.backgroundColor = .clear
            next.hasShadow = false
            next.ignoresMouseEvents = true
            next.hidesOnDeactivate = false
            next.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            next.contentView = gridView
            next.orderFrontRegardless()
            panel = next
            grid = gridView
        }

        func hide() {
            panel?.orderOut(nil)
            panel = nil
            grid = nil
        }
    }
}

private final class ThrowGridView: NSView {
    var zone: ThrowZone = .maximize {
        didSet {
            if zone != oldValue {
                needsDisplay = true
            }
        }
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds
        let width = bounds.width / 3
        let height = bounds.height / 3
        for row in 0..<3 {
            for column in 0..<3 {
                let cell = ThrowZone.cell(column: column, row: row)
                let cocoaRow = 2 - row
                let rect = CGRect(
                    x: CGFloat(column) * width,
                    y: CGFloat(cocoaRow) * height,
                    width: width,
                    height: height
                ).insetBy(dx: 4, dy: 4)
                let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
                if cell == zone {
                    NSColor.white.withAlphaComponent(0.28).setFill()
                    NSColor.white.withAlphaComponent(0.9).setStroke()
                } else {
                    NSColor.black.withAlphaComponent(0.32).setFill()
                    NSColor.white.withAlphaComponent(0.2).setStroke()
                }
                path.lineWidth = 1.5
                path.fill()
                path.stroke()
            }
        }
    }
}
