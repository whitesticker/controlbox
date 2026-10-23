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
        menuBar = MenuBarPreview(store: store)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct HistoryLabApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("HistoryLab", id: "main") {
            LabRoot()
                .environmentObject(delegate.store)
        }
        .defaultSize(width: 1240, height: 780)
    }
}

struct LabRoot: View {
    @EnvironmentObject private var store: LabStore

    var body: some View {
        HStack(spacing: 0) {
            LabCanvas()
            Divider()
            Inspector()
                .frame(width: 340)
        }
        .frame(minWidth: 1000, minHeight: 640)
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
