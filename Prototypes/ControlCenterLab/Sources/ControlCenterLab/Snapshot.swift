import AppKit
import SwiftUI

/// `ControlCenterLab --snapshot <dir>` renders the panel's home and detail
/// views and each separate extra, light and dark, then quits. Glass is drawn
/// as a fill offscreen, so judge layout here and glass in the running app.
enum Snapshot {
    @MainActor
    static func runIfRequested(store: LabStore) -> Bool {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--snapshot"), flag + 1 < args.count else { return false }
        let dir = URL(fileURLWithPath: args[flag + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        store.startCaffeinate(.oneHour)

        var shots: [(String, AnyView)] = [("home", AnyView(ControlCenterPanel(store: store)))]
        for kind in ModuleKind.allCases where kind.hasDetail {
            shots.append(("detail-\(kind.rawValue)", AnyView(ControlCenterPanel(store: store, initialRoute: .detail(kind)))))
        }
        for kind in ModuleKind.allCases where kind.canBeExtra {
            shots.append(("extra-\(kind.rawValue)", AnyView(ExtraPanel(store: store, kind: kind))))
        }

        for scheme in [ColorScheme.light, .dark] {
            for (name, view) in shots {
                let content = view
                    .padding(24)
                    .background(Wallpaper())
                    .environment(\.labSnapshot, true)
                    .environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: content)
                renderer.scale = 2
                guard let image = renderer.nsImage,
                      let tiff = image.tiffRepresentation,
                      let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
                else { continue }
                try? png.write(to: dir.appendingPathComponent("\(name)-\(scheme == .dark ? "dark" : "light").png"))
            }
        }
        return true
    }
}
