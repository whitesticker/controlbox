import AppKit
import SwiftUI

/// `HistoryLab --snapshot <dir>` renders one PNG per metric and style
/// offscreen, then quits. Lets the panel be reviewed without screen capture.
enum Snapshot {
    @MainActor
    static func runIfRequested(store: LabStore) -> Bool {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--snapshot"), flag + 1 < args.count else { return false }
        let dir = URL(fileURLWithPath: args[flag + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        store.live = false

        let savedRange = store.range
        defer { store.range = savedRange }
        for scheme in [ColorScheme.light, .dark] {
            for metric in Metric.allCases {
                for style in HistoryDesign.Style.allCases {
                  for range in style == .bars ? HistoryRange.allCases : [savedRange] {
                    store.metric = metric
                    store.range = range
                    var design = store.design
                    design.style = style
                    let view = HistoryPanel(history: store.history, design: design)
                        .padding(10)
                        .background(scheme == .dark ? Color(white: 0.16) : Color(white: 0.96))
                        .environment(\.colorScheme, scheme)
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 2
                    guard let image = renderer.nsImage,
                          let tiff = image.tiffRepresentation,
                          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
                    else { continue }
                    let rangeTag = style == .bars ? "-\(range.rawValue)" : ""
                    let name = "\(metric.rawValue)-\(style.rawValue)\(rangeTag)-\(scheme == .dark ? "dark" : "light").png"
                    try? png.write(to: dir.appendingPathComponent(name))
                  }
                }
            }
        }
        return true
    }
}
