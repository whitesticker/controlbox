import Foundation

public enum DeviceButton: String, Codable, CaseIterable, Sendable {
    case cross, circle, square, triangle
    case dpadUp, dpadDown, dpadLeft, dpadRight
    case l1, r1, l2, r2, l3, r3
    case create, options, ps, touchpadClick
    case touchpadOneFinger, touchpadTwoFinger

    case back, tv, siri, mute, playPause, power
    case volumeUp, volumeDown
    case clickSelect, clickSelectLong, clickUp, clickDown, clickLeft, clickRight
    case mxGesture, mxGestureUp, mxGestureDown, mxGestureLeft, mxGestureRight
    case mxBack, mxForward, mxSmartShift, mxModeShift, mxHaptic
    case mxLeft, mxRight, mxMiddle
    case mxWheelUp, mxWheelDown, mxThumbLeft, mxThumbRight

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
        case .l3: return "Left stick click"
        case .r3: return "Right stick click"
        case .create: return "Create"
        case .options: return "Options"
        case .ps: return "PS"
        case .touchpadClick: return "Touchpad click"
        case .touchpadOneFinger: return "1-finger swipe"
        case .touchpadTwoFinger: return "2-finger swipe"
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
        case .mxGesture: return "Gesture tap"
        case .mxGestureUp: return "Gesture up"
        case .mxGestureDown: return "Gesture down"
        case .mxGestureLeft: return "Gesture left"
        case .mxGestureRight: return "Gesture right"
        case .mxBack: return "Back"
        case .mxForward: return "Forward"
        case .mxSmartShift: return "Mode shift"
        case .mxModeShift: return "DPI"
        case .mxHaptic: return "Haptic"
        case .mxLeft: return "Left click"
        case .mxRight: return "Right click"
        case .mxMiddle: return "Middle click"
        case .mxWheelUp: return "Wheel up"
        case .mxWheelDown: return "Wheel down"
        case .mxThumbLeft: return "Thumb wheel left"
        case .mxThumbRight: return "Thumb wheel right"
        }
    }

    public static let appleTVButtons: [DeviceButton] = appleTVGroups.flatMap(\.buttons)

    public static let dualSenseButtons: [DeviceButton] = dualSenseGroups.flatMap(\.buttons)
        + [.touchpadOneFinger, .touchpadTwoFinger]

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

    public static let mxMasterGroups: [DeviceButtonGroup] = [
        DeviceButtonGroup(
            id: "buttons",
            title: "Buttons",
            buttons: [.mxHaptic, .mxBack, .mxForward, .mxSmartShift, .mxModeShift, .mxMiddle, .mxLeft, .mxRight]
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
            buttons: [.l1, .r1, .l2, .r2]
        ),
        DeviceButtonGroup(
            id: "sticks",
            title: "Stick clicks",
            buttons: [.l3, .r3]
        ),
        DeviceButtonGroup(
            id: "system",
            title: "System",
            buttons: [.create, .options, .ps, .touchpadClick]
        )
    ]

    /// Hold-to-swipe owners: MX haptic / gesture button, DualSense finger counts.
    public var canOwnGestures: Bool {
        switch self {
        case .mxHaptic, .touchpadOneFinger, .touchpadTwoFinger:
            return true
        default:
            return false
        }
    }
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
    case dualSenseTouchpadSecondary
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
    public var scrollY: Double
    public var scrollX: Double
    public var gestureSlot: DeviceButton?
    public var gestureOwner: DeviceButton?
    public var gestureActive: Bool
    public var gestureX: Double
    public var gestureY: Double

    public init(
        buttons: [DeviceButton: Bool] = [:],
        analog: [AnalogSource: AnalogSample] = [:],
        wheelDegrees: Double = 0,
        scrollY: Double = 0,
        scrollX: Double = 0,
        gestureSlot: DeviceButton? = nil,
        gestureOwner: DeviceButton? = nil,
        gestureActive: Bool = false,
        gestureX: Double = 0,
        gestureY: Double = 0
    ) {
        self.buttons = buttons
        self.analog = analog
        self.wheelDegrees = wheelDegrees
        self.scrollY = scrollY
        self.scrollX = scrollX
        self.gestureSlot = gestureSlot
        self.gestureOwner = gestureOwner
        self.gestureActive = gestureActive
        self.gestureX = gestureX
        self.gestureY = gestureY
    }
}
