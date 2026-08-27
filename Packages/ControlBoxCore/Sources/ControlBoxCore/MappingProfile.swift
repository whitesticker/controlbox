import CoreGraphics
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
    public var scrollAcceleration: Bool?
    public var scrollAccelerationAmount: Double?
    public var stickyTargeting: Bool?
    public var pointerSpeed: Double?
    public var hapticGestureSpeed: Double?
    public var wheelScrollSpeed: Double?
    public var thumbScrollSpeed: Double?
    public var naturalScrolling: Bool?
    public var sensorDPI: Int?
    public var smoothScrolling: Bool?
    public var gestureSets: [DeviceButton: GestureSet]?
    public var dualSenseTabRepeatInterval: Double?
    public var windowMoveEnabled: Bool?
    public var windowResizeEnabled: Bool?
    public var windowThrowEnabled: Bool?
    public var windowOrganizeEnabled: Bool?
    public var windowMoveFlags: UInt64?
    public var windowResizeFlags: UInt64?
    public var windowThrowFlags: UInt64?
    public var windowOrganizeFlags: UInt64?
    public var windowOrganizeKey: UInt16?

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
    public var resolvedTabRepeatInterval: Double { min(max(dualSenseTabRepeatInterval ?? 0.22, 0.10), 0.55) }
    public var resolvedWindowMoveEnabled: Bool { windowMoveEnabled ?? true }
    public var resolvedWindowResizeEnabled: Bool { windowResizeEnabled ?? true }
    public var resolvedWindowThrowEnabled: Bool { windowThrowEnabled ?? false }
    public var resolvedWindowOrganizeEnabled: Bool { windowOrganizeEnabled ?? false }
    public var resolvedWindowMoveFlags: CGEventFlags {
        CGEventFlags(rawValue: windowMoveFlags ?? Self.defaultWindowMoveFlags)
    }
    public var resolvedWindowResizeFlags: CGEventFlags {
        CGEventFlags(rawValue: windowResizeFlags ?? Self.defaultWindowResizeFlags)
    }
    public var resolvedWindowThrowFlags: CGEventFlags {
        CGEventFlags(rawValue: windowThrowFlags ?? Self.defaultWindowThrowFlags)
    }
    public var resolvedWindowOrganizeFlags: CGEventFlags {
        CGEventFlags(rawValue: windowOrganizeFlags ?? Self.defaultWindowOrganizeFlags)
    }
    public var resolvedWindowOrganizeKey: UInt16 {
        windowOrganizeKey ?? Self.defaultWindowOrganizeKey
    }

    public static let defaultWindowMoveFlags = CGEventFlags.maskControl.rawValue
    public static let defaultWindowResizeFlags = CGEventFlags.maskControl.union(.maskShift).rawValue
    public static let defaultWindowThrowFlags = CGEventFlags.maskControl.union(.maskAlternate).rawValue
    public static let defaultWindowOrganizeFlags = CGEventFlags.maskControl.union(.maskCommand).rawValue
    public static let defaultWindowOrganizeKey: UInt16 = 31

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
        scrollAcceleration: Bool? = false,
        scrollAccelerationAmount: Double? = 0.3,
        stickyTargeting: Bool? = false,
        pointerSpeed: Double? = 0.5,
        hapticGestureSpeed: Double? = 0.5,
        wheelScrollSpeed: Double? = 0.5,
        thumbScrollSpeed: Double? = 0.5,
        naturalScrolling: Bool? = true,
        sensorDPI: Int? = nil,
        smoothScrolling: Bool? = true,
        gestureSets: [DeviceButton: GestureSet]? = nil,
        dualSenseTabRepeatInterval: Double? = nil,
        windowMoveEnabled: Bool? = nil,
        windowResizeEnabled: Bool? = nil,
        windowThrowEnabled: Bool? = nil,
        windowOrganizeEnabled: Bool? = nil,
        windowMoveFlags: UInt64? = nil,
        windowResizeFlags: UInt64? = nil,
        windowThrowFlags: UInt64? = nil,
        windowOrganizeFlags: UInt64? = nil,
        windowOrganizeKey: UInt16? = nil
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
        self.scrollAcceleration = scrollAcceleration
        self.scrollAccelerationAmount = scrollAccelerationAmount
        self.stickyTargeting = stickyTargeting
        self.pointerSpeed = pointerSpeed
        self.hapticGestureSpeed = hapticGestureSpeed
        self.wheelScrollSpeed = wheelScrollSpeed
        self.thumbScrollSpeed = thumbScrollSpeed
        self.naturalScrolling = naturalScrolling
        self.sensorDPI = sensorDPI
        self.smoothScrolling = smoothScrolling
        self.gestureSets = gestureSets
        self.dualSenseTabRepeatInterval = dualSenseTabRepeatInterval
        self.windowMoveEnabled = windowMoveEnabled
        self.windowResizeEnabled = windowResizeEnabled
        self.windowThrowEnabled = windowThrowEnabled
        self.windowOrganizeEnabled = windowOrganizeEnabled
        self.windowMoveFlags = windowMoveFlags
        self.windowResizeFlags = windowResizeFlags
        self.windowThrowFlags = windowThrowFlags
        self.windowOrganizeFlags = windowOrganizeFlags
        self.windowOrganizeKey = windowOrganizeKey
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
        case .dualSenseTouchpadSecondary: return .off
        case .appleTVClickpad: return appleTVClickpad
        case .appleTVWheel: return appleTVWheel
        }
    }

    public mutating func setMode(_ mode: AnalogMode, for source: AnalogSource) {
        switch source {
        case .dualSenseLeftStick: leftStick = mode
        case .dualSenseRightStick: rightStick = mode
        case .dualSenseTouchpad: dualSenseTouchpad = mode
        case .dualSenseTouchpadSecondary: break
        case .appleTVClickpad: appleTVClickpad = mode
        case .appleTVWheel: appleTVWheel = mode
        }
    }

    public mutating func setBinding(_ action: ControlAction, for button: DeviceButton) {
        if action == .gestures, !button.canOwnGestures {
            bindings[button] = Self.fallbackMXClickAction(for: button)
            return
        }
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

    /// Hold-to-swipe is the haptic pad only. Click-as-gesture on Back / etc. is parked.
    public mutating func restrictGesturesToHapticPad() {
        for button in bindings.keys where button != .mxHaptic && bindings[button] == .gestures {
            bindings[button] = Self.fallbackMXClickAction(for: button)
        }
        if let sets = gestureSets {
            let kept = sets.filter { $0.key == .mxHaptic }
            gestureSets = kept.isEmpty ? nil : kept
        }
    }

    public var mxGestureOwners: Set<DeviceButton> {
        if bindings[.mxHaptic] == .gestures || gestureSets?[.mxHaptic] != nil {
            return [.mxHaptic]
        }
        if bindings[.mxGesture] != nil || bindings[.mxGestureUp] != nil {
            return [.mxHaptic]
        }
        return []
    }

    public func gestureSet(for button: DeviceButton) -> GestureSet? {
        guard button.canOwnGestures else { return nil }
        if let set = gestureSets?[button] { return set }
        if bindings[button] == .gestures {
            return .named(Self.defaultGesturePreset(for: button))
        }
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
        guard button.canOwnGestures else { return }
        bindings[button] = .gestures
        var sets = gestureSets ?? [:]
        sets[button] = set
        gestureSets = sets
    }

    private static func defaultGesturePreset(for button: DeviceButton) -> GesturePreset {
        button == .touchpadTwoFinger ? .mediaControls : .windowNavigation
    }

    /// Saved DualSense profiles that never bound the finger rows get the
    /// new 1-finger / 2-finger Gestures defaults. Pointer/scroll touchpad
    /// profiles are left alone.
    /// MX4 extra thumb button (CID `0x00C3`) is missing on older saved profiles.
    public mutating func ensureMX4SideButton() {
        if bindings[.mxSide] != nil { return }
        bindings[.mxSide] = .missionControl
    }

    public mutating func ensureDualSenseTouchGestures() {
        if bindings[.touchpadOneFinger] != nil || bindings[.touchpadTwoFinger] != nil {
            return
        }
        guard dualSenseTouchpad == .off else { return }
        bindings[.touchpadOneFinger] = .gestures
        bindings[.touchpadTwoFinger] = .gestures
        var sets = gestureSets ?? [:]
        sets[.touchpadOneFinger] = .named(.windowNavigation)
        sets[.touchpadTwoFinger] = .named(.mediaControls)
        gestureSets = sets
    }

    private static func fallbackMXClickAction(for button: DeviceButton) -> ControlAction {
        switch button {
        case .mxBack: return .browserBack
        case .mxForward: return .browserForward
        default: return .none
        }
    }

    /// Missing or `.scroll` keeps the native / speed-tap path. Anything else
    /// replaces that direction’s scrolling with the mapped action.
    public func keepsNativeScroll(for button: DeviceButton) -> Bool {
        guard button.isMXScrollDirection else { return false }
        let action = bindings[button]
        return action == nil || action == .scroll
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
            scrollAcceleration: scrollAcceleration,
            scrollAccelerationAmount: scrollAccelerationAmount,
            stickyTargeting: stickyTargeting,
            pointerSpeed: pointerSpeed,
            hapticGestureSpeed: hapticGestureSpeed,
            wheelScrollSpeed: wheelScrollSpeed,
            thumbScrollSpeed: thumbScrollSpeed,
            naturalScrolling: naturalScrolling,
            sensorDPI: sensorDPI,
            smoothScrolling: smoothScrolling,
            gestureSets: gestureSets,
            dualSenseTabRepeatInterval: dualSenseTabRepeatInterval,
            windowMoveEnabled: windowMoveEnabled,
            windowResizeEnabled: windowResizeEnabled,
            windowThrowEnabled: windowThrowEnabled,
            windowOrganizeEnabled: windowOrganizeEnabled,
            windowMoveFlags: windowMoveFlags,
            windowResizeFlags: windowResizeFlags,
            windowThrowFlags: windowThrowFlags,
            windowOrganizeFlags: windowOrganizeFlags,
            windowOrganizeKey: windowOrganizeKey
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
                summary: "Haptic pad is Gestures. Side is Switch Desktop. Back and Forward are browser buttons.",
                bindings: mxMasterBindings,
                pointerSpeed: 0.21,
                hapticGestureSpeed: 0.5,
                wheelScrollSpeed: 0.5,
                thumbScrollSpeed: 0.5,
                naturalScrolling: false,
                sensorDPI: defaultSensorDPI,
                smoothScrolling: true,
                gestureSets: [.mxHaptic: .named(.windowNavigation)],
                windowMoveEnabled: true,
                windowResizeEnabled: true,
                windowMoveFlags: defaultWindowMoveFlags,
                windowResizeFlags: defaultWindowResizeFlags
            )
        }
        if isAppleTVRemote {
            return MappingProfile(
                name: name,
                summary: "Clickpad moves the pointer. Clickwheel scrolls. Back is Return.",
                bindings: appleTVBindings,
                appleTVClickpad: .pointer,
                appleTVWheel: .scroll,
                pointerAcceleration: true,
                pointerAccelerationAmount: 0.58,
                stickyTargeting: false
            )
        }
        return MappingProfile(
            name: name,
            summary: "L1/R1 desktops, L2/R2 tabs. D-pad Mission Control, Desktop, and app switch. Left stick pointer, right stick scroll. 1-finger is media.",
            bindings: dualSenseBindings,
            leftStick: .pointer,
            rightStick: .scroll,
            dualSenseTouchpad: .pointer,
            pointerAcceleration: true,
            pointerAccelerationAmount: 0.47,
            pointerSpeed: 0.32,
            hapticGestureSpeed: 0.29,
            wheelScrollSpeed: 0.97,
            naturalScrolling: true,
            gestureSets: [
                .touchpadOneFinger: .named(.mediaControls)
            ]
        )
    }
}

