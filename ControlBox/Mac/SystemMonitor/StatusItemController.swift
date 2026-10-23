import AppKit
import SwiftUI
import Combine

// Owns the NSStatusItem: keeps the menu bar icon in sync with the items
// chosen in the pane (MenuBarIcon.swift), and shows the dashboard as a dropdown `MenuPanel` (not an
// NSMenu; see MenuPanel.swift) -- one row per metric, each with a detail
// submenu panel beside it. See MenuRows.swift and MetricDetails.swift.
//
// Every row's NSHostingView and every submenu panel is built exactly once
// here and reused for the extra's lifetime. Metric rows are
// reorderable/hideable: `applyRowOrder()` re-stacks the existing row views.
// Does not quit Control Box.
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let monitor: SystemMonitor
    private let stack: MenuPanelStack
    private let panel: MenuPanel
    private var rowHostingViews: [MenuHostingView] = []
    private var rowViews: [MetricRow: MenuPanelRow] = [:]
    private var topViews: [NSView] = []
    private var bottomViews: [NSView] = []
    private var launcherRow: MenuPanelRow?
    private var launcherHostingView: MenuHostingView?
    private var openSubmenu: DetailSubmenu?
    private var eventMonitors: [Any] = []
    private var spaceObserver: NSObjectProtocol?
    private var cancellable: AnyCancellable?
    private var preferencesCancellable: AnyCancellable?
    private var launcherCancellable: AnyCancellable?
    private var iconKey: String?

    init(monitor: SystemMonitor) {
        self.monitor = monitor
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let stack = MenuPanelStack()
        self.stack = stack
        panel = MenuPanel(content: stack)

        super.init()

        topViews = [row(DateRow().environmentObject(monitor)), MenuPanelSeparator()]

        rowViews[.cpu] = detailRow(CPURow().environmentObject(monitor), topProcesses: .cpu, history: [.cpu]) {
            CPUDetailStandalone().environmentObject(monitor)
        }
        rowViews[.gpu] = detailRow(GPURow().environmentObject(monitor), history: [.gpu]) {
            GPUDetailStandalone().environmentObject(monitor)
        }
        rowViews[.memory] = detailRow(MemoryRow().environmentObject(monitor), topProcesses: .memory, history: [.memory]) {
            MemoryDetailStandalone().environmentObject(monitor)
        }
        rowViews[.network] = detailRow(NetworkRow().environmentObject(monitor), topProcesses: .network, history: [.network]) {
            NetworkDetailStandalone().environmentObject(monitor)
        }
        rowViews[.disk] = detailRow(DiskRow().environmentObject(monitor), topProcesses: .disk, history: [.disk]) {
            DiskDetailStandalone().environmentObject(monitor)
        }
        let sensorsFocus = HistoryFocus(.sensorGroup(.cpu))
        rowViews[.sensors] = detailRow(
            SensorsRow().environmentObject(monitor),
            historyFeeds: [sensorsFocus.feed],
            width: SensorsDetail.width
        ) {
            SensorsDetailStandalone(focus: sensorsFocus).environmentObject(monitor)
        }
        rowViews[.battery] = detailRow(PowerRow().environmentObject(monitor), topProcesses: .energy) {
            PowerDetailStandalone().environmentObject(monitor)
        }

        let launcher = row(launcherContent(PreferencesStore.shared.launcherApps))
        launcherRow = launcher
        launcherHostingView = launcher.content as? MenuHostingView
        let hide = row(MenuPanelActionRow(title: "Hide from Menu Bar") { [weak self] in self?.hideFromMenuBar() })
        bottomViews = [launcher, MenuPanelSeparator(), hide]

        applyRowOrder()
        preferencesCancellable = PreferencesStore.shared.$rowOrder
            .combineLatest(PreferencesStore.shared.$hiddenRows)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.applyRowOrder() }
        launcherCancellable = PreferencesStore.shared.$launcherApps
            .sink { [weak self] apps in self?.applyLauncherApps(apps) }

        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(togglePanel)
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }

        cancellable = monitor.tickSnapshot
            .combineLatest(PreferencesStore.shared.$menuBarItems)
            .sink { [weak self] snapshot, items in self?.updateIcon(snapshot, items: items) }
    }

    /// A row with no submenu (date, quick launch, Hide). Hovering it closes
    /// the open submenu, as in NSMenu.
    private func row<V: View>(_ view: V) -> MenuPanelRow {
        let hosting = MenuHostingView(content: view, initialSize: NSSize(width: menuRowWidth, height: 100))
        hosting.onResize = { [weak self] in self?.relayout() }
        rowHostingViews.append(hosting)
        let row = MenuPanelRow(content: hosting)
        row.onHover = { [weak self] in self?.hover(nil, row: nil) }
        return row
    }

    private func detailRow<V: View, D: View>(
        _ view: V,
        topProcesses: TopProcessKind? = nil,
        history: [HistoryMetric] = [],
        historyFeeds: [HistoryFeed] = [],
        width: CGFloat = 260,
        @ViewBuilder detail: @escaping () -> D
    ) -> MenuPanelRow {
        let row = row(view)
        let feeds = history.map(HistoryFeed.init(metric:)) + historyFeeds
        let submenu = DetailSubmenu(topProcesses: topProcesses, history: feeds, width: width, content: detail)
        row.onHover = { [weak self, weak row] in self?.hover(submenu, row: row) }
        return row
    }

    private func launcherContent(_ apps: [String]) -> QuickLauncherRow {
        QuickLauncherRow(apps: apps) { [weak self] bundleID in
            self?.close()
            MainActor.assumeIsolated { QuickLauncher.launch(bundleID) }
        }
    }

    private func applyLauncherApps(_ apps: [String]) {
        launcherRow?.isHidden = apps.isEmpty
        launcherHostingView?.setContent(launcherContent(apps))
        relayout()
    }

    // Re-stacks the (already-built, never-recreated) metric rows in whatever
    // order/visibility Preferences currently specifies.
    private func applyRowOrder() {
        let rows = PreferencesStore.shared.visibleRowsInOrder.compactMap { rowViews[$0] }
        stack.arranged = topViews + rows + bottomViews
        relayout()
    }

    private func relayout() {
        stack.layoutArranged()
        if panel.isVisible { panel.fitContent() }
    }

    // MARK: Open / close

    @objc private func togglePanel() {
        if panel.isVisible { close() } else { open() }
    }

    /// Publishes current data first so rows measure against it, not the
    /// placeholder branches (Battery's "no battery", GPU's "n/a") that were
    /// live when the rows were built before `monitor.start()`.
    private func open() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        monitor.setPresenting(true)
        rowHostingViews.forEach { $0.isTracking = true }
        stack.layoutArranged()

        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame ?? anchor
        let width = stack.frame.width
        let x = min(max(anchor.minX, screen.minX + 4), screen.maxX - width - 4)
        panel.place(topLeft: NSPoint(x: x, y: min(anchor.minY - 1, screen.maxY)))
        panel.makeKeyAndOrderFront(nil)
        button.highlight(true)
        installMonitors()
    }

    private func close() {
        guard panel.isVisible else { return }
        removeMonitors()
        openSubmenu?.hide()
        openSubmenu = nil
        panel.orderOut(nil)
        rowHostingViews.forEach { $0.isTracking = false }
        monitor.setPresenting(false)
        statusItem.button?.highlight(false)
    }

    /// Back on the row whose submenu is open closes only its history panel.
    private func hover(_ submenu: DetailSubmenu?, row: MenuPanelRow?) {
        guard panel.isVisible else { return }
        guard openSubmenu !== submenu else {
            submenu?.hideHistory()
            return
        }
        let previous = openSubmenu
        openSubmenu = submenu
        if let submenu, let row {
            let rowFrame = panel.convertToScreen(row.convert(row.bounds, to: nil))
            submenu.show(beside: panel.frame, rowTop: rowFrame.maxY)
        }
        previous?.hide()
    }

    /// Closes on a click anywhere else (other apps, the menu bar, another
    /// Control Box window), Escape, or a Space switch.
    private func installMonitors() {
        if let monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown],
            handler: { [weak self] _ in self?.close() }
        ) {
            eventMonitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown],
            handler: { [weak self] event in
                guard let self else { return event }
                if event.type == .keyDown {
                    guard event.keyCode == 53 else { return event }
                    close()
                    return nil
                }
                let ours = event.window === panel
                    || openSubmenu?.owns(event.window) == true
                    || event.window === statusItem.button?.window
                if !ours { close() }
                return event
            }
        ) {
            eventMonitors.append(monitor)
        }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.close() }
    }

    private func removeMonitors() {
        eventMonitors.forEach(NSEvent.removeMonitor)
        eventMonitors = []
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
        }
        spaceObserver = nil
    }

    private func updateIcon(_ snapshot: SystemSnapshot?, items: [MenuBarItem]) {
        let entries = items.map { (item: $0, text: $0.text(snapshot ?? SystemSnapshot())) }
        let key = entries.map { "\($0.item.rawValue)=\($0.text)" }.joined(separator: "|")
        guard key != iconKey else { return }
        iconKey = key
        statusItem.button?.image = MenuBarIconRenderer.render(entries)
    }

    func invalidate() {
        close()
        cancellable?.cancel()
        cancellable = nil
        preferencesCancellable?.cancel()
        preferencesCancellable = nil
        launcherCancellable?.cancel()
        launcherCancellable = nil
        monitor.setPresenting(false)
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func hideFromMenuBar() {
        close()
        PreferencesStore.shared.menuBarEnabled = false
    }
}
