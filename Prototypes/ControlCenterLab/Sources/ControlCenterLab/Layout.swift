import CoreGraphics

/// One module's cell on the 4-column grid.
struct Placement: Identifiable, Equatable {
    let kind: ModuleKind
    let col: Int
    let row: Int
    let width: Int
    let height: Int
    var id: String { kind.rawValue }
}

/// Dense first-fit packing on a 4-column grid, in the user's order, so a
/// later small module backfills a gap an earlier large one left (the way
/// Control Center fills its grid). Sliders span the full width, so a row is
/// either all sliders or all tiles and every row has one height.
struct GridLayout {
    static let columns = 4

    let placements: [Placement]
    let rowHeights: [Double]
    let design: CCDesign

    init(order: [ModuleKind], design: CCDesign) {
        self.design = design
        var occupied: [[Bool]] = []
        var sliderRows = Set<Int>()
        var placements: [Placement] = []

        func fits(_ col: Int, _ row: Int, _ w: Int, _ h: Int) -> Bool {
            for r in row..<(row + h) {
                guard r < occupied.count else { continue }
                for c in col..<(col + w) where occupied[r][c] { return false }
            }
            return true
        }

        for kind in order {
            let (w, h) = Self.span(kind, design: design)
            var row = 0
            placed: while true {
                for col in 0...(Self.columns - w) where fits(col, row, w, h) {
                    // A tile never shares a row with a slider and vice versa.
                    let rows = Set(row..<(row + h))
                    let isSlider = kind.size == .slider
                    let clash = rows.contains { r in
                        r < occupied.count && occupied[r].contains(true) && sliderRows.contains(r) != isSlider
                    }
                    if clash { continue }
                    while occupied.count < row + h { occupied.append(Array(repeating: false, count: Self.columns)) }
                    for r in rows { for c in col..<(col + w) { occupied[r][c] = true } }
                    if isSlider { sliderRows.formUnion(rows) }
                    placements.append(Placement(kind: kind, col: col, row: row, width: w, height: h))
                    break placed
                }
                row += 1
            }
        }
        self.placements = placements
        rowHeights = (0..<occupied.count).map { sliderRows.contains($0) ? design.sliderRowHeight : design.rowHeight }
    }

    static func span(_ kind: ModuleKind, design: CCDesign) -> (Int, Int) {
        switch kind.size {
        case .small: (1, design.smallSpan == .tall ? 2 : 1)
        case .large: (2, design.largeSpan == .block ? 2 : 1)
        case .slider: (4, 1)
        }
    }

    var size: CGSize {
        let width = design.panelWidth - 2 * design.panelPadding
        let height = rowHeights.reduce(0, +) + Double(max(rowHeights.count - 1, 0)) * design.spacing
        return CGSize(width: width, height: max(height, 0))
    }

    func frame(_ p: Placement) -> CGRect {
        let unit = design.unitWidth
        let x = Double(p.col) * (unit + design.spacing)
        let y = rowHeights.prefix(p.row).reduce(0, +) + Double(p.row) * design.spacing
        let width = Double(p.width) * unit + Double(p.width - 1) * design.spacing
        let height = rowHeights[p.row..<(p.row + p.height)].reduce(0, +) + Double(p.height - 1) * design.spacing
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
