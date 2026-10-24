import AppKit
import SwiftUI

// The System Monitor dropdown and its submenus are borderless panels, not an
// NSMenu. NSMenu opens a submenu from a timer about 200 ms after its row
// highlights, and moves the custom view into a fresh menu window on every
// open; neither is configurable. Here each row tracks the mouse itself and
// each submenu is a prebuilt panel that stays laid out, so switching rows is
// one window out and one in (about 5 ms). iStat Menus does the same.
// See dev/system-monitor-menu-lag-and-gaps.md.

/// A borderless, non-activating panel with menu chrome (Liquid Glass on
/// macOS 26). Its content view's frame is authoritative: the panel follows
/// it through `place` / `setSize`, anchored at the top.
final class MenuPanel: NSPanel {
    private let content: NSView
    /// The pointer entered this panel.
    var onPointerEnter: (() -> Void)?

    init(content: NSView) {
        self.content = content
        let size = content.frame.size
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .popUpMenu
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear
        hidesOnDeactivate = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        let holder = MenuPanelContent(frame: NSRect(origin: .zero, size: size))
        holder.autoresizingMask = [.width, .height]
        content.frame.origin = .zero
        holder.addSubview(content)
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: holder.frame)
            glass.cornerRadius = 12
            glass.contentView = holder
            contentView = glass
        } else {
            let visual = NSVisualEffectView(frame: holder.frame)
            visual.material = .menu
            visual.blendingMode = .behindWindow
            visual.state = .active
            visual.wantsLayer = true
            visual.layer?.cornerRadius = 10
            visual.layer?.cornerCurve = .continuous
            visual.layer?.masksToBounds = true
            visual.addSubview(holder)
            contentView = visual
        }
    }

    override var canBecomeKey: Bool { true }

    // While key, macOS 26 draws a square rim over a borderless glass window
    // (a box around the rounded panel). SwiftUI's MenuBarExtraWindow
    // overrides these same AppKit hooks. See dev/glass-panel-square-box.md.
    @objc func _hasActiveAppearance() -> Bool { false }
    @objc func _hasActiveControls() -> Bool { true }

    func place(topLeft: NSPoint) {
        let size = content.frame.size
        setFrame(NSRect(x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height), display: false)
    }

    /// Follows the content's size, keeping the top edge (and the right edge
    /// when the panel opened to the left of its parent).
    func fitContent(anchorRight: Bool = false) {
        let size = content.frame.size
        guard size != frame.size else { return }
        var next = frame
        next.origin.y = frame.maxY - size.height
        if anchorRight { next.origin.x = frame.maxX - size.width }
        next.size = size
        setFrame(next, display: true)
    }
}

/// Flipped, so content sits at the top-left. Makes its panel key when the
/// pointer enters, so SwiftUI hover and Escape work in whichever panel the
/// pointer is over without activating Control Box, and reports the entry.
private final class MenuPanelContent: NSView {
    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        if window?.isKeyWindow == false { window?.makeKey() }
        (window as? MenuPanel)?.onPointerEnter?()
    }
}

/// One dropdown row. Reports the pointer on the first enter or move, which
/// is what makes the submenu switch immediately.
final class MenuPanelRow: NSView {
    let content: NSView
    var onHover: (() -> Void)?

    init(content: NSView) {
        self.content = content
        super.init(frame: NSRect(origin: .zero, size: content.frame.size))
        content.frame.origin = .zero
        addSubview(content)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { onHover?() }
    override func mouseMoved(with event: NSEvent) { onHover?() }
}

/// Stacks rows and separators top to bottom at their own heights.
final class MenuPanelStack: NSView {
    var arranged: [NSView] = [] {
        didSet {
            subviews.filter { view in !arranged.contains { $0 === view } }.forEach { $0.removeFromSuperview() }
            arranged.filter { $0.superview !== self }.forEach(addSubview)
        }
    }

    private static let inset: CGFloat = 5

    override var isFlipped: Bool { true }

    func layoutArranged() {
        var y = Self.inset
        var width: CGFloat = menuRowWidth
        for view in arranged where !view.isHidden {
            if let row = view as? MenuPanelRow {
                row.frame.size = row.content.frame.size
            }
            view.frame.origin = NSPoint(x: 0, y: y)
            y += view.frame.height
            width = max(width, view.frame.width)
        }
        setFrameSize(NSSize(width: width, height: y + Self.inset))
    }
}

/// Matches NSMenu's separator item.
final class MenuPanelSeparator: NSView {
    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: menuRowWidth, height: 11))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        NSRect(x: 12, y: floor(bounds.midY), width: bounds.width - 24, height: 1).fill()
    }
}

/// A plain menu-style command row (Hide from Menu Bar).
struct MenuPanelActionRow: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(hovering ? .white : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(hovering ? Color.accentColor : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .padding(.horizontal, 5)
        .frame(width: menuRowWidth)
    }
}
