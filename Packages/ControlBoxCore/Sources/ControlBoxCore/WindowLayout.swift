import AppKit
import CoreGraphics
import Foundation

/// 3×3 pointer cells. Result frames are quarters, halves, or the full visible area.
public enum ThrowZone: Int, Equatable, Sendable, CaseIterable {
    case topLeft = 0
    case top
    case topRight
    case left
    case maximize
    case right
    case bottomLeft
    case bottom
    case bottomRight

    public var column: Int { rawValue % 3 }
    public var row: Int { rawValue / 3 }

    public static func cell(column: Int, row: Int) -> ThrowZone {
        ThrowZone(rawValue: row * 3 + column) ?? .maximize
    }
}

public enum WindowLayout {
    public static let hysteresis: CGFloat = 8
    public static let organizeTravelLimit: CGFloat = 8

    public static func screen(containingQuartz point: CGPoint) -> NSScreen? {
        let screens = NSScreen.screens
        return screens.first { quartzFrame(from: $0.frame).insetBy(dx: -2, dy: -2).contains(point) }
            ?? screens.first
    }

    public static func visibleFrame(containingQuartz point: CGPoint) -> CGRect {
        guard let screen = screen(containingQuartz: point) else {
            return CGRect(x: 0, y: 0, width: 1440, height: 900)
        }
        return quartzFrame(from: screen.visibleFrame)
    }

    public static func quartzFrame(from cocoa: CGRect) -> CGRect {
        guard let primary = primaryScreen() else { return cocoa }
        var quartz = cocoa
        quartz.origin.y = primary.frame.maxY - cocoa.maxY
        return quartz
    }

    public static func cocoaFrame(from quartz: CGRect) -> CGRect {
        guard let primary = primaryScreen() else { return quartz }
        var cocoa = quartz
        cocoa.origin.y = primary.frame.maxY - quartz.maxY
        return cocoa
    }

    public static func zone(at point: CGPoint, in frame: CGRect, previous: ThrowZone?) -> ThrowZone {
        guard frame.width > 1, frame.height > 1 else { return .maximize }
        if let previous {
            let stay = cellRect(column: previous.column, row: previous.row, in: frame)
                .insetBy(dx: -hysteresis, dy: -hysteresis)
            if stay.contains(point) {
                return previous
            }
        }
        let column = clampIndex((point.x - frame.minX) / frame.width * 3)
        let row = clampIndex((point.y - frame.minY) / frame.height * 3)
        return .cell(column: column, row: row)
    }

    public static func frame(for zone: ThrowZone, in visible: CGRect) -> CGRect {
        let halfW = visible.width / 2
        let halfH = visible.height / 2
        let midX = visible.minX + halfW
        let midY = visible.minY + halfH
        switch zone {
        case .topLeft:
            return CGRect(x: visible.minX, y: visible.minY, width: halfW, height: halfH)
        case .top:
            return CGRect(x: visible.minX, y: visible.minY, width: visible.width, height: halfH)
        case .topRight:
            return CGRect(x: midX, y: visible.minY, width: halfW, height: halfH)
        case .left:
            return CGRect(x: visible.minX, y: visible.minY, width: halfW, height: visible.height)
        case .maximize:
            return visible
        case .right:
            return CGRect(x: midX, y: visible.minY, width: halfW, height: visible.height)
        case .bottomLeft:
            return CGRect(x: visible.minX, y: midY, width: halfW, height: halfH)
        case .bottom:
            return CGRect(x: visible.minX, y: midY, width: visible.width, height: halfH)
        case .bottomRight:
            return CGRect(x: midX, y: midY, width: halfW, height: halfH)
        }
    }

    public static func grid(count: Int, in visible: CGRect) -> [CGRect] {
        guard count > 0 else { return [] }
        if count == 1 { return [visible] }
        let halfW = visible.width / 2
        let halfH = visible.height / 2
        let midX = visible.minX + halfW
        let midY = visible.minY + halfH
        if count == 2 {
            return [
                CGRect(x: visible.minX, y: visible.minY, width: halfW, height: visible.height),
                CGRect(x: midX, y: visible.minY, width: halfW, height: visible.height)
            ]
        }
        if count == 3 {
            return [
                CGRect(x: visible.minX, y: visible.minY, width: halfW, height: visible.height),
                CGRect(x: midX, y: visible.minY, width: halfW, height: halfH),
                CGRect(x: midX, y: midY, width: halfW, height: halfH)
            ]
        }
        if count == 4 {
            return [
                CGRect(x: visible.minX, y: visible.minY, width: halfW, height: halfH),
                CGRect(x: midX, y: visible.minY, width: halfW, height: halfH),
                CGRect(x: visible.minX, y: midY, width: halfW, height: halfH),
                CGRect(x: midX, y: midY, width: halfW, height: halfH)
            ]
        }
        let cols = Int(ceil(sqrt(Double(count))))
        let rows = Int(ceil(Double(count) / Double(cols)))
        var frames: [CGRect] = []
        var index = 0
        for row in 0..<rows {
            let remaining = count - index
            let colsInRow = row == rows - 1 ? remaining : cols
            let cellW = visible.width / CGFloat(colsInRow)
            let cellH = visible.height / CGFloat(rows)
            for col in 0..<colsInRow {
                frames.append(
                    CGRect(
                        x: visible.minX + CGFloat(col) * cellW,
                        y: visible.minY + CGFloat(row) * cellH,
                        width: cellW,
                        height: cellH
                    )
                )
                index += 1
            }
        }
        return frames
    }

    private static func cellRect(column: Int, row: Int, in frame: CGRect) -> CGRect {
        let width = frame.width / 3
        let height = frame.height / 3
        return CGRect(
            x: frame.minX + CGFloat(column) * width,
            y: frame.minY + CGFloat(row) * height,
            width: width,
            height: height
        )
    }

    private static func clampIndex(_ value: CGFloat) -> Int {
        min(2, max(0, Int(floor(value))))
    }

    private static func primaryScreen() -> NSScreen? {
        NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first
    }
}
