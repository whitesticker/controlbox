import AppKit
import Combine
import SwiftUI

// The iStat Menus approach: no NSMenu. The dropdown and every submenu are
// borderless panels; rows track the mouse themselves, so a submenu shows on
// the first mouse-moved event over its row instead of after NSMenu's own
// submenu delay. Each submenu is its own prebuilt panel, so switching rows
// only orders one window out and another in (no re-layout).

struct PanelOptions {
    enum Background: String, CaseIterable {
        case glass = "Glass"
        case material = "Menu material"
        case solid = "Solid"
    }

    var menuAim = UserDefaults.standard.bool(forKey: "panel.aim")
    var background = Background(rawValue: UserDefaults.standard.string(forKey: "panel.background") ?? "") ?? .glass
    var oneWindow = UserDefaults.standard.bool(forKey: "panel.oneWindow")

    func save() {
        UserDefaults.standard.set(menuAim, forKey: "panel.aim")
        UserDefaults.standard.set(background.rawValue, forKey: "panel.background")
        UserDefaults.standard.set(oneWindow, forKey: "panel.oneWindow")
    }
}

final class MenuPanel: NSPanel {
    private let host = NSView()

    init(content: NSView, background: PanelOptions.Background) {
        super.init(
            contentRect: NSRect(origin: .zero, size: content.frame.size),
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
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        content.frame = NSRect(origin: .zero, size: content.frame.size)
        content.autoresizingMask = [.width, .height]
        host.frame = content.frame
        host.addSubview(content)
        if background == .solid {
            let solid = NSView()
            solid.wantsLayer = true
            solid.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            solid.layer?.cornerRadius = 10
            solid.layer?.masksToBounds = true
            host.autoresizingMask = [.width, .height]
            solid.addSubview(host)
            contentView = solid
        } else if background == .glass, #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = 12
            glass.contentView = host
            contentView = glass
        } else {
            let effect = NSVisualEffectView()
            effect.material = .menu
            effect.state = .active
            effect.blendingMode = .behindWindow
            effect.wantsLayer = true
            effect.layer?.cornerRadius = 10
            effect.layer?.masksToBounds = true
            host.autoresizingMask = [.width, .height]
            effect.addSubview(host)
            contentView = effect
        }
        setContentSize(content.frame.size)
    }

    override var canBecomeKey: Bool { true }
}

/// The main rows, drawn in one view, with their own mouse tracking.
final class RowsView: NSView {
    static let rowHeight: CGFloat = 56
    let titles: [String]
    private let numbers: Numbers
    var selected: Int? { didSet { if selected != oldValue { needsDisplay = true } } }
    var onMove: ((Int?) -> Void)?

    init(titles: [String], numbers: Numbers, width: CGFloat) {
        self.titles = titles
        self.numbers = numbers
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: CGFloat(titles.count) * Self.rowHeight + 8))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseMoved(with event: NSEvent) { onMove?(row(atWindowPoint: event.locationInWindow)) }
    override func mouseEntered(with event: NSEvent) { onMove?(row(atWindowPoint: event.locationInWindow)) }

    func row(atWindowPoint point: NSPoint) -> Int? {
        let local = convert(point, from: nil)
        guard local.y >= 4, local.x >= 0, local.x <= bounds.width else { return nil }
        let index = Int((local.y - 4) / Self.rowHeight)
        return titles.indices.contains(index) ? index : nil
    }

    func rowRect(_ index: Int) -> NSRect {
        NSRect(x: 0, y: 4 + CGFloat(index) * Self.rowHeight, width: bounds.width, height: Self.rowHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.labelColor,
        ]
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 16, weight: .semibold), .foregroundColor: NSColor.labelColor,
        ]
        let chevronAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor.secondaryLabelColor,
        ]
        for (index, title) in titles.enumerated() {
            let rect = rowRect(index)
            if index == selected {
                NSColor.labelColor.withAlphaComponent(0.1).setFill()
                NSBezierPath(roundedRect: rect.insetBy(dx: 6, dy: 2), xRadius: 8, yRadius: 8).fill()
            }
            (title as NSString).draw(at: NSPoint(x: 14, y: rect.minY + 8), withAttributes: titleAttributes)
            (String(format: "%.1f%%", numbers.values[index]) as NSString)
                .draw(at: NSPoint(x: 14, y: rect.minY + 25), withAttributes: valueAttributes)
            ("›" as NSString).draw(at: NSPoint(x: rect.maxX - 22, y: rect.minY + 18), withAttributes: chevronAttributes)
        }
    }
}

final class PanelMenu: NSObject {
    private let rowsView: RowsView
    private let main: MenuPanel
    private let options: PanelOptions
    /// Separate windows: one per row. One window: `subs` is a single panel
    /// holding every row's view, and only the selected one is unhidden.
    private let subs: [MenuPanel]
    private let subViews: [NSView]
    private var aimWait: CFTimeInterval = 0
    private var selected: Int?
    private var monitors: [Any] = []
    private var lastMouse: NSPoint?
    private var rowEnteredAt: CFTimeInterval = 0
    private var hoveredRow: Int?
    private var pending: Timer?
    private var cancellable: AnyCancellable?
    private weak var button: NSStatusBarButton?
    private let report: (String, Double, Double) -> Void

    var isOpen: Bool { main.isVisible }

