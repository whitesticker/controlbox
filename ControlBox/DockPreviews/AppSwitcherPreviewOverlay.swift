import AppKit
import ControlBoxCore
import QuartzCore
import SwiftUI

@MainActor
final class AppSwitcherPreviewOverlay {
    static let shared = AppSwitcherPreviewOverlay()

    private var panel: NSPanel?
    private var host: NSHostingView<AppSwitcherPreviewPanelView>?
    private let model = DockPreviewModel()
    private var captureToken = 0
    private var lastHover: AppSwitcherPreviewHover?
    var cardScale = DockPreview.defaultCardScale {
        didSet {
            let next = min(max(cardScale, DockPreview.minCardScale), DockPreview.maxSwitcherCardScale)
            if abs(next - cardScale) > 0.0001 {
                cardScale = next
                return
            }
            model.cardScale = next
            if let lastHover {
                show(lastHover)
            }
        }
    }

    func show(_ hover: AppSwitcherPreviewHover) {
        captureToken += 1
        let switched = model.hover?.bundleID != hover.bundleID
        model.hover = DockPreviewHover(
            bundleID: hover.bundleID,
            appName: hover.appName,
            appIcon: hover.appIcon,
            iconFrame: .zero,
            edge: .bottom,
            windows: hover.windows
        )
        lastHover = hover
        model.cardScale = cardScale
        if switched {
            model.thumbnails = [:]
        }
        let size = panelSize(windows: hover.windows)
        let frame = placedFrame(size: size, switcher: hover.switcherFrame)
        let panel = ensurePanel(size: size)
        panel.setFrame(frame, display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        if switched || model.thumbnails.isEmpty {
            capture(hover)
        }
    }

    func hide() {
        captureToken += 1
        lastHover = nil
        model.hover = nil
        model.thumbnails = [:]
        panel?.orderOut(nil)
    }

    private func ensurePanel(size: CGSize) -> NSPanel {
        if let panel {
            host?.frame = CGRect(origin: .zero, size: size)
            return panel
        }
        let hosting = NSHostingView(rootView: AppSwitcherPreviewPanelView(model: model))
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        let chrome = DockPreviewChrome(hosting: hosting)
        chrome.frame = CGRect(origin: .zero, size: size)
        let next = NSPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        next.title = AppSwitcherPreview.overlayTitle
        next.isFloatingPanel = true
        next.becomesKeyOnlyIfNeeded = true
        next.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) + 2)
        next.isOpaque = false
        next.backgroundColor = .clear
        next.hasShadow = false
        next.hidesOnDeactivate = false
        next.animationBehavior = .none
        next.isExcludedFromWindowsMenu = true
        next.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        next.ignoresMouseEvents = false
        next.contentView = chrome
        panel = next
        host = hosting
        return next
    }

    private func capture(_ hover: AppSwitcherPreviewHover) {
        captureToken += 1
        let token = captureToken
        let windows = hover.windows
        let width = max(220 * cardScale, 280)
        Task {
            let images = await DockPreview.thumbnails(for: windows, maxPixelWidth: width)
            await MainActor.run {
                guard token == self.captureToken, self.model.hover?.bundleID == hover.bundleID else { return }
                self.model.thumbnails = images
            }
        }
    }

    private func panelSize(windows: [DockPreviewWindow]) -> CGSize {
        let height = DockPreviewCardMetrics.thumbHeight(scale: cardScale)
        let widths = windows.map { DockPreviewCardMetrics.width(for: $0, scale: cardScale) }
        let visible = Array(widths.prefix(5))
        let row = visible.reduce(0, +) + CGFloat(max(visible.count - 1, 0)) * 8
        return CGSize(width: 24 + row, height: height + 24)
    }

    private func placedFrame(size: CGSize, switcher: CGRect) -> CGRect {
        let full = mainScreen?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let switcherOnMain = switcher.width > 40 && switcher.height > 20 && full.intersects(switcher)
        let gapBottom = switcherOnMain ? switcher.maxY : full.midY
        var origin = CGPoint(
            x: (switcherOnMain ? switcher.midX : full.midX) - size.width / 2,
            y: (gapBottom + full.maxY) / 2 - size.height / 2
        )
        origin.x = min(max(origin.x, full.minX + 8), max(full.minX + 8, full.maxX - size.width - 8))
        origin.y = min(max(origin.y, full.minY + 8), max(full.minY + 8, full.maxY - size.height - 8))
        return CGRect(origin: origin, size: size)
    }

    private var mainScreen: NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return CGDisplayIsMain(number.uint32Value) != 0
        } ?? NSScreen.screens.first
    }
}

struct AppSwitcherPreviewPanelView: View {
    @ObservedObject var model: DockPreviewModel

    var body: some View {
        Group {
            if let hover = model.hover {
                ScrollView(.horizontal, showsIndicators: hover.windows.count > 4) {
                    HStack(spacing: 8) {
                        ForEach(hover.windows) { window in
                            DockPreviewCard(
                                window: window,
                                appIcon: hover.appIcon,
                                model: model,
                                compact: true
                            )
                        }
                    }
                }
                .padding(12)
            }
        }
    }
}
