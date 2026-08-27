import Foundation

public enum GesturePreset: String, Codable, CaseIterable, Sendable {
    case windowNavigation
    case mediaControls
    case appNavigation
    case custom

    public var title: String {
        switch self {
        case .windowNavigation: return "Window navigation"
        case .mediaControls: return "Media controls"
        case .appNavigation: return "App navigation"
        case .custom: return "Custom"
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = GesturePreset(rawValue: raw) ?? .custom
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum GestureSlot: String, Codable, CaseIterable, Sendable {
    case click
    case up
    case down
    case left
    case right

    public var title: String {
        switch self {
        case .click: return "Click"
        case .up: return "Hold + move up"
        case .down: return "Hold + move down"
        case .left: return "Hold + move left"
        case .right: return "Hold + move right"
        }
    }

    public var deviceButton: DeviceButton {
        switch self {
        case .click: return .mxGesture
        case .up: return .mxGestureUp
        case .down: return .mxGestureDown
        case .left: return .mxGestureLeft
        case .right: return .mxGestureRight
        }
    }

    public static func slot(for button: DeviceButton) -> GestureSlot? {
        switch button {
        case .mxGesture: return .click
        case .mxGestureUp: return .up
        case .mxGestureDown: return .down
        case .mxGestureLeft: return .left
        case .mxGestureRight: return .right
        default: return nil
        }
    }
}

public struct GestureSet: Codable, Equatable, Sendable {
    public var preset: GesturePreset
    public var click: ControlAction
    public var up: ControlAction
    public var down: ControlAction
    public var left: ControlAction
    public var right: ControlAction

    public init(
        preset: GesturePreset,
        click: ControlAction,
        up: ControlAction,
        down: ControlAction,
        left: ControlAction,
        right: ControlAction
    ) {
        self.preset = preset
        self.click = click
        self.up = up
        self.down = down
        self.left = left
        self.right = right
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let preset = try container.decode(GesturePreset.self, forKey: .preset)
        if preset == .appNavigation {
            self = .named(.appNavigation)
            return
        }
        self.preset = preset
        self.click = try container.decode(ControlAction.self, forKey: .click)
        self.up = try container.decode(ControlAction.self, forKey: .up)
        self.down = try container.decode(ControlAction.self, forKey: .down)
        self.left = try container.decode(ControlAction.self, forKey: .left)
        self.right = try container.decode(ControlAction.self, forKey: .right)
    }

    public func action(for slot: GestureSlot) -> ControlAction {
        switch slot {
        case .click: return click
        case .up: return up
        case .down: return down
        case .left: return left
        case .right: return right
        }
    }

    public mutating func setAction(_ action: ControlAction, for slot: GestureSlot) {
        switch slot {
        case .click: click = action
        case .up: up = action
        case .down: down = action
        case .left: left = action
        case .right: right = action
        }
        preset = Self.matchingPreset(click: click, up: up, down: down, left: left, right: right)
    }

    public static func named(_ preset: GesturePreset) -> GestureSet {
        switch preset {
        case .windowNavigation:
            return GestureSet(
                preset: .windowNavigation,
                click: .missionControl,
                up: .missionControl,
                down: .appExpose,
                left: .spaceLeft,
                right: .spaceRight
            )
        case .mediaControls:
            return GestureSet(
                preset: .mediaControls,
                click: .mediaPlayPause,
                up: .mediaVolumeUp,
                down: .mediaVolumeDown,
                left: .mediaPrevious,
                right: .mediaNext
            )
        case .appNavigation:
            return GestureSet(
                preset: .appNavigation,
                click: .switchApplication,
                up: .missionControl,
                down: .appExpose,
                left: .switchApplication,
                right: .switchApplicationBack
            )
        case .custom:
            return GestureSet(
                preset: .custom,
                click: .none,
                up: .none,
                down: .none,
                left: .none,
                right: .none
            )
        }
    }

    private static func matchingPreset(
        click: ControlAction,
        up: ControlAction,
        down: ControlAction,
        left: ControlAction,
        right: ControlAction
    ) -> GesturePreset {
        for preset in GesturePreset.allCases where preset != .custom {
            let candidate = named(preset)
            if candidate.click == click,
               candidate.up == up,
               candidate.down == down,
               candidate.left == left,
               candidate.right == right {
                return preset
            }
        }
        return .custom
    }
}