    init(numbers: Numbers, wide: Bool, options: PanelOptions, footer: NSView, report: @escaping (String, Double, Double) -> Void) {
        self.report = report
        self.options = options
        let width: CGFloat = 300
        rowsView = RowsView(titles: rowTitles, numbers: numbers, width: width)
        let container = FlippedView(frame: NSRect(x: 0, y: 0, width: width, height: rowsView.frame.height + footer.frame.height))
        container.addSubview(rowsView)
        footer.frame.origin = NSPoint(x: 0, y: rowsView.frame.maxY)
        container.addSubview(footer)
        main = MenuPanel(content: container, background: options.background)

        let subWidth: CGFloat = wide ? 550 : 260
        subViews = rowTitles.map { title in
            let note = Note()
            note.text = "Custom panel: no NSMenu, no submenu delay"
            let host = NSHostingView(rootView: SwiftUIDetail(title: title, numbers: numbers, note: note, width: subWidth))
            host.frame = NSRect(x: 0, y: 0, width: subWidth, height: 220)
            return host
        }
        if options.oneWindow {
            let holder = FlippedView(frame: NSRect(x: 0, y: 0, width: subWidth, height: 220))
            for view in subViews {
                view.autoresizingMask = []
                view.isHidden = true
                holder.addSubview(view)
            }
            subs = [MenuPanel(content: holder, background: options.background)]
        } else {
            subs = subViews.map { MenuPanel(content: $0, background: options.background) }
        }
        super.init()
        rowsView.onMove = { [weak self] row in self?.handleMove(row) }
        cancellable = numbers.$values.sink { [weak self] _ in
            DispatchQueue.main.async { self?.rowsView.needsDisplay = true }
        }
    }

    func toggle(from button: NSStatusBarButton) {
        if isOpen { close() } else { open(from: button) }
    }

    private func open(from button: NSStatusBarButton) {
        self.button = button
        guard let buttonWindow = button.window else { return }
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let size = main.frame.size
        let x = min(max(anchor.minX, screen.minX + 4), screen.maxX - size.width - 4)
        main.setFrameOrigin(NSPoint(x: x, y: anchor.minY - size.height - 4))
        main.makeKeyAndOrderFront(nil)
        button.highlight(true)

        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            self?.close()
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 { close(); return nil }
                return event
            }
            let ours = event.window === main || subs.contains { $0 === event.window } || event.window === button.window
            if !ours { close() }
            return event
        } as Any)
    }

    func close() {
        pending?.invalidate()
        pending = nil
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        subs.forEach { $0.orderOut(nil) }
        main.orderOut(nil)
        selected = nil
        hoveredRow = nil
        lastMouse = nil
        rowsView.selected = nil
        button?.highlight(false)
    }

    private func handleMove(_ row: Int?) {
        let mouse = NSEvent.mouseLocation
        defer { lastMouse = mouse }
        if row != hoveredRow {
            hoveredRow = row
            rowEnteredAt = CACurrentMediaTime()
        }
        guard let row else { return }
        guard row != selected else {
            pending?.invalidate()
            pending = nil
            return
        }
        if options.menuAim, let selected, let last = lastMouse, movingToward(window(for: selected).frame, from: last, to: mouse) {
            if pending == nil {
                aimWait = CACurrentMediaTime()
                let timer = Timer(timeInterval: 0.15, repeats: false) { [weak self] _ in
                    guard let self else { return }
                    pending = nil
                    if let row = rowsView.row(atWindowPoint: main.convertPoint(fromScreen: NSEvent.mouseLocation)),
                       row != self.selected {
                        select(row)
                    }
                }
                RunLoop.main.add(timer, forMode: .common)
                pending = timer
            }
            return
        }
        select(row)
    }

    /// Inside the triangle from the previous pointer position to the open
    /// submenu's near edge: the user is heading for the submenu across
    /// other rows, so do not switch yet.
    private func movingToward(_ target: NSRect, from a: NSPoint, to p: NSPoint) -> Bool {
        let nearX = target.midX < main.frame.midX ? target.maxX : target.minX
        let b = NSPoint(x: nearX, y: target.maxY)
        let c = NSPoint(x: nearX, y: target.minY)
        func side(_ p1: NSPoint, _ p2: NSPoint, _ p3: NSPoint) -> CGFloat {
            (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y)
        }
        let d1 = side(p, a, b), d2 = side(p, b, c), d3 = side(p, c, a)
        let hasNegative = d1 < 0 || d2 < 0 || d3 < 0
        let hasPositive = d1 > 0 || d2 > 0 || d3 > 0
        return !(hasNegative && hasPositive)
    }

    private func window(for row: Int) -> MenuPanel {
        options.oneWindow ? subs[0] : subs[row]
    }

    private func select(_ row: Int) {
        let waited = pending == nil ? 0 : CACurrentMediaTime() - aimWait
        pending?.invalidate()
        pending = nil
        let previous = selected
        selected = row
        rowsView.selected = row

        let sub = window(for: row)
        if options.oneWindow {
            for (index, view) in subViews.enumerated() { view.isHidden = index != row }
        }
        let size = sub.frame.size
        let rowRect = main.convertToScreen(rowsView.convert(rowsView.rowRect(row), to: nil))
        let screen = (main.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let roomLeft = main.frame.minX - size.width >= screen.minX
        let roomRight = main.frame.maxX + size.width <= screen.maxX
        let openLeft = main.frame.midX > screen.midX ? roomLeft : !roomRight
        let x = openLeft ? main.frame.minX - size.width + 2 : main.frame.maxX - 2
        let y = max(rowRect.maxY - size.height + 6, screen.minY)
        sub.setFrameOrigin(NSPoint(x: x, y: y))
        if !sub.isVisible { sub.orderFront(nil) }
        if !options.oneWindow, let previous, previous != row { subs[previous].orderOut(nil) }

        let entered = rowEnteredAt
        DispatchQueue.main.async { [weak self] in
            let now = CACurrentMediaTime()
            self?.report(rowTitles[row], now - entered, waited)
        }
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
