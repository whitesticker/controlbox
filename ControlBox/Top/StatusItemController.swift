import AppKit
import SwiftUI
import Combine

// Owns the NSStatusItem: keeps the menu bar icon in sync with the latest
// network speeds, and shows the dashboard as a genuine NSMenu (not an
// NSPopover) -- one row per metric, each a real NSMenuItem with a native
// `.submenu` for its detail view. See MenuRows.swift and MetricDetails.swift.
//
// The menu (and every row's NSHostingView) is built exactly once here and
// reused for the extra's lifetime; it is never rebuilt on each click.
// Rebuilding a SwiftUI-backed NSMenuItem repeatedly is a known source of
// memory leaks (FB7539293). Metric rows are reorderable/hideable: each
// row's NSMenuItem is built once, kept in `rowItems`, and `applyRowOrder()`
// re-inserts those existing items. Does not quit Control Box.
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let monitor: SystemMonitor
    private let menu = NSMenu()
    private var rowHostingViews: [NSHostingView<AnyView>] = []
    private var detailSubmenus: [DetailSubmenu] = []
    private var rowItems: [MetricRow: NSMenuItem] = [:]
    private var rowInsertionIndex = 0
    private var cancellable: AnyCancellable?
    private var preferencesCancellable: AnyCancellable?

    init(monitor: SystemMonitor) {
        self.monitor = monitor
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        super.init()

        menu.delegate = self

        // Leading separator absorbs NSMenu's own top-inset chrome (its
        // rounded-corner chrome otherwise clips the top of the first row).
        menu.addItem(.separator())
        menu.addItem(plainRow(DateRow().environmentObject(monitor)))
        menu.addItem(.separator())
        // Metric rows are inserted here by applyRowOrder(); this index
        // never moves since nothing before it ever changes.
        rowInsertionIndex = menu.items.count

        rowItems[.cpu] = detailRow(CPURow().environmentObject(monitor)) {
            CPUDetailStandalone().environmentObject(monitor)
        }
        rowItems[.gpu] = detailRow(GPURow().environmentObject(monitor)) {
            GPUDetailStandalone().environmentObject(monitor)
        }
        rowItems[.memory] = detailRow(MemoryRow().environmentObject(monitor)) {
            MemoryDetailStandalone().environmentObject(monitor)
        }
        rowItems[.network] = detailRow(NetworkRow().environmentObject(monitor)) {
            NetworkDetailStandalone().environmentObject(monitor)
        }
        rowItems[.disk] = detailRow(DiskRow().environmentObject(monitor)) {
            DiskDetailStandalone().environmentObject(monitor)
        }
        rowItems[.sensors] = detailRow(SensorsRow().environmentObject(monitor)) {
            SensorsDetailStandalone().environmentObject(monitor)
        }
        rowItems[.battery] = detailRow(PowerRow().environmentObject(monitor)) {
            PowerDetailStandalone().environmentObject(monitor)
        }

        menu.addItem(.separator())
        let openItem = NSMenuItem(title: "Open Control Box…", action: #selector(openControlBox), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let hideItem = NSMenuItem(title: "Hide from Menu Bar", action: #selector(hideFromMenuBar), keyEquivalent: "")
        hideItem.target = self
        menu.addItem(hideItem)

        applyRowOrder()
        preferencesCancellable = PreferencesStore.shared.$rowOrder
            .combineLatest(PreferencesStore.shared.$hiddenRows)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.applyRowOrder() }

        statusItem.menu = menu

        if let button = statusItem.button {
            button.imagePosition = .imageOnly
        }

        cancellable = monitor.$snapshot
            .map(\.network)
            .receive(on: RunLoop.main)
            .sink { [weak self] net in self?.updateIcon(net) }

        updateIcon(monitor.snapshot.network)
    }

    /// Builds a plain row (no submenu) -- used only for the date/time row.
    private func plainRow<V: View>(_ view: V) -> NSMenuItem {
        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.frame = NSRect(x: 0, y: 0, width: 300, height: 100)
        warmUp(hosting)
        rowHostingViews.append(hosting)

        let item = NSMenuItem()
        item.view = hosting
        return item
    }

    /// Builds a row with a native cascading `.submenu` for its detail view.
    private func detailRow<V: View, D: View>(_ view: V, @ViewBuilder detail: @escaping () -> D) -> NSMenuItem {
        let item = plainRow(view)
        let submenu = DetailSubmenu(content: detail)
        detailSubmenus.append(submenu)
        item.submenu = submenu.menu
        return item
    }

    // Re-inserts the (already-built, never-recreated) metric row items into
    // `menu` in whatever order/visibility Preferences currently specifies.
    private func applyRowOrder() {
        for item in rowItems.values where menu.items.contains(item) {
            menu.removeItem(item)
        }
        for (offset, row) in PreferencesStore.shared.visibleRowsInOrder.enumerated() {
            guard let item = rowItems[row] else { continue }
            menu.insertItem(item, at: rowInsertionIndex + offset)
        }
    }

    // Forces one real SwiftUI layout pass immediately (via a throwaway
    // offscreen window), so `fittingSize` is already trustworthy the very
    // first time this menu opens -- without this, the first open or two
    // can read a wrong (too-short) `fittingSize` in `menuWillOpen` and clip
    // the row's content, since the view has never been part of any real
    // window before that point.
    private func warmUp(_ hosting: NSHostingView<AnyView>) {
        let warmupWindow = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        warmupWindow.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        let fitting = hosting.fittingSize
        if fitting.height > 0 {
            hosting.frame = NSRect(origin: .zero, size: fitting)
        }
        warmupWindow.contentView = nil
    }

    // Refines every row's frame to its real SwiftUI-measured size right
    // before the menu displays. `layoutSubtreeIfNeeded()` matters here, not
    // just at construction: several rows render entirely different content
    // depending on live data (e.g. Battery's "no battery" one-liner vs. its
    // full percentage+bar+stat-grid layout once real PowerMonitor data
    // arrives; same for GPU's "n/a" fallback). `StatusItemController` is
    // built *before* `monitor.start()` runs, so `warmUp()`'s very first
    // measurement can bake in the shorter placeholder branch's size. Without
    // forcing a fresh layout pass here too, `fittingSize` can keep reporting
    // that stale (too-short) measurement for the first several opens, until
    // SwiftUI's own async update pipeline happens to catch up on its own --
    // matching the reported "battery tile doesn't load right the first
    // couple times" bug. Forcing layout before every measurement, not just
    // the first, makes every open correct instead of relying on that race.
    func menuWillOpen(_ menu: NSMenu) {
        for hosting in rowHostingViews {
            hosting.layoutSubtreeIfNeeded()
            let fitting = hosting.fittingSize
            guard fitting.height > 0 else { continue }
            hosting.frame = NSRect(origin: .zero, size: fitting)
        }
    }

    private func updateIcon(_ net: NetworkSample) {
        statusItem.button?.image = NetworkIconRenderer.render(
            up: net.upBytesPerSec, down: net.downBytesPerSec)
    }

    func invalidate() {
        cancellable?.cancel()
        cancellable = nil
        preferencesCancellable?.cancel()
        preferencesCancellable = nil
        statusItem.menu = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @MainActor
    @objc private func openControlBox() {
        TopNavigation.openSystemMonitorPane()
    }

    @objc private func hideFromMenuBar() {
        PreferencesStore.shared.menuBarEnabled = false
    }
}
