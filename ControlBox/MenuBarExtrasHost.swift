import AppKit
import ControlBoxCore
import Observation
import SwiftUI

/// Brightness and Sound extras. Separate from the Control Box ring
/// `MenuBarExtra` and from System Monitor’s network icon. Off until each pane’s toggle is on.
///
/// Same shape as System Monitor: a real `NSMenu` on the status item, SwiftUI
/// rows hosted once and reused, native Open / Hide items. Not an `NSPopover`.
@MainActor
final class MenuBarExtrasHost {
    static let shared = MenuBarExtrasHost()

    private var displays: DisplayCatalog?
    private var sound: SoundCatalog?
    private var brightnessItem: ExtraStatusItem?
    private var soundItem: ExtraStatusItem?

    private init() {}

    func start(displays: DisplayCatalog, sound: SoundCatalog) {
        self.displays = displays
        self.sound = sound
        displays.refresh()
        sound.refresh()
        apply()
    }

    func stop() {
        brightnessItem?.invalidate()
        brightnessItem = nil
        soundItem?.invalidate()
        soundItem = nil
        displays = nil
        sound = nil
    }

    func apply() {
        let settings = AppSettings.shared
        if settings.brightnessMenuBarEnabled, let displays {
            if brightnessItem == nil {
                brightnessItem = ExtraStatusItem.brightness(catalog: displays)
            }
        } else {
            brightnessItem?.invalidate()
            brightnessItem = nil
        }
        if settings.soundMenuBarEnabled, let sound {
            if soundItem == nil {
                soundItem = ExtraStatusItem.sound(catalog: sound)
            }
        } else {
            soundItem?.invalidate()
            soundItem = nil
        }
    }
}

/// Status extra with a genuine `NSMenu` (System Monitor’s pattern). Hide does not quit.
@MainActor
private final class ExtraStatusItem: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var hostingViews: [NSHostingView<AnyView>] = []
    private var sliderItems: [String: NSMenuItem] = [:]
    private var sliderIDs: [String] = []
    private var rowInsertionIndex = 0
    private var screenObserver: NSObjectProtocol?
    private var refreshTimer: Timer?
    private let rebuild: () -> [(id: String, view: AnyView)]
    private let rowIDs: () -> [String]
    private let prepareOpen: () -> Void
    private let pollWhileOpen: Bool

    static func brightness(catalog: DisplayCatalog) -> ExtraStatusItem {
        ExtraStatusItem(
            symbol: "sun.max.fill",
            accessibility: "Display Brightness",
            openTitle: "Open Display Brightness…",
            open: { PaneNavigation.open(.displays) },
            hide: { AppSettings.shared.brightnessMenuBarEnabled = false },
            prepareOpen: { catalog.refresh(readHardware: false) },
            watchScreens: true,
            pollWhileOpen: false,
            rowIDs: { Self.brightnessIDs(catalog: catalog) },
            rebuild: { Self.brightnessRows(catalog: catalog) }
        )
    }

    static func sound(catalog: SoundCatalog) -> ExtraStatusItem {
        ExtraStatusItem(
            symbol: "speaker.wave.2.fill",
            accessibility: "Sound",
            openTitle: "Open Sound…",
            open: { PaneNavigation.open(.sound) },
            hide: { AppSettings.shared.soundMenuBarEnabled = false },
            prepareOpen: { catalog.refresh() },
            watchScreens: false,
            pollWhileOpen: true,
            rowIDs: { Self.soundIDs(catalog: catalog) },
            rebuild: { Self.soundRows(catalog: catalog) }
        )
    }

    private init(
        symbol: String,
        accessibility: String,
        openTitle: String,
        open: @escaping () -> Void,
        hide: @escaping () -> Void,
        prepareOpen: @escaping () -> Void,
        watchScreens: Bool,
        pollWhileOpen: Bool,
        rowIDs: @escaping () -> [String],
        rebuild: @escaping () -> [(id: String, view: AnyView)]
    ) {
        self.prepareOpen = prepareOpen
        self.rowIDs = rowIDs
        self.rebuild = rebuild
        self.pollWhileOpen = pollWhileOpen
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        menu.delegate = self
        menu.autoenablesItems = false
        menu.addItem(.separator())
        rowInsertionIndex = menu.items.count
        menu.addItem(.separator())

        let openItem = NSMenuItem(title: openTitle, action: #selector(openPane), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        let hideItem = NSMenuItem(title: "Hide from Menu Bar", action: #selector(hideFromMenuBar), keyEquivalent: "")
        hideItem.target = self
        menu.addItem(hideItem)

        self.openPaneHandler = open
        self.hideHandler = hide

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: accessibility)
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
        }

        applyRows()
        statusItem.menu = menu
        observeRows()

        if watchScreens {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.prepareOpen()
                    self?.applyRows()
                }
            }
        }
    }

    private var openPaneHandler: () -> Void = {}
    private var hideHandler: () -> Void = {}

    func invalidate() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        menu.delegate = nil
        statusItem.menu = nil
        NSStatusBar.system.removeStatusItem(statusItem)
        hostingViews.removeAll()
        sliderItems.removeAll()
    }

    func menuWillOpen(_ menu: NSMenu) {
        prepareOpen()
        applyRows()
        for hosting in hostingViews {
            hosting.layoutSubtreeIfNeeded()
            let fitting = hosting.fittingSize
            guard fitting.height > 0 else { continue }
            hosting.frame = NSRect(origin: .zero, size: fitting)
        }
        refreshTimer?.invalidate()
        refreshTimer = nil
        if pollWhileOpen {
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.prepareOpen()
                    self.applyRows()
                }
            }
            RunLoop.main.add(refreshTimer!, forMode: .common)
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func observeRows() {
        withObservationTracking {
            _ = rowIDs()
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyRows()
                self?.observeRows()
            }
        }
    }

    @objc private func openPane() {
        openPaneHandler()
    }

    @objc private func hideFromMenuBar() {
        hideHandler()
    }

    private func applyRows() {
        let rows = rebuild()
        let ids = rows.map(\.id)
        if ids == sliderIDs {
            return
        }
        for item in sliderItems.values where menu.items.contains(item) {
            menu.removeItem(item)
        }
        sliderItems.removeAll()
        hostingViews.removeAll()
        sliderIDs = ids
        for (offset, row) in rows.enumerated() {
            let item = hostedRow(row.view)
            sliderItems[row.id] = item
            menu.insertItem(item, at: rowInsertionIndex + offset)
        }
    }

    private func hostedRow(_ view: AnyView) -> NSMenuItem {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 300, height: 80)
        warmUp(hosting)
        hostingViews.append(hosting)
        let item = NSMenuItem()
        item.isEnabled = true
        item.view = hosting
        return item
    }

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

    private static func brightnessIDs(catalog: DisplayCatalog) -> [String] {
        if catalog.displays.isEmpty { return ["empty"] }
        if catalog.unifiedEnabled { return ["unified"] }
        return catalog.displays.map(\.id)
    }

    private static func soundIDs(catalog: SoundCatalog) -> [String] {
        soundRows(catalog: catalog).map(\.id)
    }

    private static func brightnessRows(catalog: DisplayCatalog) -> [(id: String, view: AnyView)] {
        if catalog.displays.isEmpty {
            return [("empty", AnyView(ExtraMenuNote(text: "No displays reported.")))]
        }
        if catalog.unifiedEnabled {
            return [(
                "unified",
                AnyView(ExtraSliderRow(
                    title: "All displays",
                    value: Binding(
                        get: { catalog.unifiedBrightness },
                        set: { catalog.setUnifiedBrightness($0) }
                    )
                ))
            )]
        }
        return catalog.displays.map { display in
            (
                display.id,
                AnyView(BrightnessSliderRow(catalog: catalog, display: display))
            )
        }
    }

    private static func soundRows(catalog: SoundCatalog) -> [(id: String, view: AnyView)] {
        var rows: [(id: String, view: AnyView)] = []
        if catalog.outputs.isEmpty {
            rows.append(("empty-output", AnyView(ExtraMenuNote(text: "No output devices."))))
        } else {
            rows.append((
                "output",
                AnyView(ExtraSliderRow(
                    title: "Output",
                    value: Binding(
                        get: { catalog.volume },
                        set: { catalog.setVolume($0) }
                    )
                ))
            ))
        }
        if catalog.mixSupported {
            if !catalog.hasCaptureAccess {
                rows.append(("need-audio", AnyView(ExtraMenuNote(text: "Grant System Audio Recording for per-app volume."))))
            } else if catalog.apps.isEmpty {
                rows.append(("empty-apps", AnyView(ExtraMenuNote(text: "Play something, then that app’s slider shows up here."))))
            } else {
                for app in catalog.apps {
                    rows.append((
                        "app:\(app.id)",
                        AnyView(AppVolumeSliderRow(catalog: catalog, app: app))
                    ))
                }
            }
        }
        return rows
    }
}

