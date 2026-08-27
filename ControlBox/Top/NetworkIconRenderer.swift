import AppKit

// Renders the two-line ↑/↓ network speed image shown in the menu bar.
// The image is a template (monochrome) so it adapts to light/dark menu bars.
enum NetworkIconRenderer {
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
    private static let leftPad: CGFloat = 2
    private static let rightPad: CGFloat = 2
    private static let arrowGap: CGFloat = 3
    private static let lineHeight: CGFloat = 9

    // Fixed canvas size, computed once from a worst-case reference string
    // ("999.9 K/s" -- the longest string Fmt.speedCompact can produce: up to
    // 3 digits, or 4 with a decimal point, plus a 3-character unit).
    // Rendering at a CONSTANT width regardless of actual digit count matters
    // because NSStatusItem repositions neighboring menu bar items whenever
    // a variable-length item's width changes -- a width that jitters with
    // the displayed numbers makes the icon (and its popover anchor) shift
    // left/right on every update, and can make a click land on a
    // neighboring item entirely if the width changes between aiming and
    // clicking.
    //
    // Each line is arrow on the left, speed on the right, padding between.
    // Short speeds stay right-aligned in the speed column so both edges of
    // the canvas stay occupied ("↑    12 K/s" vs "↑ 999.9 K/s").
    private static let attrs: [NSAttributedString.Key: Any] = [.font: font]

    private static let arrowSlotWidth: CGFloat = {
        let up = NSAttributedString(string: "↑", attributes: attrs).size().width
        let down = NSAttributedString(string: "↓", attributes: attrs).size().width
        return ceil(max(up, down))
    }()

    private static let speedColumnWidth: CGFloat = {
        ceil(NSAttributedString(string: "999.9 K/s", attributes: attrs).size().width)
    }()

    private static let canvasSize = NSSize(
        width: leftPad + arrowSlotWidth + arrowGap + speedColumnWidth + rightPad,
        height: 18
    )

    static func render(up: Double, down: Double) -> NSImage {
        let (upNum, upUnit) = Fmt.speedCompact(up)
        let (downNum, downUnit) = Fmt.speedCompact(down)
        let size = canvasSize
        let image = NSImage(size: size, flipped: true) { rect in
            let topY = (rect.height - lineHeight * 2) / 2
            drawLine(
                arrow: "↑",
                speed: "\(upNum) \(upUnit)",
                y: topY,
                in: rect
            )
            drawLine(
                arrow: "↓",
                speed: "\(downNum) \(downUnit)",
                y: topY + lineHeight,
                in: rect
            )
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func drawLine(arrow: String, speed: String, y: CGFloat, in rect: NSRect) {
        let drawAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,
        ]
        let arrowRect = NSRect(x: leftPad, y: y, width: arrowSlotWidth, height: lineHeight)
        NSAttributedString(string: arrow, attributes: drawAttrs)
            .draw(with: arrowRect, options: [.usesLineFragmentOrigin, .usesFontLeading])

        let speedPara = NSMutableParagraphStyle()
        speedPara.alignment = .right
        var speedAttrs = drawAttrs
        speedAttrs[.paragraphStyle] = speedPara
        let speedX = leftPad + arrowSlotWidth + arrowGap
        let speedRect = NSRect(
            x: speedX,
            y: y,
            width: rect.width - speedX - rightPad,
            height: lineHeight
        )
        NSAttributedString(string: speed, attributes: speedAttrs)
            .draw(with: speedRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
    }
}
