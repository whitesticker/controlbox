import AppKit
import ControlBoxCore
import SwiftUI

extension Notification.Name {
    static let controlBoxReopenMainWindow = Notification.Name("controlBoxReopenMainWindow")
    static let controlBoxOpenPane = Notification.Name("controlBoxOpenPane")
    static let controlBoxOpenSystemMonitor = Notification.Name("controlBoxOpenSystemMonitor")
}

@MainActor
enum WindowActions {
    static var openMain: ((String) -> Void)?
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let monitor = DualSenseMonitor()
    let arrangementCatalog = ArrangementCatalog()
    let nightShiftCatalog = NightShiftCatalog()
    let displayCatalog = DisplayCatalog()
    let soundCatalog = SoundCatalog()
    let dockPreviewCatalog = DockPreviewCatalog()

    func applicationDidFinishLaunching(_ notification: Notification) {
        LegacyPrefs.migrateIfNeeded()
        AppSettings.shared.applyDockPolicy()
        TopMenuBarHost.shared.start()
        MenuBarExtrasHost.shared.start(displays: displayCatalog, sound: soundCatalog)
        nightShiftCatalog.attachDisplays(displayCatalog)
        dockPreviewCatalog.attachSuppress {
            WindowGrab.isBusy || WindowGrab.grabChordHeld(ModifierChords.fromAppKit(NSEvent.modifierFlags))
        }
        DispatchQueue.main.async { [monitor] in
            monitor.start()
        }
        if AppSettings.shared.hideDockIcon {
            DispatchQueue.main.async { [weak self] in
                self?.closeSessionWindows()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        TopMenuBarHost.shared.stop()
        MenuBarExtrasHost.shared.stop()
        ArrangementHotkey.stop()
        nightShiftCatalog.invalidate()
        DockPreview.stop()
        DockPreviewOverlay.shared.hide()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let hasKeyWindow = NSApp.windows.contains { $0.isVisible && $0.canBecomeKey }
        if !hasKeyWindow {
            NotificationCenter.default.post(name: .controlBoxReopenMainWindow, object: nil)
            WindowActions.openMain?("main")
        }
        NSApp.activate()
        return true
    }

    private func closeSessionWindows() {
        for window in NSApp.windows where window.title == "Control Box" || window.title == "Calibration" {
            window.close()
        }
    }
}

@main
struct ControlBoxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Control Box", id: "main") {
            ContentView(
                monitor: appDelegate.monitor,
                arrangementCatalog: appDelegate.arrangementCatalog,
                nightShiftCatalog: appDelegate.nightShiftCatalog,
                displayCatalog: appDelegate.displayCatalog,
                soundCatalog: appDelegate.soundCatalog,
                dockPreviewCatalog: appDelegate.dockPreviewCatalog
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

        Window("Calibration", id: "calibration") {
            CalibrationWindow(monitor: appDelegate.monitor)
                .frame(minWidth: 1100, minHeight: 700)
                .preferredColorScheme(nil)
                .onAppear { appDelegate.monitor.start() }
        }
        .defaultSize(width: 1280, height: 800)
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            ControlBoxMenuBar()
        } label: {
            MenuBarReopenHook()
        }
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

private struct MenuBarReopenHook: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(nsImage: MenuBarRingIcon.image)
            .renderingMode(.template)
            .accessibilityLabel("Control Box")
            .onAppear {
                WindowActions.openMain = { id in
                    openWindow(id: id)
                    NSApp.activate()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .controlBoxReopenMainWindow)) { _ in
                openWindow(id: "main")
                NSApp.activate()
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

private struct ControlBoxMenuBar: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Control Box") {
            openWindow(id: "main")
            NSApp.activate()
        }

        Divider()
        Button("Quit Control Box") {
            AppQuit.quitNow()
        }
    }
}
