import AppKit
import ControlBoxCore
import QuartzCore
import SwiftUI

@MainActor
final class DockPreviewOverlay {
    static let shared = DockPreviewOverlay()

    private var panel: NSPanel?
    private var host: NSHostingView<DockPreviewPanelView>?
    private let model = DockPreviewModel()
    private var captureToken = 0
    private var animationGeneration = 0
    var cardScale = DockPreview.defaultCardScale {
        didSet {
            let next = min(max(cardScale, DockPreview.minCardScale), DockPreview.maxCardScale)
            if abs(next - cardScale) > 0.0001 {
                cardScale = next
                return
            }
            model.cardScale = next
            if let hover = model.hover {
                show(hover)
            }
        }
    }

    func show(_ hover: DockPreviewHover) {
        if hover.windows.isEmpty {
            hide()
            return
        }
        animationGeneration += 1
        let switched = model.hover?.bundleID != hover.bundleID
        model.hover = hover
        model.cardScale = cardScale
        if switched {
            captureToken += 1
            model.thumbnails = [:]
        } else if model.thumbnails.keys.contains(where: { id in !hover.windows.contains(where: { $0.windowID == id }) }) {
            model.thumbnails = model.thumbnails.filter { id, _ in hover.windows.contains(where: { $0.windowID == id }) }
        }
        let size = panelSize(for: hover)
        let frame = placedFrame(size: size, icon: hover.iconFrame, edge: hover.edge)
        let panel = ensurePanel(size: size)
        let duration = DockPreview.hideAnimationDuration()
        let appearing = !panel.isVisible || panel.alphaValue < 0.9
        if appearing {
            let start = frame.offsetBy(dx: appearOffset(hover.edge).x, dy: appearOffset(hover.edge).y)
            panel.alphaValue = 0
            panel.setFrame(start, display: true)
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().alphaValue = 1
                panel.animator().setFrame(frame, display: true)
            }
        }
        DockPreview.setKeepAliveRect(
            corridor(panel: frame, icon: hover.iconFrame, edge: hover.edge),
            panelFrame: frame
        )
        if switched || model.thumbnails.isEmpty {
            capture(hover)
        }
    }

    func hide() {
        captureToken += 1
        let generation = animationGeneration
        DockPreview.setKeepAliveRect(.zero, panelFrame: .zero)
        guard let panel, panel.isVisible else {
            model.hover = nil
            model.thumbnails = [:]
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = DockPreview.hideAnimationDuration()
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            guard generation == self.animationGeneration else { return }
            self.model.hover = nil
            self.model.thumbnails = [:]
            panel.orderOut(nil)
            panel.alphaValue = 1
        })
    }

    private func ensurePanel(size: CGSize) -> NSPanel {
        if let panel {
            host?.frame = CGRect(origin: .zero, size: size)
            panel.ignoresMouseEvents = false
            return panel
        }
        let hosting = NSHostingView(rootView: DockPreviewPanelView(model: model))
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
        next.title = DockPreview.overlayTitle
        next.isFloatingPanel = true
        next.becomesKeyOnlyIfNeeded = true
        next.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.helpWindow)))
        next.isOpaque = false
        next.backgroundColor = .clear
        next.hasShadow = false
        next.hidesOnDeactivate = false
        next.animationBehavior = .none
        next.isExcludedFromWindowsMenu = true
        next.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        next.ignoresMouseEvents = false
        next.acceptsMouseMovedEvents = true
        next.contentView = chrome
        panel = next
        host = hosting
        return next
    }

    private func capture(_ hover: DockPreviewHover) {
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

    private func appearOffset(_ edge: DockPreviewEdge) -> CGPoint {
        switch edge {
        case .bottom: return CGPoint(x: 0, y: -12)
        case .top: return CGPoint(x: 0, y: 12)
        case .left: return CGPoint(x: -12, y: 0)
        case .right: return CGPoint(x: 12, y: 0)
        }
    }

    private func panelSize(for hover: DockPreviewHover) -> CGSize {
        let height = DockPreviewCardMetrics.cardHeight(scale: cardScale)
        let widths = hover.windows.map { DockPreviewCardMetrics.width(for: $0, scale: cardScale) }
        let visible = Array(widths.prefix(5))
        let row = visible.reduce(0, +) + CGFloat(max(visible.count - 1, 0)) * 8
        return CGSize(width: 24 + row, height: height + 24)
    }

    private func placedFrame(size: CGSize, icon: CGRect, edge: DockPreviewEdge) -> CGRect {
        let iconPoint = CGPoint(x: icon.midX, y: icon.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(iconPoint) }
            ?? NSScreen.screens.first { $0.frame.intersects(icon) }
            ?? NSScreen.main
        let full = screen?.frame ?? CGRect(origin: icon.origin, size: size)
        var origin = CGPoint.zero
        let clearance = DockPreview.dockClearance(icon: icon, edge: edge)
        switch edge {
        case .bottom:
            origin = CGPoint(x: icon.midX - size.width / 2, y: full.minY + clearance + 6)
        case .top:
            origin = CGPoint(x: icon.midX - size.width / 2, y: full.maxY - clearance - size.height - 6)
        case .left:
            origin = CGPoint(x: full.minX + clearance + 6, y: icon.midY - size.height / 2)
        case .right:
            origin = CGPoint(x: full.maxX - clearance - size.width - 6, y: icon.midY - size.height / 2)
        }
        origin.x = min(max(origin.x, full.minX + 8), max(full.minX + 8, full.maxX - size.width - 8))
        origin.y = min(max(origin.y, full.minY + 8), max(full.minY + 8, full.maxY - size.height - 8))
        return CGRect(origin: origin, size: size)
    }

    private func corridor(panel: CGRect, icon: CGRect, edge: DockPreviewEdge) -> CGRect {
        let gap: CGRect
        switch edge {
        case .bottom:
            gap = CGRect(
                x: icon.minX,
                y: icon.maxY,
                width: icon.width,
                height: max(panel.minY - icon.maxY, 0) + 6
            )
        case .top:
            gap = CGRect(
                x: icon.minX,
                y: min(panel.maxY, icon.minY),
                width: icon.width,
                height: max(icon.minY - panel.maxY, 0) + 6
            )
        case .left:
            gap = CGRect(
                x: icon.maxX,
                y: icon.minY,
                width: max(panel.minX - icon.maxX, 0) + 6,
                height: icon.height
            )
        case .right:
            gap = CGRect(
                x: min(panel.maxX, icon.minX),
                y: icon.minY,
                width: max(icon.minX - panel.maxX, 0) + 6,
                height: icon.height
            )
        }
        return panel.union(gap)
    }
}

