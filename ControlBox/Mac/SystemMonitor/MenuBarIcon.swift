import AppKit

// MARK: - Items

/// What the System Monitor menu bar extra can show, chosen and ordered in
/// the pane's Menu Bar Icon section.
enum MenuBarItem: String, CaseIterable, Codable, Identifiable {
    case network, diskActivity, cpu, cpuTemp, gpu, gpuTemp, memory, disk, power, battery, fan

    var id: String { rawValue }

    /// Name in the pane.
    var title: String {
        switch self {
        case .network: return "Network"
        case .diskActivity: return "Disk activity"
        case .cpu: return "CPU"
        case .cpuTemp: return "CPU temp"
        case .gpu: return "GPU"
        case .gpuTemp: return "GPU temp"
        case .memory: return "Memory pressure"
        case .disk: return "Disk used"
        case .power: return "Power"
        case .battery: return "Battery"
        case .fan: return "Fan"
        }
    }

    static let defaultShown: [MenuBarItem] = [.network]
}

/// One item's text: a small caption over a large value, or two marked
/// lines (↑ upload / ↓ download, R read / W write).
enum MenuBarItemText: Equatable {
    case single(caption: String, value: String)
    case pair(top: Line, bottom: Line)

    struct Line: Equatable {
        var mark: String
        var value: String
    }
}

extension MenuBarItem {
    /// Live text from `snapshot`, or the pane's example values when nil.
    func text(_ snapshot: SystemSnapshot?) -> MenuBarItemText {
        guard let snapshot else { return example }
        switch self {
        case .network:
            return Self.rates(("↑", snapshot.network.upBytesPerSec), ("↓", snapshot.network.downBytesPerSec))
        case .diskActivity:
            return Self.rates(("R", snapshot.disk.readBytesPerSec), ("W", snapshot.disk.writeBytesPerSec))
        case .cpu:
            return .single(caption: "CPU", value: Fmt.percent(snapshot.cpu.totalUsage))
        case .cpuTemp:
            return .single(caption: "CPU", value: Self.degrees(snapshot.sensors.cpuTemp))
        case .gpu:
            return .single(caption: "GPU", value: snapshot.gpu.available ? Fmt.percent(snapshot.gpu.utilization) : "—")
        case .gpuTemp:
            return .single(caption: "GPU", value: Self.degrees(snapshot.sensors.gpuTemp))
        case .memory:
            return .single(caption: "MEM", value: Fmt.percent(snapshot.memory.pressure))
        case .disk:
            let volumes = snapshot.disk.volumes
            guard let boot = volumes.first(where: { $0.mountPoint == "/" }) ?? volumes.first, boot.total > 0 else {
                return .single(caption: "SSD", value: "—")
            }
            return .single(
                caption: boot.isInternal ? "SSD" : "DISK",
                value: Fmt.percent(Double(boot.used) / Double(boot.total))
            )
        case .power:
            let watts = snapshot.sensors.systemPower > 0 ? snapshot.sensors.systemPower : snapshot.power.powerWatts
            return .single(caption: "PWR", value: watts > 0 ? String(format: "%.0fW", watts) : "—")
        case .battery:
            return .single(caption: "BAT", value: snapshot.power.hasBattery ? Fmt.percent(snapshot.power.percentage) : "—")
        case .fan:
            return .single(caption: "FAN", value: snapshot.sensors.fans.first.map { String(format: "%.0f", $0.rpm) } ?? "—")
        }
    }

    private var example: MenuBarItemText {
        switch self {
        case .network: return .pair(top: .init(mark: "↑", value: "4 K/s"), bottom: .init(mark: "↓", value: "11 K/s"))
        case .diskActivity: return .pair(top: .init(mark: "R", value: "2.1 M/s"), bottom: .init(mark: "W", value: "640 K/s"))
        case .cpu: return .single(caption: "CPU", value: "14%")
        case .cpuTemp: return .single(caption: "CPU", value: "41°")
        case .gpu: return .single(caption: "GPU", value: "8%")
        case .gpuTemp: return .single(caption: "GPU", value: "38°")
        case .memory: return .single(caption: "MEM", value: "33%")
        case .disk: return .single(caption: "SSD", value: "49%")
        case .power: return .single(caption: "PWR", value: "28W")
        case .battery: return .single(caption: "BAT", value: "80%")
        case .fan: return .single(caption: "FAN", value: "1200")
        }
    }

    /// Widest value this item can show, so its width never changes.
    fileprivate var widestText: MenuBarItemText {
        switch self {
        case .network, .diskActivity:
            let line = MenuBarItemText.Line(mark: "↑", value: "999.9 K/s")
            return .pair(top: line, bottom: line)
        case .cpu, .gpu, .memory, .disk, .battery: return .single(caption: "DISK", value: "100%")
        case .cpuTemp, .gpuTemp: return .single(caption: "CPU", value: "100°")
        case .power: return .single(caption: "PWR", value: "999W")
        case .fan: return .single(caption: "FAN", value: "8888")
        }
    }

