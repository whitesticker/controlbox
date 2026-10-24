import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = LabStore()
    private var menuBar: MenuBarPreview?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if MainActor.assumeIsolated({ Snapshot.runIfRequested(store: store) }) {
            exit(0)
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        menuBar = MenuBarPreview(store: store) { Self.showLabWindow() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    static func showLabWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.title == "ControlCenterLab" }?.makeKeyAndOrderFront(nil)
    }
}

@main
struct ControlCenterLabApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("ControlCenterLab", id: "main") {
            LabRoot(store: delegate.store)
        }
        .defaultSize(width: 1500, height: 860)
    }
}

struct LabRoot: View {
    @ObservedObject var store: LabStore

    var body: some View {
        HStack(spacing: 0) {
            LabCanvas(store: store) { store.canvasTab = .pane }
            Divider()
            Inspector(store: store)
                .frame(width: 360)
        }
        .frame(minWidth: 1100, minHeight: 680)
        .onAppear { applyAppearance() }
        .onChange(of: store.appearance) { applyAppearance() }
    }

    private func applyAppearance() {
        switch store.appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
