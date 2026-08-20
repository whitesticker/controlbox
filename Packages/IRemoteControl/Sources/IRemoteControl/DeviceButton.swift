import Foundation

public enum DeviceButton: String, Codable, CaseIterable, Sendable {
    case cross, circle, square, triangle
    case dpadUp, dpadDown, dpadLeft, dpadRight
    case l1, r1, l2, r2, l3, r3
    case create, options, ps, touchpadClick

    case back, tv, siri, mute, playPause, power
    case volumeUp, volumeDown
    case clickSelect, clickSelectLong, clickUp, clickDown, clickLeft, clickRight

    public var title: String {
        switch self {
        case .cross: return "Cross"
        case .circle: return "Circle"
        case .square: return "Square"
        case .triangle: return "Triangle"
        case .dpadUp: return "D-pad Up"
        case .dpadDown: return "D-pad Down"
        case .dpadLeft: return "D-pad Left"
        case .dpadRight: return "D-pad Right"
        case .l1: return "L1"
        case .r1: return "R1"
        case .l2: return "L2"
        case .r2: return "R2"
        case .l3: return "L3"
        case .r3: return "R3"
        case .create: return "Create"
        case .options: return "Options"
        case .ps: return "PS"
        case .touchpadClick: return "Touchpad click"
        case .back: return "Back"
        case .tv: return "TV"
        case .siri: return "Siri"
        case .mute: return "Mute"
        case .playPause: return "Play/Pause"
        case .power: return "Power"
        case .volumeUp: return "Volume Up"
        case .volumeDown: return "Volume Down"
        case .clickSelect: return "Select"
        case .clickSelectLong: return "Select hold"
        case .clickUp: return "Clickpad Up"
        case .clickDown: return "Clickpad Down"
        case .clickLeft: return "Clickpad Left"
        case .clickRight: return "Clickpad Right"
        }
    }

    public static let appleTVButtons: [DeviceButton] = appleTVGroups.flatMap(\.buttons)

    public static let dualSenseButtons: [DeviceButton] = dualSenseGroups.flatMap(\.buttons)

    public static let appleTVGroups: [DeviceButtonGroup] = [
        DeviceButtonGroup(
            id: "clickpad",
            title: "Clickpad",
            buttons: [.clickUp, .clickDown, .clickLeft, .clickRight, .clickSelect]
        ),
        DeviceButtonGroup(
            id: "media",
            title: "Media",
            buttons: [.playPause, .volumeUp, .volumeDown, .mute]
        ),
        DeviceButtonGroup(
            id: "navigation",
            title: "Back & TV",
            buttons: [.back, .tv]
        ),
        DeviceButtonGroup(
            id: "siri",
            title: "Siri",
            buttons: [.siri]
        ),
        DeviceButtonGroup(
            id: "power",
            title: "Power",
            buttons: [.power]
        )
    ]

    public static let dualSenseGroups: [DeviceButtonGroup] = [
        DeviceButtonGroup(
            id: "face",
            title: "Face buttons",
            buttons: [.cross, .circle, .square, .triangle]
        ),
        DeviceButtonGroup(
            id: "dpad",
            title: "D-pad",
            buttons: [.dpadUp, .dpadDown, .dpadLeft, .dpadRight]
        ),
        DeviceButtonGroup(
            id: "shoulders",
            title: "Shoulders",
            buttons: [.l1, .r1, .l2, .r2, .l3, .r3]
        ),
        DeviceButtonGroup(
            id: "system",
            title: "System",
            buttons: [.create, .options, .ps, .touchpadClick]
        )
    ]
}

public struct DeviceButtonGroup: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var buttons: [DeviceButton]

    public init(id: String, title: String, buttons: [DeviceButton]) {
        self.id = id
        self.title = title
        self.buttons = buttons
    }
}

public enum AnalogSource: String, Codable, CaseIterable, Sendable {
    case dualSenseLeftStick
    case dualSenseRightStick
    case dualSenseTouchpad
    case appleTVClickpad
    case appleTVWheel
}

public struct AnalogSample: Equatable, Sendable {
    public var x: Float
    public var y: Float
    public var active: Bool

    public init(x: Float = 0, y: Float = 0, active: Bool = false) {
        self.x = x
        self.y = y
        self.active = active
    }
}

public struct ControlFrame: Equatable, Sendable {
    public var buttons: [DeviceButton: Bool]
    public var analog: [AnalogSource: AnalogSample]
    public var wheelDegrees: Double

    public init(
        buttons: [DeviceButton: Bool] = [:],
        analog: [AnalogSource: AnalogSample] = [:],
        wheelDegrees: Double = 0
    ) {
        self.buttons = buttons
        self.analog = analog
        self.wheelDegrees = wheelDegrees
    }
}
