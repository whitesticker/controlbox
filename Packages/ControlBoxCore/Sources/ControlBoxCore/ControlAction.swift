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
    case missionControl
    case appExpose
    case showDesktop
    case spaceLeft
    case spaceRight
    case browserBack
    case browserForward
    case tabPrevious
    case tabNext
    case gestures
    case mediaNext
    case mediaPrevious
    case switchApplication
    case switchApplicationBack
    case screenCapture
    case closeWindow
    case scroll

    public var title: String {
        switch self {
        case .none: return "None"
        case .scroll: return "Scroll"
        case .key(let virtualKey, let flags):
            return ShortcutFormatter.describe(virtualKey: virtualKey, flags: flags)
        case .mediaPlayPause: return "Play/Pause"
        case .mediaVolumeUp: return "Volume Up"
        case .mediaVolumeDown: return "Volume Down"
        case .mediaMute: return "Mute"
        case .mouseLeft: return "Left click"
        case .mouseRight: return "Right click"
        case .missionControl: return "Mission Control"
        case .appExpose: return "App Expose"
        case .showDesktop: return "Show Desktop"
        case .spaceLeft: return "Previous desktop"
        case .spaceRight: return "Next desktop"
        case .browserBack: return "Back"
        case .browserForward: return "Forward"
        case .tabPrevious: return "Previous tab"
        case .tabNext: return "Next tab"
        case .gestures: return "Gestures"
        case .mediaNext: return "Next track"
        case .mediaPrevious: return "Previous track"
        case .switchApplication: return "Next application"
        case .switchApplicationBack: return "Previous application"
        case .screenCapture: return "Screen capture"
        case .closeWindow: return "Close window"
        }
    }

    public var isSystemNavigation: Bool {
        switch self {
        case .missionControl, .appExpose, .showDesktop, .spaceLeft, .spaceRight,
             .switchApplication, .switchApplicationBack:
            return true
        default:
            return false
        }
    }

    var isLiveVolume: Bool {
        switch self {
        case .mediaVolumeUp, .mediaVolumeDown: return true
        default: return false
        }
    }

    public var isTabSwitch: Bool {
        switch self {
        case .tabPrevious, .tabNext: return true
        default: return false
        }
    }

    var isLiveSpace: Bool {
        switch self {
        case .spaceLeft, .spaceRight: return true
        default: return false
        }
    }

    var isLiveMissionSwipe: Bool {
        switch self {
        case .missionControl, .appExpose: return true
        default: return false
        }
    }

    /// One-shot hold+move. Not live DockSwipe.
    var isDiscreteSwipe: Bool {
        switch self {
        case .mediaNext, .mediaPrevious, .mediaPlayPause, .mediaMute,
             .switchApplication, .switchApplicationBack,
             .browserBack, .browserForward,
             .tabPrevious, .tabNext:
            return true
        default:
            return false
        }
    }

    /// Silent discrete actions that need an on-screen cue.
    var showsActionHUD: Bool {
        switch self {
        case .mediaNext, .mediaPrevious, .mediaPlayPause, .mediaMute,
             .browserBack, .browserForward,
             .tabPrevious, .tabNext:
            return true
        default:
            return false
        }
    }

    var actionHUDSymbol: String? {
        switch self {
        case .mediaNext: return "forward.end.fill"
        case .mediaPrevious: return "backward.end.fill"
        case .mediaPlayPause: return "playpause.fill"
        case .mediaMute: return "speaker.slash.fill"
        case .browserBack: return "chevron.backward"
        case .browserForward: return "chevron.forward"
        case .tabPrevious: return "arrow.left.to.line"
        case .tabNext: return "arrow.right.to.line"
        default: return nil
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
    public static let customID = "custom"

    public static func options(including action: ControlAction) -> [ControlActionOption] {
        var items = ControlAction.catalog
        if case .key = action, ControlAction.catalog.contains(where: { $0.action == action }) == false {
            items.append(ControlActionOption(id: customID, title: action.title, action: action))
        } else {
            items.append(ControlActionOption(id: customID, title: "Custom Shortcut…", action: .none))
        }
        return items
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
        .init(id: "missionControl", title: "Mission Control", action: .missionControl),
        .init(id: "appExpose", title: "App Expose", action: .appExpose),
        .init(id: "showDesktop", title: "Show Desktop", action: .showDesktop),
        .init(id: "spaceLeft", title: "Previous desktop", action: .spaceLeft),
        .init(id: "spaceRight", title: "Next desktop", action: .spaceRight),
        .init(id: "browserBack", title: "Back", action: .browserBack),
        .init(id: "browserForward", title: "Forward", action: .browserForward),
        .init(id: "tabPrevious", title: "Previous tab", action: .tabPrevious),
        .init(id: "tabNext", title: "Next tab", action: .tabNext),
        .init(id: "switchApplication", title: "Next application", action: .switchApplication),
        .init(id: "switchApplicationBack", title: "Previous application", action: .switchApplicationBack),
        .init(id: "screenCapture", title: "Screen capture", action: .screenCapture),
        .init(id: "closeWindow", title: "Close window", action: .closeWindow),
        .init(id: "mediaNext", title: "Next track", action: .mediaNext),
        .init(id: "mediaPrevious", title: "Previous track", action: .mediaPrevious),
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
        if self == .gestures { return "gestures" }
        if self == .scroll { return "scroll" }
        if let id = Self.catalog.first(where: { $0.action == self })?.id {
            return id
        }
        if case .key = self {
            return ControlActionOption.customID
        }
        return ControlActionOption.unknownID
    }

    public static func fromCatalogID(_ id: String) -> ControlAction {
        if id == "gestures" { return .gestures }
        if id == "scroll" { return .scroll }
        switch id {
        case "option": return .leftOptionKey
        case "command": return .leftCommandKey
        case "shift": return .leftShiftKey
        case "control": return .leftControlKey
        default: return catalog.first { $0.id == id }?.action ?? .none
        }
    }
}
