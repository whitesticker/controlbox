import AppKit
import SwiftUI

extension Notification.Name {
    static let vibeRemoteReopenMainWindow = Notification.Name("vibeRemoteReopenMainWindow")
}

@MainActor
enum WindowActions {
    static var openMain: ((String) -> Void)?
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let monitor = DualSenseMonitor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async { [monitor] in
            monitor.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let hasKeyWindow = NSApp.windows.contains { $0.isVisible && $0.canBecomeKey }
        if !hasKeyWindow {
            NotificationCenter.default.post(name: .vibeRemoteReopenMainWindow, object: nil)
            WindowActions.openMain?("main")
        }
        NSApp.activate()
        return true
    }
}

@main
struct IRemoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("VibeRemote", id: "main") {
            ContentView(monitor: appDelegate.monitor)
                .frame(minWidth: 860, minHeight: 620)
                .preferredColorScheme(nil)
                .modifier(RegisterOpenWindow())
                .onAppear { appDelegate.monitor.start() }
        }
        .defaultSize(width: 980, height: 720)
        .windowResizability(.contentMinSize)
        .commands {
            VibeRemoteWindowCommands()
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
            VibeRemoteMenuBar(monitor: appDelegate.monitor)
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
        Image(systemName: "gamecontroller.fill")
            .accessibilityLabel("VibeRemote")
            .onAppear {
                WindowActions.openMain = { id in
                    openWindow(id: id)
                    NSApp.activate()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .vibeRemoteReopenMainWindow)) { _ in
                openWindow(id: "main")
                NSApp.activate()
            }
    }
}

private struct VibeRemoteWindowCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .windowList) {
            Button("VibeRemote") {
                openWindow(id: "main")
                NSApp.activate()
            }
            .keyboardShortcut("0", modifiers: .command)
        }
    }
}

private struct VibeRemoteMenuBar: View {
    @Bindable var monitor: DualSenseMonitor
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open VibeRemote") {
            openWindow(id: "main")
            NSApp.activate()
        }

        if let record = monitor.selectedRecord {
            Divider()
            Text(record.controlEnabled ? "\(record.name) · Control on" : "\(record.name) · Control off")
        }

        Divider()
        Button("Quit VibeRemote") {
            NSApp.terminate(nil)
        }
    }
}