private let mxMasterBindings: [DeviceButton: ControlAction] = [
    .mxHaptic: .gestures,
    .mxSide: .missionControl,
    .mxBack: .browserBack,
    .mxForward: .browserForward,
    .mxSmartShift: .rightOptionKey
]

private let appleTVBindings: [DeviceButton: ControlAction] = [
    .playPause: .mediaPlayPause,
    .mute: .mediaMute,
    .volumeUp: .mediaVolumeUp,
    .volumeDown: .mediaVolumeDown,
    .back: .returnKey,
    .tv: .rightOptionKey,
    .siri: .none,
    .power: .none,
    .clickSelect: .mouseLeft,
    .clickSelectLong: .mouseRight,
    .clickUp: .arrowUp,
    .clickDown: .arrowDown,
    .clickLeft: .arrowLeft,
    .clickRight: .arrowRight
]

private let dualSenseBindings: [DeviceButton: ControlAction] = [
    .dpadUp: .missionControl,
    .dpadDown: .showDesktop,
    .dpadLeft: .switchApplicationBack,
    .dpadRight: .switchApplication,
    .cross: .rightOptionKey,
    .circle: .returnKey,
    .square: .mouseLeft,
    .triangle: .escapeKey,
    .l1: .spaceLeft,
    .r1: .spaceRight,
    .l2: .tabPrevious,
    .r2: .tabNext,
    .l3: .mouseLeft,
    .r3: .mouseRight,
    .touchpadClick: .mouseLeft,
    .touchpadOneFinger: .gestures
]
