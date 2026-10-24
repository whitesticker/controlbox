import AppKit
import ControlBoxCore
import SwiftUI

extension Notification.Name {
    static let controlBoxOpenPane = Notification.Name("controlBoxOpenPane")
    static let controlBoxOpenSystemMonitor = Notification.Name("controlBoxOpenSystemMonitor")
}

@MainActor
enum WindowActions {
    /// SwiftUI `openWindow`, captured when the main window first appears.
    static var openMain: ((String) -> Void)?

    /// Opens (or raises) the main window. Falls back to the Window menu's
    /// Control Box command, which holds its own `openWindow`.
    static func showMain() {
        if let openMain {
            openMain("main")
            return
        }
        NSApp.activate()
        for menu in NSApp.mainMenu?.items.compactMap(\.submenu) ?? [] {
            if let index = menu.items.firstIndex(where: { $0.title == "Control Box" && $0.keyEquivalent == "0" }) {
                menu.performActionForItem(at: index)
                return
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let monitor = DualSenseMonitor()
    let arrangementCatalog = ArrangementCatalog()
    let nightShiftCatalog = NightShiftCatalog()
    let displayCatalog = DisplayCatalog()
    let soundCatalog = SoundCatalog()
    let caffeinateCatalog = CaffeinateCatalog()
    let dockPreviewCatalog = DockPreviewCatalog()
    let capsLockCatalog = CapsLockCatalog()
    let boltCatalog = LogiBoltCatalog()

    func applicationDidFinishLaunching(_ notification: Notification) {
        LegacyPrefs.migrateIfNeeded()
        if ScreenshotExport.isActive {
            NSApp.setActivationPolicy(.regular)
        } else {
            AppSettings.shared.applyDockPolicy()
        }
        displayCatalog.start()
        SystemMonitorMenuBarHost.shared.start()
        soundCatalog.refresh()
        nightShiftCatalog.attachDisplays(displayCatalog)
        dockPreviewCatalog.attachSuppress {
            WindowGrab.isBusy || WindowShake.isBusy || AppSwitcherPreview.isBusy
                || WindowGrab.grabChordHeld(ModifierChords.fromAppKit(NSEvent.modifierFlags))
        }
        DispatchQueue.main.async { [monitor, boltCatalog] in
            monitor.attachBoltCatalog(boltCatalog)
            monitor.start()
        }
        if ScreenshotExport.isActive {
            DispatchQueue.main.async {
                ScreenshotExport.runIfRequested()
            }
        } else if AppSettings.shared.hideDockIcon {
            DispatchQueue.main.async { [weak self] in
                self?.closeSessionWindows()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        SystemMonitorMenuBarHost.shared.stop()
        caffeinateCatalog.invalidate()
        ArrangementHotkey.stop()
        nightShiftCatalog.invalidate()
        DockPreview.stop()
        DockPreviewOverlay.shared.hide()
        DockClick.stop()
        AppSwitcherPreview.stop()
        AppSwitcherPreviewOverlay.shared.hide()
        capsLockCatalog.invalidate()
        boltCatalog.stopWatching()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let hasKeyWindow = NSApp.windows.contains { $0.isVisible && $0.canBecomeKey }
        if !hasKeyWindow {
            WindowActions.showMain()
        }
        NSApp.activate()
        return true
    }

    private func closeSessionWindows() {
        for window in NSApp.windows where window.title == "Control Box" || window.title == "Calibration" || window.title == "Pair Logi Bolt" {
            window.close()
        }
    }
}

@main
struct ControlBoxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Bindable private var settings = AppSettings.shared

    init() {
        Self.useOverlayScrollers()
    }

    /// Scroll bars show only while scrolling, in every window and menu, even
    /// when a mouse makes macOS prefer always-visible (legacy) scrollers.
    /// Same as launching with `-AppleShowScrollBars WhenScrolling`: the
    /// argument domain outranks the global setting and is never saved, so
    /// System Settings is untouched and other apps are unaffected. Must run
    /// before the first scroll view exists.
    private static func useOverlayScrollers() {
        let defaults = UserDefaults.standard
        var arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        arguments["AppleShowScrollBars"] = "WhenScrolling"
        defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
    }

    var body: some Scene {
        Window("Control Box", id: "main") {
            ContentView(
                monitor: appDelegate.monitor,
                arrangementCatalog: appDelegate.arrangementCatalog,
                nightShiftCatalog: appDelegate.nightShiftCatalog,
                displayCatalog: appDelegate.displayCatalog,
                soundCatalog: appDelegate.soundCatalog,
                caffeinateCatalog: appDelegate.caffeinateCatalog,
                dockPreviewCatalog: appDelegate.dockPreviewCatalog,
                capsLockCatalog: appDelegate.capsLockCatalog,
                boltCatalog: appDelegate.boltCatalog
            )
                .frame(minWidth: 860, minHeight: 620)
                .preferredColorScheme(nil)
                .modifier(RegisterOpenWindow())
                .onAppear { appDelegate.monitor.start() }
        }
        .defaultSize(width: 980, height: 720)
        .windowResizability(.contentMinSize)
        .commands {
            ControlBoxWindowCommands()
        }

        WindowGroup("Calibration", id: "calibration", for: String.self) { $deviceID in
            Group {
                if let deviceID {
                    CalibrationWindow(monitor: appDelegate.monitor, deviceID: deviceID)
                } else {
                    ContentUnavailableView(
                        "No Device",
                        systemImage: "slider.horizontal.3",
                        description: Text("Open Calibration from a device page.")
                    )
                }
            }
                .frame(minWidth: 1100, minHeight: 700)
                .preferredColorScheme(nil)
                .onAppear { appDelegate.monitor.start() }
        }
        .defaultSize(width: 1280, height: 800)
        .windowResizability(.contentMinSize)

        Window("Mouse Settings", id: "mx-mouse-settings") {
            MXMouseSettingsWindow(monitor: appDelegate.monitor)
                .frame(minWidth: 480, minHeight: 560)
                .preferredColorScheme(nil)
                .onAppear { appDelegate.monitor.start() }
        }
        .defaultSize(width: 540, height: 680)
        .windowResizability(.contentMinSize)

        Window("Pair Logi Bolt", id: "bolt-pairing") {
            BoltPairingGuideWindow(catalog: appDelegate.boltCatalog)
                .frame(minWidth: 560, minHeight: 520)
                .preferredColorScheme(nil)
        }
        .defaultSize(width: 620, height: 560)
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            ControlCenterPanelView(context: controlCenterContext)
        } label: {
            Image(nsImage: MenuBarRingIcon.image)
                .accessibilityLabel("Control Box")
        }
        .menuBarExtraStyle(.window)

        controlCenterExtra(.display, isInserted: $settings.brightnessMenuBarEnabled)
        controlCenterExtra(.sound, isInserted: $settings.soundMenuBarEnabled)
        controlCenterExtra(.caffeinate, isInserted: $settings.caffeinateMenuBarEnabled)
    }

    private var controlCenterContext: ControlCenterContext {
        ControlCenterContext(
            displays: appDelegate.displayCatalog,
            sound: appDelegate.soundCatalog,
            caffeinate: appDelegate.caffeinateCatalog,
            nightShift: appDelegate.nightShiftCatalog,
            arrangement: appDelegate.arrangementCatalog
        )
    }

    /// A module's own extra (its pane's Show in Menu Bar): that module's detail view.
    private func controlCenterExtra(_ module: ControlCenterModule, isInserted: Binding<Bool>) -> some Scene {
        MenuBarExtra(isInserted: isInserted) {
            ControlCenterExtraView(context: controlCenterContext, module: module)
        } label: {
            ControlCenterExtraLabel(context: controlCenterContext, module: module)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct RegisterOpenWindow: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content
            .onAppear {
                WindowActions.openMain = { id in
                    openWindow(id: id)
                    NSApp.activate()
                }
            }
    }
}

private struct ControlBoxWindowCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appTermination) {
            Button("Close Window") {
                NSApp.keyWindow?.close()
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        CommandGroup(after: .windowList) {
            Button("Control Box") {
                openWindow(id: "main")
                NSApp.activate()
            }
            .keyboardShortcut("0", modifiers: .command)
        }
    }
}