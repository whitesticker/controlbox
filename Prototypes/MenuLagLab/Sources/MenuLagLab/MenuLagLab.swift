import AppKit
import SwiftUI

// A menu bar extra shaped like the System Monitor menu (seven rows, each with
// a submenu), with no graphs: only random numbers. Switch between rows and
// compare the feel with Control Box. The footer times each submenu open from
// the moment the row highlighted.

@main
enum MenuLagLabMain {
    static func main() {
        let app = NSApplication.shared
        let lab = Lab()
        app.delegate = lab
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

enum Mode: String, CaseIterable {
    case native = "Plain menu items"
    case appKit = "AppKit custom views"
    case swiftUI = "SwiftUI custom views"
    case panel = "Custom panel (like iStat)"
}

let rowTitles = ["CPU", "GPU", "Memory", "Network", "Disk", "Sensors", "Battery"]

/// Random numbers for every row and submenu, re-rolled once a second while
/// the menu is open.
final class Numbers: ObservableObject {
    @Published var values: [Double] = Numbers.roll()
    static func roll() -> [Double] { (0..<12).map { _ in Double.random(in: 0...100) } }
}

final class Lab: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var details: [Detail] = []
    private let numbers = Numbers()
    private var ticker: Timer?
    private var appKitRowLabels: [NSTextField] = []
    private let footer = NSTextField(wrappingLabelWithString: "Hover a row to time its submenu.")
    private var history: [Double] = []
    private var panelMenu: PanelMenu?
    private var panelOptions = PanelOptions()

    private var mode = Mode(rawValue: UserDefaults.standard.string(forKey: "mode") ?? "") ?? .native {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "mode"); rebuild() }
    }
    private var wide = UserDefaults.standard.bool(forKey: "wide") {
        didSet { UserDefaults.standard.set(wide, forKey: "wide"); rebuild() }
    }

    private(set) var highlightedAt: CFTimeInterval = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Lag Lab"
        footer.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        footer.textColor = .secondaryLabelColor
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            numbers.values = Numbers.roll()
            updateAppKitRows()
            details.forEach { $0.update() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
        rebuild()
    }

    private func rebuild() {
        panelMenu?.close()
        panelMenu = nil
        history = []
        if mode == .panel {
            details = []
            appKitRowLabels = []
            footer.stringValue = "Hover a row to time its submenu.\nRight-click Lag Lab for modes."
            let footerView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 74))
            footer.frame = footerView.bounds.insetBy(dx: 14, dy: 4)
            footerView.addSubview(footer)
            panelMenu = PanelMenu(numbers: numbers, wide: wide, options: panelOptions, footer: footerView) { [weak self] title, delay, work in
                self?.report(title: title, delay: delay, work: work)
            }
            statusItem.menu = nil
            statusItem.button?.target = self
            statusItem.button?.action = #selector(statusClicked)
            statusItem.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
            return
        }
        statusItem.button?.action = nil
        let menu = NSMenu()
        menu.delegate = self
        appKitRowLabels = []
        details = rowTitles.map { Detail(title: $0, mode: mode, wide: wide, numbers: numbers, lab: self) }

        for (index, detail) in details.enumerated() {
            let item = NSMenuItem(title: detail.title, action: nil, keyEquivalent: "")
            switch mode {
            case .native, .panel:
                break
            case .appKit:
                item.view = appKitRow(detail.title, index: index)
            case .swiftUI:
                let host = NSHostingView(rootView: SwiftUIRow(title: detail.title, index: index, numbers: numbers))
                host.frame = NSRect(x: 0, y: 0, width: 300, height: 56)
                item.view = host
            }
            item.submenu = detail.menu
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let footerView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 74))
        footer.frame = footerView.bounds.insetBy(dx: 14, dy: 4)
        footerView.addSubview(footer)
        let footerItem = NSMenuItem()
        footerItem.view = footerView
        menu.addItem(footerItem)

        addOptions(to: menu)
        statusItem.menu = menu
    }

    private func addOptions(to menu: NSMenu) {
        menu.addItem(.separator())
        for option in Mode.allCases {
            let item = NSMenuItem(title: option.rawValue, action: #selector(pickMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.rawValue
            item.state = option == mode ? .on : .off
            menu.addItem(item)
        }
        let wideItem = NSMenuItem(title: "Wide submenus (550 pt, like history)", action: #selector(toggleWide), keyEquivalent: "")
        wideItem.target = self
        wideItem.state = wide ? .on : .off
        menu.addItem(wideItem)
        if mode == .panel {
            menu.addItem(.separator())
            let aim = NSMenuItem(title: "Panel: menu aim (wait when heading for the submenu)", action: #selector(toggleAim), keyEquivalent: "")
            aim.target = self
            aim.state = panelOptions.menuAim ? .on : .off
            menu.addItem(aim)
            let one = NSMenuItem(title: "Panel: one submenu window, swap content", action: #selector(toggleOneWindow), keyEquivalent: "")
            one.target = self
            one.state = panelOptions.oneWindow ? .on : .off
            menu.addItem(one)
            for background in PanelOptions.Background.allCases {
                let item = NSMenuItem(title: "Panel background: \(background.rawValue)", action: #selector(pickBackground(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = background.rawValue
                item.state = panelOptions.background == background ? .on : .off
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Lag Lab", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func statusClicked() {
        guard let button = statusItem.button else { return }
        if NSApp.currentEvent?.type == .rightMouseDown {
            panelMenu?.close()
            let menu = NSMenu()
            addOptions(to: menu)
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
        } else {
            panelMenu?.toggle(from: button)
        }
    }

    private func appKitRow(_ title: String, index: Int) -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 56))
        let name = NSTextField(labelWithString: title)
        name.font = .systemFont(ofSize: 12, weight: .semibold)
        name.frame = NSRect(x: 14, y: 30, width: 200, height: 18)
        let value = NSTextField(labelWithString: "")
        value.font = .monospacedDigitSystemFont(ofSize: 16, weight: .semibold)
        value.frame = NSRect(x: 14, y: 8, width: 200, height: 22)
        view.addSubview(name)
        view.addSubview(value)
        appKitRowLabels.append(value)
        updateAppKitRows()
        return view
    }

    private func updateAppKitRows() {
        for (index, label) in appKitRowLabels.enumerated() {
            label.stringValue = String(format: "%.1f%%", numbers.values[index])
        }
    }

    @objc private func pickMode(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let picked = Mode(rawValue: raw) { mode = picked }
    }

    @objc private func toggleWide() { wide.toggle() }

    @objc private func toggleAim() { panelOptions.menuAim.toggle(); panelOptions.save(); rebuild() }
    @objc private func toggleOneWindow() { panelOptions.oneWindow.toggle(); panelOptions.save(); rebuild() }
    @objc private func pickBackground(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let picked = PanelOptions.Background(rawValue: raw) {
            panelOptions.background = picked
            panelOptions.save()
            rebuild()
        }
    }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: NSMenuDelegate (main menu)

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        guard item?.submenu != nil else { return }
        highlightedAt = CACurrentMediaTime()
    }

    /// Called by a submenu once it is on screen.
    func report(title: String, delay: Double, work: Double) {
        history.append(delay)
        if history.count > 10 { history.removeFirst() }
        let average = history.reduce(0, +) / Double(history.count)
        footer.stringValue = String(
            format: mode == .panel
                ? "%@: shown %.0f ms after the pointer entered\nof that, menu-aim wait: %.0f ms\naverage of last %d opens: %.0f ms"
                : "%@: opened %.0f ms after the row highlighted\nour work before it showed: %.1f ms\naverage of last %d opens: %.0f ms",
            title, delay * 1000, work * 1000, history.count, average * 1000
        )
    }
}

/// One row's submenu: eight random numbers, refreshed once a second while open.
final class Detail: NSObject, NSMenuDelegate {
    let title: String
    let menu = NSMenu()
    private let mode: Mode
    private let numbers: Numbers
    private weak var lab: Lab?
    private let note = Note()
    private var plainItems: [NSMenuItem] = []
    private var labels: [NSTextField] = []
    private var noteLabel: NSTextField?

    init(title: String, mode: Mode, wide: Bool, numbers: Numbers, lab: Lab) {
        self.title = title
        self.mode = mode
        self.numbers = numbers
        self.lab = lab
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        let size = NSSize(width: wide ? 550 : 260, height: 220)

        switch mode {
        case .native, .panel:
            for _ in 0..<8 {
                let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
                plainItems.append(item)
                menu.addItem(item)
            }
        case .appKit:
            let view = NSView(frame: NSRect(origin: .zero, size: size))
            let header = NSTextField(labelWithString: "")
            header.font = .systemFont(ofSize: 11)
            header.textColor = .secondaryLabelColor
            header.frame = NSRect(x: 14, y: size.height - 26, width: size.width - 28, height: 16)
            view.addSubview(header)
            noteLabel = header
            for i in 0..<8 {
                let label = NSTextField(labelWithString: "")
                label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
                label.frame = NSRect(x: 14, y: size.height - 52 - CGFloat(i) * 21, width: size.width - 28, height: 18)
                view.addSubview(label)
                labels.append(label)
            }
            let item = NSMenuItem()
            item.view = view
            menu.addItem(item)
        case .swiftUI:
            let host = NSHostingView(rootView: SwiftUIDetail(title: title, numbers: numbers, note: note, width: size.width))
            host.frame = NSRect(origin: .zero, size: size)
            let item = NSMenuItem()
            item.view = host
            menu.addItem(item)
        }
        refreshAppKit()
    }

    private func refreshAppKit() {
        for (i, item) in plainItems.enumerated() {
            item.title = String(format: "\(title) value \(i + 1): %.1f", numbers.values[i])
        }
        for (i, label) in labels.enumerated() {
            label.stringValue = String(format: "\(title) value \(i + 1): %.1f", numbers.values[i])
        }
        noteLabel?.stringValue = note.text
    }

    func menuWillOpen(_ menu: NSMenu) {
        let start = CACurrentMediaTime()
        let delay = start - (lab?.highlightedAt ?? start)
        note.text = String(format: "Opened %.0f ms after the row highlighted", delay * 1000)
        refreshAppKit()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            lab?.report(title: title, delay: delay, work: CACurrentMediaTime() - start)
        }
    }

    /// Keeps plain and AppKit rows in step with the shared numbers.
    func update() { refreshAppKit() }
}

final class Note: ObservableObject {
    @Published var text = ""
}

struct SwiftUIRow: View {
    let title: String
    let index: Int
    @ObservedObject var numbers: Numbers

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 12, weight: .semibold))
            Text(String(format: "%.1f%%", numbers.values[index]))
                .font(.system(size: 16, weight: .semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .frame(width: 300, height: 56, alignment: .leading)
    }
}

struct SwiftUIDetail: View {
    let title: String
    @ObservedObject var numbers: Numbers
    @ObservedObject var note: Note
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(note.text).font(.system(size: 11)).foregroundColor(.secondary)
            ForEach(0..<8, id: \.self) { i in
                Text(String(format: "\(title) value \(i + 1): %.1f", numbers.values[i]))
                    .font(.system(size: 12))
                    .monospacedDigit()
            }
        }
        .padding(14)
        .frame(width: width, height: 220, alignment: .topLeading)
    }
}
