import Foundation

public enum ControlAction: Codable, Equatable, Hashable, Sendable {
    case none
    case key(virtualKey: UInt16, flags: UInt64 = 0)
    case mediaPlayPause
    case mediaVolumeUp
    case mediaVolumeDown
    case mediaMute
    case mouseLeft
    case mouseRight

    public var title: String {
        switch self {
        case .none: return "None"
        case .key(let virtualKey, let flags):
            if flags != 0 { return "Key \(virtualKey)" }
            switch virtualKey {
            case 126: return "Arrow Up"
            case 125: return "Arrow Down"
            case 123: return "Arrow Left"
            case 124: return "Arrow Right"
            case 36: return "Return"
            case 53: return "Escape"
            case 49: return "Space"
            case 48: return "Tab"
            case 51: return "Delete"
            case 58: return "Left Option"
            case 61: return "Right Option"
            case 55: return "Left Command"
            case 54: return "Right Command"
            case 56: return "Left Shift"
            case 60: return "Right Shift"
            case 59: return "Left Control"
            case 62: return "Right Control"
            default: return "Key \(virtualKey)"
            }
        case .mediaPlayPause: return "Play/Pause"
        case .mediaVolumeUp: return "Volume Up"
        case .mediaVolumeDown: return "Volume Down"
        case .mediaMute: return "Mute"
        case .mouseLeft: return "Left click"
        case .mouseRight: return "Right click"
        }
    }
}

public struct ControlActionOption: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var action: ControlAction

    public init(id: String, title: String, action: ControlAction) {
        self.id = id
        self.title = title
        self.action = action
    }

    public static let unknownID = "unknown"

    public static func options(including action: ControlAction) -> [ControlActionOption] {
        if ControlAction.catalog.contains(where: { $0.action == action }) {
            return ControlAction.catalog
        }
        return ControlAction.catalog + [
            ControlActionOption(id: unknownID, title: action.title, action: action)
        ]
    }
}

public enum AnalogMode: String, Codable, CaseIterable, Sendable {
    case off
    case pointer
    case scroll
    case volume

    public var title: String {
        switch self {
        case .off: return "Off"
        case .pointer: return "Pointer"
        case .scroll: return "Scroll"
        case .volume: return "Volume"
        }
    }

    public var detail: String {
        switch self {
        case .off:
            return "Ignore analog motion. Digital clicks still work."
        case .pointer:
            return "Move the mouse. If the glass does not report X/Y, nothing moves until it does."
        case .scroll:
            return "Turn motion into scroll. Best for the click wheel and stick Y."
        case .volume:
            return "Turn motion into volume up/down."
        }
    }
}

public extension ControlAction {
    static let arrowUp = ControlAction.key(virtualKey: 126)
    static let arrowDown = ControlAction.key(virtualKey: 125)
    static let arrowLeft = ControlAction.key(virtualKey: 123)
    static let arrowRight = ControlAction.key(virtualKey: 124)
    static let returnKey = ControlAction.key(virtualKey: 36)
    static let escapeKey = ControlAction.key(virtualKey: 53)
    static let spaceKey = ControlAction.key(virtualKey: 49)
    static let tabKey = ControlAction.key(virtualKey: 48)
    static let deleteKey = ControlAction.key(virtualKey: 51)

    static let leftOptionKey = ControlAction.key(virtualKey: 58)
    static let rightOptionKey = ControlAction.key(virtualKey: 61)
    static let leftCommandKey = ControlAction.key(virtualKey: 55)
    static let rightCommandKey = ControlAction.key(virtualKey: 54)
    static let leftShiftKey = ControlAction.key(virtualKey: 56)
    static let rightShiftKey = ControlAction.key(virtualKey: 60)
    static let leftControlKey = ControlAction.key(virtualKey: 59)
    static let rightControlKey = ControlAction.key(virtualKey: 62)

    static let catalog: [ControlActionOption] = [
        .init(id: "none", title: "None", action: .none),
        .init(id: "mouseLeft", title: "Left click", action: .mouseLeft),
        .init(id: "mouseRight", title: "Right click", action: .mouseRight),
        .init(id: "leftOption", title: "Left Option", action: .leftOptionKey),
        .init(id: "rightOption", title: "Right Option", action: .rightOptionKey),
        .init(id: "leftCommand", title: "Left Command", action: .leftCommandKey),
        .init(id: "rightCommand", title: "Right Command", action: .rightCommandKey),
        .init(id: "leftShift", title: "Left Shift", action: .leftShiftKey),
        .init(id: "rightShift", title: "Right Shift", action: .rightShiftKey),
        .init(id: "leftControl", title: "Left Control", action: .leftControlKey),
        .init(id: "rightControl", title: "Right Control", action: .rightControlKey),
        .init(id: "arrowUp", title: "Arrow Up", action: .arrowUp),
        .init(id: "arrowDown", title: "Arrow Down", action: .arrowDown),
        .init(id: "arrowLeft", title: "Arrow Left", action: .arrowLeft),
        .init(id: "arrowRight", title: "Arrow Right", action: .arrowRight),
        .init(id: "return", title: "Return", action: .returnKey),
        .init(id: "escape", title: "Escape", action: .escapeKey),
        .init(id: "space", title: "Space", action: .spaceKey),
        .init(id: "tab", title: "Tab", action: .tabKey),
        .init(id: "delete", title: "Delete", action: .deleteKey),
        .init(id: "playPause", title: "Play/Pause", action: .mediaPlayPause),
        .init(id: "volumeUp", title: "Volume Up", action: .mediaVolumeUp),
        .init(id: "volumeDown", title: "Volume Down", action: .mediaVolumeDown),
        .init(id: "mute", title: "Mute", action: .mediaMute)
    ]

    var catalogID: String {
        Self.catalog.first { $0.action == self }?.id ?? ControlActionOption.unknownID
    }

    static func fromCatalogID(_ id: String) -> ControlAction {
        switch id {
        case "option": return .leftOptionKey
        case "command": return .leftCommandKey
        case "shift": return .leftShiftKey
        case "control": return .leftControlKey
        default: return catalog.first { $0.id == id }?.action ?? .none
        }
    }
}
