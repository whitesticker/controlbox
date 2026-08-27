import AppKit

// Renders the two-line ↑/↓ network speed image shown in the menu bar.
// The image is a template (monochrome) so it adapts to light/dark menu bars.
enum NetworkIconRenderer {
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)

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
    private static let canvasSize: NSSize = {
        let para = NSMutableParagraphStyle()
        para.alignment = .right
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: para]
        let reference = NSAttributedString(string: "↑999.9 K/s\n↓999.9 K/s", attributes: attrs)
        let bounds = reference.boundingRect(
            with: NSSize(width: 200, height: 100),
            options: [.usesLineFragmentOrigin]
        )
        return NSSize(width: ceil(bounds.width) + 4, height: 18)
    }()

    static func render(up: Double, down: Double) -> NSImage {
        let (upNum, upUnit) = Fmt.speedCompact(up)
        let (downNum, downUnit) = Fmt.speedCompact(down)

        let para = NSMutableParagraphStyle()
        para.alignment = .right
        para.lineSpacing = 0
        para.maximumLineHeight = 9
        para.minimumLineHeight = 9

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,
            .paragraphStyle: para,
        ]
        let text = "↑\(upNum) \(upUnit)\n↓\(downNum) \(downUnit)"
        let attr = NSAttributedString(string: text, attributes: attrs)

        let width = canvasSize.width
        let height = canvasSize.height

        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        let textHeight = ceil(attr.boundingRect(
            with: NSSize(width: width, height: 100),
            options: [.usesLineFragmentOrigin]
        ).height)
        let drawRect = NSRect(x: 0, y: (height - textHeight) / 2,
                              width: width - 2, height: textHeight)
        attr.draw(with: drawRect, options: [.usesLineFragmentOrigin])
        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}