final class DockPreviewChrome<Content: View>: NSView {
    init(hosting: NSHostingView<Content>) {
        super.init(frame: hosting.frame)
        autoresizingMask = [.width, .height]
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = bounds
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: bounds)
            glass.autoresizingMask = [.width, .height]
            glass.cornerRadius = 16
            glass.style = .regular
            glass.contentView = hosting
            addSubview(glass)
        } else {
            let visual = NSVisualEffectView(frame: bounds)
            visual.autoresizingMask = [.width, .height]
            visual.material = .hudWindow
            visual.blendingMode = .behindWindow
            visual.state = .active
            visual.wantsLayer = true
            visual.layer?.cornerRadius = 16
            visual.layer?.cornerCurve = .continuous
            visual.layer?.masksToBounds = true
            visual.addSubview(hosting)
            addSubview(visual)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}

@MainActor
final class DockPreviewModel: ObservableObject {
    @Published var hover: DockPreviewHover?
    @Published var thumbnails: [CGWindowID: NSImage] = [:]
    @Published var cardScale = DockPreview.defaultCardScale
}

enum DockPreviewCardMetrics {
    static let baseThumbHeight: CGFloat = 96
    static let baseCardHeight: CGFloat = 132

    static func thumbHeight(scale: CGFloat) -> CGFloat {
        baseThumbHeight * scale
    }

    static func cardHeight(scale: CGFloat) -> CGFloat {
        baseCardHeight * scale
    }

    static func width(for window: DockPreviewWindow, scale: CGFloat) -> CGFloat {
        let thumb = thumbHeight(scale: scale)
        let ratio = window.bounds.height > 1 ? window.bounds.width / window.bounds.height : 1.6
        let raw = thumb * min(max(ratio, 0.4), 2.8)
        return min(max(raw, 108 * scale), 280 * scale)
    }
}

struct DockPreviewPanelView: View {
    @ObservedObject var model: DockPreviewModel

    var body: some View {
        Group {
            if let hover = model.hover {
                content(hover).padding(12)
            }
        }
    }

