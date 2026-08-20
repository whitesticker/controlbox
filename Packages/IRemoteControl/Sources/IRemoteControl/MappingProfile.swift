import Foundation

public struct MappingProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var summary: String
    public var bindings: [DeviceButton: ControlAction]
    public var leftStick: AnalogMode
    public var rightStick: AnalogMode
    public var dualSenseTouchpad: AnalogMode
    public var appleTVClickpad: AnalogMode
    public var appleTVWheel: AnalogMode
    public var pointerAcceleration: Bool?
    public var pointerAccelerationAmount: Double?
    public var stickyTargeting: Bool?

    public init(
        id: String = UUID().uuidString,
        name: String,
        summary: String = "",
        bindings: [DeviceButton: ControlAction],
        leftStick: AnalogMode = .off,
        rightStick: AnalogMode = .off,
        dualSenseTouchpad: AnalogMode = .off,
        appleTVClickpad: AnalogMode = .off,
        appleTVWheel: AnalogMode = .off,
        pointerAcceleration: Bool? = true,
        pointerAccelerationAmount: Double? = 0.3,
        stickyTargeting: Bool? = false
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.bindings = bindings
        self.leftStick = leftStick
        self.rightStick = rightStick
        self.dualSenseTouchpad = dualSenseTouchpad
        self.appleTVClickpad = appleTVClickpad
        self.appleTVWheel = appleTVWheel
        self.pointerAcceleration = pointerAcceleration
        self.pointerAccelerationAmount = pointerAccelerationAmount
        self.stickyTargeting = stickyTargeting
    }

    public func mode(for source: AnalogSource) -> AnalogMode {
        switch source {
        case .dualSenseLeftStick: return leftStick
        case .dualSenseRightStick: return rightStick
        case .dualSenseTouchpad: return dualSenseTouchpad
        case .appleTVClickpad: return appleTVClickpad
        case .appleTVWheel: return appleTVWheel
        }
    }

    public mutating func setMode(_ mode: AnalogMode, for source: AnalogSource) {
        switch source {
        case .dualSenseLeftStick: leftStick = mode
        case .dualSenseRightStick: rightStick = mode
        case .dualSenseTouchpad: dualSenseTouchpad = mode
        case .appleTVClickpad: appleTVClickpad = mode
        case .appleTVWheel: appleTVWheel = mode
        }
    }

    public mutating func setBinding(_ action: ControlAction, for button: DeviceButton) {
        bindings[button] = action
    }

    public func duplicated(as name: String? = nil) -> MappingProfile {
        MappingProfile(
            id: UUID().uuidString,
            name: name ?? "\(self.name) copy",
            summary: summary,
            bindings: bindings,
            leftStick: leftStick,
            rightStick: rightStick,
            dualSenseTouchpad: dualSenseTouchpad,
            appleTVClickpad: appleTVClickpad,
            appleTVWheel: appleTVWheel,
            pointerAcceleration: pointerAcceleration,
            pointerAccelerationAmount: pointerAccelerationAmount,
            stickyTargeting: stickyTargeting
        )
    }

    public static func makeDefault(name: String = "Default", isAppleTVRemote: Bool) -> MappingProfile {
        if isAppleTVRemote {
            return MappingProfile(
                name: name,
                summary: "Clickpad moves the pointer. Clickwheel scrolls.",
                bindings: appleTVBindings,
                appleTVClickpad: .pointer,
                appleTVWheel: .scroll,
                pointerAcceleration: true,
                pointerAccelerationAmount: 0.3,
                stickyTargeting: false
            )
        }
        return MappingProfile(
            name: name,
            summary: "D-pad arrows, Cross for Return, Circle for Escape.",
            bindings: dualSenseBindings
        )
    }
}

private let appleTVBindings: [DeviceButton: ControlAction] = [
    .playPause: .mediaPlayPause,
    .mute: .mediaMute,
    .volumeUp: .mediaVolumeUp,
    .volumeDown: .mediaVolumeDown,
    .back: .escapeKey,
    .clickSelect: .mouseLeft,
    .clickSelectLong: .mouseRight,
    .clickUp: .arrowUp,
    .clickDown: .arrowDown,
    .clickLeft: .arrowLeft,
    .clickRight: .arrowRight
]

private let dualSenseBindings: [DeviceButton: ControlAction] = [
    .dpadUp: .arrowUp,
    .dpadDown: .arrowDown,
    .dpadLeft: .arrowLeft,
    .dpadRight: .arrowRight,
    .cross: .returnKey,
    .circle: .escapeKey,
    .square: .tabKey,
    .triangle: .spaceKey,
    .touchpadClick: .mouseLeft
]
