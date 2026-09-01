import AppKit
import Observation
import SwiftUI

/// Owns the Caffeinate menu bar extra. Separate from the Control Box ring
/// and from Brightness / Sound / System Monitor. Off until the pane toggle is on.
@MainActor
final class CaffeinateMenuBarHost {
    static let shared = CaffeinateMenuBarHost()

    private var catalog: CaffeinateCatalog?
    private var item: CaffeinateMenuBarItem?

    private init() {}

    func start(catalog: CaffeinateCatalog) {
        self.catalog = catalog
        apply()
    }

    func stop() {
        item?.invalidate()
        item = nil
        catalog = nil
    }

    func apply() {
        if AppSettings.shared.caffeinateMenuBarEnabled, let catalog {
            if item == nil {
                item = CaffeinateMenuBarItem(catalog: catalog)
            }
        } else {
            item?.invalidate()
            item = nil
        }
    }
}

/// Native duration menu. Hide does not quit. While a session is on, the first
/// row is a live countdown (1 s only while the menu is open).
@MainActor
private final class CaffeinateMenuBarItem: NSObject, NSMenuDelegate {
    private let catalog: CaffeinateCatalog
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let countdownItem = NSMenuItem()
    private let turnOffItem = NSMenuItem(title: "Turn Off", action: #selector(turnOff), keyEquivalent: "")
    private var durationItems: [CaffeinateDuration: NSMenuItem] = [:]
    private var countdownTimer: Timer?

    init(catalog: CaffeinateCatalog) {
        self.catalog = catalog
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        menu.delegate = self
        menu.autoenablesItems = false

        countdownItem.isEnabled = false
        menu.addItem(countdownItem)
        menu.addItem(.separator())

        for duration in CaffeinateDuration.allCases {
            let item = NSMenuItem(title: duration.title, action: #selector(chooseDuration(_:)), keyEquivalent: "")
            item.target = self
            item.tag = duration.rawValue
            item.representedObject = duration.rawValue
            durationItems[duration] = item
            menu.addItem(item)
        }

        menu.addItem(.separator())
        turnOffItem.target = self
        menu.addItem(turnOffItem)
        menu.addItem(.separator())

        let openItem = NSMenuItem(title: "Open Caffeinate…", action: #selector(openPane), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        let hideItem = NSMenuItem(title: "Hide from Menu Bar", action: #selector(hideFromMenuBar), keyEquivalent: "")
        hideItem.target = self
        menu.addItem(hideItem)

        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.setAccessibilityTitle("Caffeinate")
        }

        statusItem.menu = menu
        applyChrome()
        observeState()
    }

    func invalidate() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        menu.delegate = nil
        statusItem.menu = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    func menuWillOpen(_ menu: NSMenu) {
        applyChrome()
        countdownTimer?.invalidate()
        countdownTimer = nil
        guard catalog.isActive, catalog.endDate != nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.applyCountdown()
            }
        }
        timer.tolerance = 0.15
        RunLoop.main.add(timer, forMode: .common)
        countdownTimer = timer
    }

    func menuDidClose(_ menu: NSMenu) {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    private func observeState() {
        withObservationTracking {
            _ = catalog.isActive
            _ = catalog.duration
            _ = catalog.endDate
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyChrome()
                self?.observeState()
            }
        }
    }

    private func applyChrome() {
        applyIcon()
        applyCountdown()
        turnOffItem.isHidden = !catalog.isActive
        for (duration, item) in durationItems {
            item.state = catalog.isActive && catalog.duration == duration ? .on : .off
        }
    }

    private func applyCountdown() {
        countdownItem.isHidden = !catalog.isActive
        countdownItem.title = catalog.statusText
    }

    private func applyIcon() {
        guard let button = statusItem.button else { return }
        let name = catalog.isActive ? "caffeinate-filled" : "caffeinate-line"
        let fallback = catalog.isActive ? "cup.and.saucer.fill" : "cup.and.saucer"
        let image = NSImage(named: name) ?? NSImage(systemSymbolName: fallback, accessibilityDescription: "Caffeinate")
        image?.isTemplate = true
        image?.size = NSSize(width: 18, height: 18)
        button.image = image
        button.toolTip = catalog.isActive ? "Caffeinate · \(catalog.statusText)" : "Caffeinate"
    }

    @objc private func chooseDuration(_ sender: NSMenuItem) {
        guard let duration = CaffeinateDuration(rawValue: sender.tag) else { return }
        catalog.start(duration)
    }

    @objc private func turnOff() {
        catalog.stop()
    }

    @objc private func openPane() {
        PaneNavigation.open(.caffeinate)
    }

    @objc private func hideFromMenuBar() {
        AppSettings.shared.caffeinateMenuBarEnabled = false
    }
}
