import AppKit
import Foundation
import QuartzCore

enum VolumeHUD {
    static func show(level: Double) {
        FeedbackHUD.show(.volume(min(max(level, 0), 1)))
    }
}

enum ActionHUD {
    static func show(_ action: ControlAction) {
        guard action.showsActionHUD, let symbol = action.actionHUDSymbol else { return }
        FeedbackHUD.show(.action(symbol: symbol, title: action.title))
    }
}

private enum FeedbackHUD {
    enum Content {
        case volume(Double)
        case action(symbol: String, title: String)
    }

    static func show(_ content: Content) {
        if Thread.isMainThread {
            Controller.shared.show(content)
        } else {
            DispatchQueue.main.async {
                Controller.shared.show(content)
            }
        }
    }

    private final class Controller {
        static let shared = Controller()

        private var window: HUDWindow?
        private var hideWork: DispatchWorkItem?

        func show(_ content: Content) {
            if window == nil {
                window = HUDWindow()
            }
            window?.update(content)

            hideWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.window?.hide()
            }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.25, execute: work)
        }
    }
}

private final class HUDWindow {
    private let panel: NSPanel
    private let content: HUDContentView
    private var appearanceObserver: NSKeyValueObservation?

    init() {
        content = HUDContentView(frame: NSRect(origin: .zero, size: HUDContentView.preferredSize))
        let chrome = GlassChromeView(content: content)
        let margin: CGFloat = 12
        let chromeSize = HUDContentView.preferredSize
        let frame = NSRect(
            x: 0,
            y: 0,
            width: chromeSize.width + margin * 2,
            height: chromeSize.height + margin * 2
        )
        chrome.frame = NSRect(x: margin, y: margin, width: chromeSize.width, height: chromeSize.height)

        panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let root = NSView(frame: frame)
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.clear.cgColor
        root.addSubview(chrome)
        panel.contentView = root
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
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
        root.setAccessibilityElement(false)
        syncAppearance()
        appearanceObserver = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            self?.syncAppearance()
        }
    }

    func update(_ content: FeedbackHUD.Content) {
        syncAppearance()
        self.content.apply(content)
        let size = panel.frame.size
        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let origin = NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.minY + frame.height * 0.22
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        let appearing = !panel.isVisible || panel.alphaValue < 0.95
        if appearing {
            panel.alphaValue = 0
        }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = appearing ? 0.2 : 0.08
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.panel.alphaValue < 0.05 else { return }
            self.panel.orderOut(nil)
        })
    }

    func orderOut(_ sender: Any?) {
        hide()
    }

    private func syncAppearance() {
        panel.appearance = NSApp.effectiveAppearance
    }
}

/// Liquid Glass on macOS 26; HUD material fallback on older systems.
private final class GlassChromeView: NSView {
    init(content: HUDContentView) {
        super.init(frame: NSRect(origin: .zero, size: HUDContentView.preferredSize))
        translatesAutoresizingMaskIntoConstraints = true
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.widthAnchor.constraint(equalToConstant: HUDContentView.preferredSize.width),
            content.heightAnchor.constraint(equalToConstant: HUDContentView.preferredSize.height)
        ])

        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: bounds)
            glass.autoresizingMask = [.width, .height]
            glass.cornerRadius = 28
            glass.style = .regular
            glass.contentView = content
            addSubview(glass)
        } else {
            let visual = NSVisualEffectView(frame: bounds)
            visual.autoresizingMask = [.width, .height]
            visual.material = .hudWindow
            visual.blendingMode = .behindWindow
            visual.state = .active
            visual.wantsLayer = true
            visual.layer?.cornerRadius = 28
            visual.layer?.cornerCurve = .continuous
            visual.layer?.masksToBounds = true
            visual.addSubview(content)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: visual.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: visual.trailingAnchor),
                content.topAnchor.constraint(equalTo: visual.topAnchor),
                content.bottomAnchor.constraint(equalTo: visual.bottomAnchor)
            ])
            addSubview(visual)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}

private final class HUDContentView: NSView {
    static let preferredSize = NSSize(width: 220, height: 214)

    private let imageView = NSImageView()
    private let caption = NSTextField(labelWithString: "")
    private let track = VolumeTrackView()
    private var content: FeedbackHUD.Content = .volume(0)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        imageView.imageScaling = .scaleProportionallyDown
        imageView.imageAlignment = .alignCenter

        caption.font = .systemFont(ofSize: 15, weight: .semibold)
        caption.textColor = .labelColor
        caption.alignment = .center
        caption.lineBreakMode = .byTruncatingTail
        caption.maximumNumberOfLines = 1

        addSubview(imageView)
        addSubview(track)
        addSubview(caption)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func apply(_ content: FeedbackHUD.Content) {
        self.content = content
        switch content {
        case .volume(let level):
            let muted = level < 0.001
            let symbol: String
            if muted {
                symbol = "speaker.slash.fill"
            } else if level < 0.34 {
                symbol = "speaker.wave.1.fill"
            } else if level < 0.67 {
                symbol = "speaker.wave.2.fill"
            } else {
                symbol = "speaker.wave.3.fill"
            }
            caption.stringValue = muted ? "Muted" : "\(Int((level * 100).rounded()))%"
            setSymbol(symbol)
            track.level = level
            track.isMuted = muted
            track.isHidden = false
        case .action(let symbol, let title):
            caption.stringValue = title
            setSymbol(symbol)
            track.isHidden = true
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let card = bounds
        switch content {
        case .volume:
            imageView.frame = NSRect(x: card.minX + 20, y: card.maxY - 100, width: card.width - 40, height: 64)
            track.frame = NSRect(x: card.minX + 32, y: card.minY + 58, width: card.width - 64, height: 7)
            caption.frame = NSRect(x: card.minX + 16, y: card.minY + 26, width: card.width - 32, height: 22)
        case .action:
            imageView.frame = NSRect(x: card.minX + 20, y: card.midY - 4, width: card.width - 40, height: 64)
            caption.frame = NSRect(x: card.minX + 16, y: card.minY + 34, width: card.width - 32, height: 22)
        }
    }

    private func setSymbol(_ name: String) {
        let config = NSImage.SymbolConfiguration(pointSize: 52, weight: .medium)
            .applying(.init(hierarchicalColor: .labelColor))
        imageView.symbolConfiguration = config
        imageView.contentTintColor = .labelColor
        imageView.image = NSImage(systemSymbolName: name, accessibilityDescription: caption.stringValue)
    }
}

private final class VolumeTrackView: NSView {
    var level: Double = 0 {
        didSet { needsDisplay = true }
    }

    var isMuted = false {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        let track = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        NSColor.quaternaryLabelColor.setFill()
        track.fill()

        guard !isMuted else { return }
        var fill = bounds
        fill.size.width = max(bounds.height, bounds.width * CGFloat(level))
        let fillPath = NSBezierPath(roundedRect: fill, xRadius: radius, yRadius: radius)
        NSColor.labelColor.setFill()
        fillPath.fill()
    }
}
