import Foundation

/// Face-button and system-button labels for a recognised gamepad family.
/// Stored raw values are stable (`sony`, `xbox`, `nintendo`, `generic`).
public enum GamepadLayout: String, Codable, Sendable, CaseIterable {
    case sony
    case xbox
    case nintendo
    case generic

    public var title: String {
        switch self {
        case .sony: return "DualSense"
        case .xbox: return "Xbox layout"
        case .nintendo: return "Nintendo layout"
        case .generic: return "Generic layout"
        }
    }

    public var brand: String {
        switch self {
        case .sony: return "Sony"
        case .xbox: return "Microsoft"
        case .nintendo: return "Nintendo"
        case .generic: return "Other"
        }
    }

    public var homeButtonName: String {
        switch self {
        case .sony: return "PS"
        case .xbox: return "Xbox"
        case .nintendo, .generic: return "Home"
        }
    }

    public func label(for button: DeviceButton) -> String {
        switch button {
        case .cross:
            switch self {
            case .sony: return "Cross"
            case .xbox, .generic: return "A"
            case .nintendo: return "B"
            }
        case .circle:
            switch self {
            case .sony: return "Circle"
            case .xbox, .generic: return "B"
            case .nintendo: return "A"
            }
        case .square:
            switch self {
            case .sony: return "Square"
            case .xbox, .generic: return "X"
            case .nintendo: return "Y"
            }
        case .triangle:
            switch self {
            case .sony: return "Triangle"
            case .xbox, .generic: return "Y"
            case .nintendo: return "X"
            }
        case .create:
            switch self {
            case .sony: return "Create"
            case .xbox: return "View"
            case .nintendo: return "−"
            case .generic: return "Select"
            }
        case .options:
            switch self {
            case .sony: return "Options"
            case .xbox: return "Menu"
            case .nintendo: return "+"
            case .generic: return "Start"
            }
        case .ps:
            switch self {
            case .sony: return "PS"
            case .xbox: return "Xbox"
            case .nintendo, .generic: return "Home"
            }
        case .l1:
            switch self {
            case .sony, .generic: return "L1"
            case .xbox: return "LB"
            case .nintendo: return "L"
            }
        case .r1:
            switch self {
            case .sony, .generic: return "R1"
            case .xbox: return "RB"
            case .nintendo: return "R"
            }
        case .l2:
            switch self {
            case .sony, .generic: return "L2"
            case .xbox: return "LT"
            case .nintendo: return "ZL"
            }
        case .r2:
            switch self {
            case .sony, .generic: return "R2"
            case .xbox: return "RT"
            case .nintendo: return "ZR"
            }
        case .l3:
            return "Left stick click"
        case .r3:
            return "Right stick click"
        default:
            return button.title
        }
    }
}
