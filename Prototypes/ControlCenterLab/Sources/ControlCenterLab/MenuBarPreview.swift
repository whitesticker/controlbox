import AppKit
import Combine
import SwiftUI

/// Real menu bar extras: the ring opens the Control Center panel, and each
/// module with Show in Menu Bar on gets its own icon that opens its detail
/// view. Borderless glass panels, like System Monitor's `MenuPanel`.
final class MenuBarPreview {
    private let store: LabStore
    private let showLab: () -> Void
    private var ring: StatusPanelItem?
    private var extras: [ModuleKind: StatusPanelItem] = [:]
    private var cancellables: Set<AnyCancellable> = []

    init(store: LabStore, showLab: @escaping () -> Void) {
        self.store = store
        self.showLab = showLab
        ring = StatusPanelItem(store: store, accessibility: "Control Box", icon: { _ in LabIcons.ring }) { [weak self] close in
            AnyView(ControlCenterPanel(
                store: store,
                onEditControls: {
                    close()
                    store.canvasTab = .pane
                    self?.showLab()
                },
                onOpenApp: {
                    close()
                    self?.showLab()
                }
            ))
        }
        store.$extras
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.syncExtras($0) }
            .store(in: &cancellables)
    }

    private func syncExtras(_ wanted: Set<ModuleKind>) {
        for (kind, item) in extras where !wanted.contains(kind) {
            item.invalidate()
            extras[kind] = nil
        }
        let store = self.store
        for kind in ModuleKind.allCases where wanted.contains(kind) && extras[kind] == nil {
            extras[kind] = StatusPanelItem(store: store, accessibility: kind.title, icon: { current in
                guard let base = kind.assetName else { return nil }
                let filled = kind == .caffeinate && current.caffeinateActive
                return LabIcons.image("\(base)-\(filled ? "filled" : "line")")
            }) { _ in
                AnyView(ExtraPanel(store: store, kind: kind))
            }
        }
    }
}

/// One status item plus the panel it toggles.
final class StatusPanelItem: NSObject {
    private let store: LabStore
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let icon: (LabStore) -> NSImage?
    private let makeContent: (@escaping () -> Void) -> AnyView
    private var panel: LabPanel?
    private var monitors: [Any] = []
    private var cancellables: Set<AnyCancellable> = []

    init(
        store: LabStore,
        accessibility: String,
        icon: @escaping (LabStore) -> NSImage?,
        content: @escaping (@escaping () -> Void) -> AnyView
    ) {
        self.store = store
        self.icon = icon
        makeContent = content
        super.init()
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(toggle)
            button.setAccessibilityTitle(accessibility)
        }
        applyIcon()
        store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.applyIcon()
                self?.panel?.applyDesign(self?.store.design ?? .defaults)
            }
            .store(in: &cancellables)
    }

    func invalidate() {
        close()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func applyIcon() {
        let image = icon(store)?.copy() as? NSImage
        image?.isTemplate = true
        image?.size = NSSize(width: 16, height: 16)
        statusItem.button?.image = image
    }

    @objc private func toggle() {
        if panel?.isVisible == true { close() } else { open() }
    }

    private func open() {
        let content = makeContent { [weak self] in self?.close() }
        let root = AnyView(
            content
                .id(UUID())
                .environment(\.inWindowChrome, true)
                .preferredColorScheme(store.appearance == .system ? nil : (store.appearance == .dark ? .dark : .light))
        )
        let panel = self.panel ?? LabPanel(design: store.design)
        self.panel = panel
        panel.setRoot(root, animate: store.design.animateResize)
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        panel.anchor = anchor
        panel.placeUnder(anchor)
        panel.orderFrontRegardless()
        panel.makeKey()
        button.highlight(true)
        installMonitors(buttonWindow: buttonWindow)
    }

    private func close() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
        panel?.orderOut(nil)
        statusItem.button?.highlight(false)
    }

    private func installMonitors(buttonWindow: NSWindow) {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            self?.close()
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown], handler: { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53, event.window === self.panel {
                    self.close()
                    return nil
                }
                return event
            }
            if event.window !== self.panel && event.window !== buttonWindow {
                self.close()
            }
            return event
        }) {
            monitors.append(local)
        }
    }
}

/// Borderless, non-activating glass panel that follows its SwiftUI content's
/// size, keeping the top edge pinned under the status item.
final class LabPanel: NSPanel {
    private let glass = NSGlassEffectView()
    private let host = SizingHostingView(rootView: AnyView(EmptyView()))
    var anchor: NSRect?

    init(design: CCDesign) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 320, height: 200), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .popUpMenu
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear
        hidesOnDeactivate = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        host.autoresizingMask = [.width, .height]
        glass.contentView = host
        contentView = glass
        applyDesign(design)
        host.onFittingSizeChange = { [weak self] size, animate in self?.fit(size, animate: animate) }
    }

    override var canBecomeKey: Bool { true }

    func applyDesign(_ design: CCDesign) {
        glass.cornerRadius = design.panelCornerRadius
        host.animateResize = design.animateResize
    }

    func setRoot(_ root: AnyView, animate: Bool) {
        host.rootView = root
        host.layoutSubtreeIfNeeded()
        fit(host.fittingSize, animate: false)
    }

    func placeUnder(_ anchor: NSRect) {
        let size = frame.size
        let screen = NSScreen.screens.first { $0.frame.contains(anchor.origin) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        var x = anchor.maxX - size.width + 8
        x = min(max(x, visible.minX + 6), visible.maxX - size.width - 6)
        let top = anchor.minY - 6
        setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true)
    }

    private func fit(_ size: NSSize, animate: Bool) {
        guard size.width > 0, size.height > 0, size != frame.size else { return }
        var next = frame
        next.origin.y = frame.maxY - size.height
        next.origin.x = frame.maxX - size.width
        next.size = size
        if animate && isVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.24
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animator().setFrame(next, display: true)
            }
        } else {
            setFrame(next, display: true)
        }
    }
}

/// Reports its SwiftUI content's fitting size whenever it changes.
final class SizingHostingView: NSHostingView<AnyView> {
    var onFittingSizeChange: ((NSSize, Bool) -> Void)?
    var animateResize = true
    private var pending = false

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        guard !pending else { return }
        pending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            pending = false
            onFittingSizeChange?(fittingSize, animateResize)
        }
    }
}