    private func content(_ hover: DockPreviewHover) -> some View {
        ScrollView(.horizontal, showsIndicators: hover.windows.count > 4) {
            HStack(spacing: 8) {
                ForEach(hover.windows) { window in
                    DockPreviewCard(window: window, appIcon: hover.appIcon, model: model, compact: false)
                }
            }
        }
    }
}

struct DockPreviewCard: View {
    let window: DockPreviewWindow
    let appIcon: NSImage
    @ObservedObject var model: DockPreviewModel
    var compact = false
    @State private var hovering = false

    private var cardWidth: CGFloat { DockPreviewCardMetrics.width(for: window, scale: model.cardScale) }
    private var cardHeight: CGFloat {
        compact
            ? DockPreviewCardMetrics.thumbHeight(scale: model.cardScale)
            : DockPreviewCardMetrics.cardHeight(scale: model.cardScale)
    }
    private var thumbHeight: CGFloat { DockPreviewCardMetrics.thumbHeight(scale: model.cardScale) }
    private var iconSize: CGFloat { 42 * model.cardScale }
    private var hudButton: CGFloat { max(20, 22 * model.cardScale) }

    var body: some View {
        ZStack(alignment: .top) {
            Button {
                if compact {
                    AppSwitcherPreview.dismissSwitcher()
                    AppSwitcherPreviewOverlay.shared.hide()
                }
                DockPreview.focus(window)
                DockPreviewOverlay.shared.hide()
            } label: {
                VStack(alignment: .leading, spacing: 6 * model.cardScale) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.black.opacity(0.22))
                        if let image = model.thumbnails[window.windowID] {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFit()
                                .transition(.opacity)
                        } else {
                            Image(nsImage: appIcon)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: iconSize, height: iconSize)
                        }
                        if window.isMinimized {
                            badge("Minimized")
                        } else if !window.isOnScreen {
                            badge("Other Space")
                        }
                    }
                    .frame(height: thumbHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    if !compact {
                        Text(window.title)
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                    }
                }
                .frame(width: cardWidth, height: cardHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if hovering, showsHUD {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    hud
                }
                .frame(width: cardWidth, height: thumbHeight, alignment: .bottom)
                .offset(y: 5)
                .transition(.opacity)
            }
        }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.16), value: hovering)
        .animation(.easeOut(duration: 0.16), value: model.thumbnails[window.windowID] != nil)
    }

    private var showsHUD: Bool {
        !compact && (window.isOnScreen || window.isMinimized)
    }

    private var hud: some View {
        HStack(spacing: 5) {
            traffic(
                systemName: "xmark",
                help: "Close window",
                color: Color(red: 1, green: 0.373, blue: 0.341)
            ) {
                DockPreview.close(window)
            }
            if window.isMinimized {
                traffic(
                    systemName: "plus",
                    help: "Show window",
                    color: Color(red: 0.157, green: 0.784, blue: 0.251)
                ) {
                    DockPreview.restore(window)
                }
            } else {
                traffic(
                    systemName: "minus",
                    help: "Minimize window",
                    color: Color(red: 1, green: 0.741, blue: 0.180)
                ) {
                    DockPreview.minimize(window)
                }
            }
            traffic(
                systemName: "power",
                help: "Quit app",
                color: Color(red: 0.69, green: 0.35, blue: 0.95)
            ) {
                DockPreview.quit(window)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .modifier(DockPreviewHUDGlass())
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.black.opacity(0.55), in: Capsule())
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(6)
    }

    private func traffic(
        systemName: String,
        help: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: hudButton * 0.38, weight: .bold))
                .foregroundStyle(.black.opacity(0.62))
                .frame(width: hudButton, height: hudButton)
                .background(color.opacity(0.92), in: Circle())
                .modifier(DockPreviewHUDGlass(shape: .circle, tint: color))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct DockPreviewHUDGlass: ViewModifier {
    enum ShapeKind {
        case capsule
        case circle
    }

    var shape: ShapeKind = .capsule
    var tint: Color?

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            switch shape {
            case .capsule:
                content.glassEffect(.regular, in: Capsule())
            case .circle:
                if let tint {
                    content.glassEffect(.regular.tint(tint).interactive(), in: Circle())
                } else {
                    content.glassEffect(.regular.interactive(), in: Circle())
                }
            }
        } else if shape == .capsule {
            content.background(.ultraThinMaterial, in: Capsule())
        } else {
            content
        }
    }
}