private struct BrightnessSliderRow: View {
    @Bindable var catalog: DisplayCatalog
    let display: AttachedDisplay

    var body: some View {
        ExtraSliderRow(
            title: catalog.displays.first { $0.id == display.id }?.name ?? display.name,
            value: Binding(
                get: { catalog.displays.first { $0.id == display.id }?.brightness ?? display.brightness },
                set: { catalog.setBrightness($0, id: display.id) }
            ),
            enabled: (catalog.displays.first { $0.id == display.id }?.canAdjustBrightness ?? display.canAdjustBrightness)
                && !catalog.unifiedEnabled
        )
    }
}

private struct AppVolumeSliderRow: View {
    @Bindable var catalog: SoundCatalog
    let app: AttachedAudioApp

    var body: some View {
        let live = catalog.apps.first { $0.id == app.id } ?? app
        ExtraSliderRow(
            title: live.name,
            detail: live.isMuted ? "Muted" : (live.isPlaying ? "Playing" : "Saved"),
            value: Binding(
                get: { catalog.apps.first { $0.id == app.id }?.volume ?? app.volume },
                set: { catalog.setAppVolume($0, id: app.id) }
            )
        )
    }
}

private struct ExtraSliderRow: View {
    let title: String
    var detail: String? = nil
    @Binding var value: Double
    var enabled: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .lineLimit(1)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Text("\(Int((value * 100).rounded()))%")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.system(size: 12, weight: .semibold))
            Slider(value: $value)
                .controlSize(.small)
                .disabled(!enabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: 300, alignment: .leading)
        .opacity(enabled ? 1 : 0.45)
    }
}

private struct ExtraMenuNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(width: 300, alignment: .leading)
    }
}
