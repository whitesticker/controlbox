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
    public var pointerSpeed: Double?
    public var hapticGestureSpeed: Double?
    public var wheelScrollSpeed: Double?
    public var thumbScrollSpeed: Double?
    public var naturalScrolling: Bool?
    public var sensorDPI: Int?
    public var smoothScrolling: Bool?
    public var gestureSets: [DeviceButton: GestureSet]?

    public var resolvedPointerSpeed: Double { Self.clampSpeed(pointerSpeed) }
    public var resolvedHapticGestureSpeed: Double { Self.clampSpeed(hapticGestureSpeed) }
    public var resolvedWheelScrollSpeed: Double { Self.clampSpeed(wheelScrollSpeed) }
    public var resolvedThumbScrollSpeed: Double { Self.clampSpeed(thumbScrollSpeed) }
    public var appliedPointerSpeed: Double { resolvedPointerSpeed * 0.5 }
    public var appliedWheelScrollSpeed: Double { resolvedWheelScrollSpeed * 0.5 }
    public var appliedThumbScrollSpeed: Double { resolvedThumbScrollSpeed * 0.5 }
    public var resolvedNaturalScrolling: Bool { naturalScrolling ?? true }
    public var resolvedSensorDPI: Int { Self.clampDPI(sensorDPI) }
    public var resolvedSmoothScrolling: Bool { smoothScrolling ?? true }

    public static let fallbackDPILevels = [400, 800, 1000, 1200, 1600, 2000, 2400, 3200, 4000]
    public static let defaultSensorDPI = 1000

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
        stickyTargeting: Bool? = false,
        pointerSpeed: Double? = 0.5,
        hapticGestureSpeed: Double? = 0.5,
        wheelScrollSpeed: Double? = 0.5,
        thumbScrollSpeed: Double? = 0.5,
        naturalScrolling: Bool? = true,
        sensorDPI: Int? = nil,
        smoothScrolling: Bool? = true,
        gestureSets: [DeviceButton: GestureSet]? = nil
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
        self.pointerSpeed = pointerSpeed
        self.hapticGestureSpeed = hapticGestureSpeed
        self.wheelScrollSpeed = wheelScrollSpeed
        self.thumbScrollSpeed = thumbScrollSpeed
        self.naturalScrolling = naturalScrolling
        self.sensorDPI = sensorDPI
        self.smoothScrolling = smoothScrolling
        self.gestureSets = gestureSets
    }

    private static func clampSpeed(_ value: Double?) -> Double {
        min(max(value ?? 0.5, 0), 1)
    }

    public static func clampDisplayedDPI(_ value: Int) -> Int {
        clampDPI(value)
    }

    private static func clampDPI(_ value: Int?) -> Int {
        min(max(value ?? defaultSensorDPI, 200), 8000)
    }

    public static func nearestDPI(_ value: Int, in levels: [Int]) -> Int {
        let list = levels.isEmpty ? fallbackDPILevels : levels
        return list.min(by: { abs($0 - value) < abs($1 - value) }) ?? defaultSensorDPI
    }

    /// On-screen speed vs a 1000 DPI mouse at 50%. Low slider values drop
    /// steeply so 8% is actually slow. Higher sensor DPI is divided out.
    public static func pointerSpeedFactor(slider: Double, dpi: Int) -> Double {
        let s = clampSpeed(slider)
        let fromSlider: Double
        if s <= 0.5 {
            fromSlider = pow(s / 0.5, 2.6)
        } else {
            fromSlider = pow(4.0, (s - 0.5) * 2)
        }
        let dpiRatio = Double(defaultSensorDPI) / Double(max(dpi, 1))
        return min(max(fromSlider * dpiRatio, 0.002), 8)
    }

    /// Haptic swipe bar. 50% is 1× of native HID travel at 1000 DPI.
    /// Sensor DPI is divided out so the same physical swipe stays the same.
    public static func gestureSpeedFactor(slider: Double, dpi: Int) -> Double {
        let fromSlider = pow(2.0, (clampSpeed(slider) - 0.5) * 2)
        let dpiRatio = Double(defaultSensorDPI) / Double(max(dpi, 1))
        return min(max(fromSlider * dpiRatio, 0.002), 8)
    }

    /// HID++ 0x2205 8.8 scale. 50% at 1000 DPI is 1×.
    public static func pointerScale8_8(slider: Double, dpi: Int) -> Int {
        Int(min(max(pointerSpeedFactor(slider: slider, dpi: dpi) * 256, 1), 4096).rounded())
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
        if action != .gestures {
            gestureSets?[button] = nil
            if gestureSets?.isEmpty == true {
                gestureSets = nil
            }
        } else if gestureSets?[button] == nil {
            setGestureSet(.named(.windowNavigation), for: button)
        }
    }

    public var mxGestureOwners: Set<DeviceButton> {
        var owners = Set((gestureSets ?? [:]).keys)
        for (button, action) in bindings where action == .gestures {
            owners.insert(button)
        }
        if owners.isEmpty, bindings[.mxGesture] != nil || bindings[.mxGestureUp] != nil {
            owners.insert(.mxHaptic)
        }
        return owners
    }

    public func gestureSet(for button: DeviceButton) -> GestureSet? {
        if let set = gestureSets?[button] { return set }
        if button == .mxHaptic, (gestureSets ?? [:]).isEmpty {
            return GestureSet(
                preset: .custom,
                click: bindings[.mxGesture] ?? .missionControl,
                up: bindings[.mxGestureUp] ?? .missionControl,
                down: bindings[.mxGestureDown] ?? .appExpose,
                left: bindings[.mxGestureLeft] ?? .spaceLeft,
                right: bindings[.mxGestureRight] ?? .spaceRight
            )
        }
        return nil
    }

    public func action(forGesture slot: GestureSlot, owner: DeviceButton) -> ControlAction {
        if let set = gestureSet(for: owner) {
            return set.action(for: slot)
        }
        return bindings[slot.deviceButton] ?? .none
    }

    public mutating func setGestureSet(_ set: GestureSet, for button: DeviceButton) {
        bindings[button] = .gestures
        var sets = gestureSets ?? [:]
        sets[button] = set
        gestureSets = sets
    }

    public mutating func setGestureAction(_ action: ControlAction, slot: GestureSlot, for button: DeviceButton) {
        var set = gestureSet(for: button) ?? GestureSet.named(.custom)
        set.setAction(action, for: slot)
        setGestureSet(set, for: button)
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
            stickyTargeting: stickyTargeting,
            pointerSpeed: pointerSpeed,
            hapticGestureSpeed: hapticGestureSpeed,
            wheelScrollSpeed: wheelScrollSpeed,
            thumbScrollSpeed: thumbScrollSpeed,
            naturalScrolling: naturalScrolling,
            sensorDPI: sensorDPI,
            smoothScrolling: smoothScrolling,
            gestureSets: gestureSets
        )
    }

    public static func makeDefault(
        name: String = "Default",
        isAppleTVRemote: Bool,
        isMXMaster: Bool = false
    ) -> MappingProfile {
        if isMXMaster {
            return MappingProfile(
                name: name,
                summary: "Assign Gestures to any button, then hold and move. A tap without moving is Click.",
                bindings: mxMasterBindings,
                sensorDPI: defaultSensorDPI,
                smoothScrolling: true,
                gestureSets: [.mxHaptic: .named(.windowNavigation)]
            )
        }
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

private let mxMasterBindings: [DeviceButton: ControlAction] = [
    .mxHaptic: .gestures,
    .mxBack: .browserBack,
    .mxForward: .browserForward
]

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
