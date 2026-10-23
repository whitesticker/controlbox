import AppKit
import Combine
import SwiftUI

/// A real status item: metric → detail submenu → History → the panel, so
/// hover, clicks, and resizing are tested inside a live `NSMenu`.
final class MenuBarPreview: NSObject, NSMenuDelegate {
    private let store: LabStore
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var hosts: [FittingHostingView] = []
    private var metricForMenu: [ObjectIdentifier: Metric] = [:]
    private var openMenus = 0
    private var cancellable: AnyCancellable?

    init(store: LabStore) {
        self.store = store
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "chart.xyaxis.line", accessibilityDescription: "HistoryLab")

        let menu = NSMenu()
        menu.delegate = self
        let note = NSMenuItem(title: "HistoryLab preview", action: nil, keyEquivalent: "")
        note.isEnabled = false
        menu.addItem(note)
        menu.addItem(.separator())
        for metric in Metric.allCases {
            let item = NSMenuItem(title: metric.title, action: nil, keyEquivalent: "")
            item.image = NSImage(systemSymbolName: metric.systemImage, accessibilityDescription: nil)
            item.submenu = detailMenu(metric)
            menu.addItem(item)
        }
        statusItem.menu = menu

        cancellable = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.fitAll() }
        }
    }

    private func detailMenu(_ metric: Metric) -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(.separator())

        let graph = hostItem(DetailGraphMock(metric: metric))
        let panelMenu = NSMenu()
        panelMenu.delegate = self
        panelMenu.addItem(hostItem(LiveHistoryPanel()))
        graph.submenu = panelMenu
        menu.addItem(graph)

        menu.addItem(hostItem(DetailListMock()))

        metricForMenu[ObjectIdentifier(menu)] = metric
        metricForMenu[ObjectIdentifier(panelMenu)] = metric
        return menu
    }

    private func hostItem<Content: View>(_ content: Content) -> NSMenuItem {
        let host = FittingHostingView(rootView: AnyView(content.environmentObject(store)))
        host.fit()
        hosts.append(host)
        let item = NSMenuItem()
        item.view = host
        return item
    }

    private func fitAll() {
        hosts.forEach { $0.fit(relayout: openMenus > 0) }
    }

    func menuWillOpen(_ menu: NSMenu) {
        openMenus += 1
        if let metric = metricForMenu[ObjectIdentifier(menu)], store.metric != metric {
            store.metric = metric
        }
        fitAll()
    }

    func menuDidClose(_ menu: NSMenu) {
        openMenus = max(openMenus - 1, 0)
    }
}

/// Same sizing rule as Control Box's `MenuHostingView`: size to fit, and
/// re-show the item after a resize so an open status menu re-lays out.
final class FittingHostingView: NSHostingView<AnyView> {
    private var fitPending = false

    override func layout() {
        super.layout()
        guard !fitPending else { return }
        fitPending = true
        DispatchQueue.main.async { [weak self] in
            self?.fitPending = false
            self?.fit(relayout: true)
        }
    }

    func fit(relayout: Bool = false) {
        layoutSubtreeIfNeeded()
        let fitting = fittingSize
        guard fitting.height > 0,
              abs(fitting.height - frame.height) > 0.5 || abs(fitting.width - frame.width) > 0.5
        else { return }
        frame = NSRect(origin: .zero, size: fitting)
        if relayout, let item = enclosingMenuItem, !item.isHidden {
            item.isHidden = true
            item.isHidden = false
        }
    }
}