    private static func rates(_ top: (String, Double), _ bottom: (String, Double)) -> MenuBarItemText {
        func line(_ entry: (String, Double)) -> MenuBarItemText.Line {
            let (number, unit) = Fmt.speedCompact(entry.1)
            return .init(mark: entry.0, value: "\(number) \(unit)")
        }
        return .pair(top: line(top), bottom: line(bottom))
    }

    private static func degrees(_ celsius: Double) -> String {
        celsius > 0 ? String(format: "%.0f°", celsius) : "—"
    }
}

// MARK: - Renderer

/// Draws the chosen items side by side as one template image (monochrome,
/// so it follows the menu bar's light/dark appearance). Every item is
/// drawn at the width of its widest possible text: `NSStatusItem` moves
/// its neighbours whenever its width changes, so a width that followed the
/// digits would shift the menu bar on every tick and could make a click
/// land on the wrong item.
enum MenuBarIconRenderer {
    static let height: CGFloat = 22
    /// Space between items; the divider sits in the middle of it.
    static let itemGap: CGFloat = 13
    private static let edgePad: CGFloat = 2
    private static let markGap: CGFloat = 3
    private static let dividerHeight: CGFloat = 14
    private static let dividerAlpha: CGFloat = 0.35

    /// Labels (captions and the ↑/↓, R/W marks) are one size above the numbers.
    private static let captionFont = NSFont.systemFont(ofSize: 10, weight: .medium)
    /// Every number (single values and both rate lines) uses this one font.
    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
    private static let captionBaseline: CGFloat = 9.5
    private static let valueBaseline: CGFloat = 19.5
    private static let lineBaselines: (CGFloat, CGFloat) = (9.5, 19.5)

    private static var widths: [MenuBarItem: CGFloat] = [:]

    static func render(_ entries: [(item: MenuBarItem, text: MenuBarItemText)]) -> NSImage {
        guard !entries.isEmpty else { return emptyIcon }
        let itemWidths = entries.map { width(of: $0.item) }
        let size = NSSize(
            width: edgePad * 2 + itemWidths.reduce(0, +) + itemGap * CGFloat(entries.count - 1),
            height: height
        )
        let image = NSImage(size: size, flipped: true) { _ in
            var x = edgePad
            for (index, entry) in entries.enumerated() {
                if index > 0 {
                    NSColor.black.withAlphaComponent(dividerAlpha).setFill()
                    NSRect(x: x - (itemGap + 1) / 2, y: (height - dividerHeight) / 2, width: 1, height: dividerHeight).fill()
                }
                draw(entry.text, x: x, width: itemWidths[index])
                x += itemWidths[index] + itemGap
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    /// With nothing chosen the extra still needs something to click.
    private static let emptyIcon: NSImage = {
        let image = NSImage(systemSymbolName: "gauge.with.dots.needle.33percent", accessibilityDescription: "System Monitor")
            ?? NSImage(size: NSSize(width: 18, height: height))
        image.isTemplate = true
        return image
    }()

    private static func width(of item: MenuBarItem) -> CGFloat {
        if let cached = widths[item] { return cached }
        let width: CGFloat
        switch item.widestText {
        case .single(let caption, let value):
            width = max(measure(caption, captionFont), measure(value, valueFont))
        case .pair(let top, _):
            width = markWidth + markGap + measure(top.value, valueFont)
        }
        widths[item] = ceil(width)
        return ceil(width)
    }

    private static var markWidth: CGFloat {
        ["↑", "↓", "R", "W"].map { measure($0, captionFont) }.max() ?? 0
    }

    private static func measure(_ text: String, _ font: NSFont) -> CGFloat {
        NSAttributedString(string: text, attributes: [.font: font]).size().width
    }

    private static func draw(_ text: MenuBarItemText, x: CGFloat, width: CGFloat) {
        switch text {
        case .single(let caption, let value):
            draw(caption, font: captionFont, baseline: captionBaseline, x: x, width: width, alignment: .left)
            draw(value, font: valueFont, baseline: valueBaseline, x: x, width: width, alignment: .left)
        case .pair(let top, let bottom):
            for (line, baseline) in [(top, lineBaselines.0), (bottom, lineBaselines.1)] {
                draw(line.mark, font: captionFont, baseline: baseline, x: x, width: markWidth, alignment: .left)
                let valueX = x + markWidth + markGap
                draw(line.value, font: valueFont, baseline: baseline, x: valueX, width: width - (valueX - x), alignment: .right)
            }
        }
    }

    /// Flipped context: the line box's top sits one ascender above `baseline`.
    private static func draw(
        _ text: String,
        font: NSFont,
        baseline: CGFloat,
        x: CGFloat,
        width: CGFloat,
        alignment: NSTextAlignment
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph,
        ]
        let rect = NSRect(x: x, y: baseline - font.ascender, width: width, height: font.ascender - font.descender)
        NSAttributedString(string: text, attributes: attributes).draw(with: rect, options: [.usesLineFragmentOrigin])
    }
}
