import SwiftUI

/// Every layout and look knob the lab can tune. Saved as you tweak; Copy
/// Design JSON hands the values to the real Control Box implementation.
struct CCDesign: Codable, Equatable {
    enum Surface: String, Codable, CaseIterable, Identifiable {
        case glass, clearGlass, fill, none
        var id: String { rawValue }
        var title: String {
            switch self {
            case .glass: "Glass"
            case .clearGlass: "Clear"
            case .fill: "Fill"
            case .none: "None"
            }
        }
    }

    /// Small modules (Night Shift, Sleep): one cell, or one column two rows tall.
    enum SmallSpan: String, Codable, CaseIterable, Identifiable {
        case square, tall
        var id: String { rawValue }
        var title: String { self == .square ? "1×1" : "1×2" }
    }

    /// Large modules (Caffeinate, Arrangement): two cells wide, one or two rows tall.
    enum LargeSpan: String, Codable, CaseIterable, Identifiable {
        case wide, block
        var id: String { rawValue }
        var title: String { self == .wide ? "2×1" : "2×2" }
    }

    enum SliderStyle: String, Codable, CaseIterable, Identifiable {
        case controlCenter, system
        var id: String { rawValue }
        var title: String { self == .controlCenter ? "Control Center" : "System" }
    }

    enum ActiveTint: String, Codable, CaseIterable, Identifiable {
        case accent, perModule
        var id: String { rawValue }
        var title: String { self == .accent ? "Accent" : "Per module" }
    }

    enum Transition: String, Codable, CaseIterable, Identifiable {
        case slide, crossfade, none
        var id: String { rawValue }
        var title: String {
            switch self {
            case .slide: "Slide"
            case .crossfade: "Crossfade"
            case .none: "None"
            }
        }
    }

    enum DurationLayout: String, Codable, CaseIterable, Identifiable {
        case chips, list
        var id: String { rawValue }
        var title: String { self == .chips ? "Chips" : "List" }
    }

    enum FooterStyle: String, Codable, CaseIterable, Identifiable {
        case capsules, text, icons
        var id: String { rawValue }
        var title: String {
            switch self {
            case .capsules: "Capsules"
            case .text: "Text"
            case .icons: "Icons"
            }
        }
    }

    /// When the large modules show their detail chevron.
    enum ChevronMode: String, Codable, CaseIterable, Identifiable {
        case hover, always
        var id: String { rawValue }
        var title: String { self == .hover ? "On hover" : "Always" }
    }

    /// What the Display module's slider moves when displays are not linked.
    enum DisplayScope: String, Codable, CaseIterable, Identifiable {
        case main, all
        var id: String { rawValue }
        var title: String { self == .main ? "Main display" : "All (scaled)" }
    }

    var panelWidth = 320.0
    var panelPadding = 12.0
    var panelCornerRadius = 24.0
    var spacing = 10.0
    var rowHeight = 66.0
    var sliderRowHeight = 66.0
    var moduleCornerRadius = 18.0
    var surface = Surface.glass
    var iconSize = 34.0
    var titleSize = 13.0
    var subtitleSize = 11.0
    var smallSpan = SmallSpan.tall
    var largeSpan = LargeSpan.wide
    var smallLabels = true
    var largeChevron = ChevronMode.hover
    var sliderStyle = SliderStyle.controlCenter
    var sliderHeight = 24.0
    var sliderTitles = true
    var displayScope = DisplayScope.main
    var activeTint = ActiveTint.accent
    var transition = Transition.slide
    var animateResize = true
    var stableHeight = false
    var detailBackButton = true
    var durationLayout = DurationLayout.chips
    var footer = true
    var footerStyle = FooterStyle.capsules
    var extraWidth = 300.0

    static let defaults = CCDesign()

    var unitWidth: Double {
        (panelWidth - 2 * panelPadding - 3 * spacing) / 4
    }
}
