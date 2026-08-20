import SwiftUI

@main
struct IRemoteApp: App {
    @State private var monitor = DualSenseMonitor()

    var body: some Scene {
        WindowGroup("VibeRemote") {
            ContentView(monitor: monitor)
                .frame(minWidth: 860, minHeight: 620)
                .preferredColorScheme(nil)
                .onAppear { monitor.start() }
        }
        .defaultSize(width: 980, height: 720)
        .windowResizability(.contentMinSize)

        WindowGroup("Calibration", id: "calibration") {
            CalibrationWindow(monitor: monitor)
                .frame(minWidth: 1100, minHeight: 700)
                .preferredColorScheme(nil)
                .onAppear { monitor.start() }
        }
        .defaultSize(width: 1280, height: 800)
        .windowResizability(.contentMinSize)
    }
}
