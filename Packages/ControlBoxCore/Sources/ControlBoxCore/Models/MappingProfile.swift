import CoreGraphics
import Foundation

/// What a plain Dock click does when that app is already in front with a visible window.
public enum DockClickFrontAction: String, Codable, Equatable, Sendable, CaseIterable {
    case none
    case minimize
    case hide
}

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
    public var pointerSpeed: Double?
    public var hapticGestureSpeed: Double?
    public var wheelScrollSpeed: Double?
    public var thumbScrollSpeed: Double?
    public var naturalScrolling: Bool?
    public var sensorDPI: Int?
    public var smoothScrolling: Bool?
    public var gestureSets: [DeviceButton: GestureSet]?
    public var customGestureSets: [DeviceButton: [NamedGestureSet]]?
    public var selectedCustomGestureSetIDs: [DeviceButton: String]?
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
    public var windowShakeEnabled: Bool?
    public var windowShakeScope: WindowShakeScope?
    public var windowDockClickMinimizeEnabled: Bool?
    public var windowDockClickEnabled: Bool?
    public var windowDockClickDoubleMinimizeEnabled: Bool?
    public var windowDockClickIgnoredBundleIDs: [String]?
    /// What a plain Dock click does when that app is already in front. Nil migrates the old minimize toggle.
    public var windowDockClickFrontAction: DockClickFrontAction?
    /// Exact-app row on an MX mouse. Nil on Default, category, and leftover profiles.
    public var frontmostAppBundleID: String? = nil
    /// Unused on current MX rows; kept so older saves that stored a category still decode.
    public var appCategory: MouseAppCategory? = nil
    /// Distinguished Default mapping on an MX mouse. Leftover named profiles stay false.
    public var isMXDefault: Bool? = nil
    /// One behavior for the physical thumb wheel. Nil migrates old direction bindings.
    public var mxThumbWheelMode: MXWheelMode? = nil
    /// Device-level HID++ thumb-wheel gain (Calibration). Nil is 50% = 1×.
    public var mxThumbWheelSensitivity: Double? = nil
    /// Device-level HID++ thumb invert (`0x2150` setThumbwheelReporting byte 1). Calibration; nil is off.
    public var mxThumbWheelInvert: Bool? = nil
    /// MagSpeed SmartShift requested mode. Device-level; nil is Ratchet.
    public var mxRatchetMode: MXRatchetMode? = nil
    /// SmartShift auto-disengage threshold (`8…50`). Device-level; nil is 16.
    public var mxSmartShiftSensitivity: Int? = nil

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
    public var resolvedWindowShakeEnabled: Bool { windowShakeEnabled ?? false }
    public var resolvedWindowShakeScope: WindowShakeScope { windowShakeScope ?? .thisDisplay }
    public var resolvedWindowDockClickMinimizeEnabled: Bool { windowDockClickMinimizeEnabled ?? false }
    public var resolvedWindowDockClickEnabled: Bool {
        windowDockClickEnabled ?? windowDockClickMinimizeEnabled ?? false
    }
    public var resolvedWindowDockClickDoubleMinimizeEnabled: Bool {
        windowDockClickDoubleMinimizeEnabled ?? false
    }
    public var resolvedWindowDockClickIgnoredBundleIDs: [String] {
        Array(Set(windowDockClickIgnoredBundleIDs ?? [])).sorted()
    }
    public var resolvedWindowDockClickFrontAction: DockClickFrontAction {
        windowDockClickFrontAction ?? (resolvedWindowDockClickDoubleMinimizeEnabled ? .minimize : .none)
    }
    public var resolvedMXThumbWheelMode: MXWheelMode {
        mxThumbWheelMode ?? inferredMXThumbWheelMode()
    }
    public var resolvedMXThumbWheelSensitivity: Double { Self.clampSpeed(mxThumbWheelSensitivity) }
    public var resolvedMXThumbWheelInvert: Bool { mxThumbWheelInvert ?? false }
    public var resolvedMXRatchetMode: MXRatchetMode { mxRatchetMode ?? .ratchet }
    public var resolvedMXSmartShiftSensitivity: Int {
        Self.clampSmartShiftSensitivity(mxSmartShiftSensitivity)
    }

    public static let defaultWindowMoveFlags = CGEventFlags.maskControl.rawValue
    public static let defaultWindowResizeFlags = CGEventFlags.maskControl.union(.maskShift).rawValue
    public static let defaultWindowThrowFlags = CGEventFlags.maskControl.union(.maskAlternate).rawValue
    public static let defaultWindowOrganizeFlags = CGEventFlags.maskControl.union(.maskCommand).rawValue
    public static let defaultWindowOrganizeKey: UInt16 = 31

    public static let fallbackDPILevels = [400, 800, 1000, 1200, 1600, 2000, 2400, 3200, 4000]
    public static let defaultSensorDPI = 1000
    /// OpenLogi slider floor: below this the ratchet free-spins on everyday scrolling.
    public static let smartShiftSensitivityMin = 8
    public static let smartShiftSensitivityMax = 50
    public static let smartShiftSensitivityDefault = 16

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
        pointerSpeed: Double? = 0.5,
        hapticGestureSpeed: Double? = 0.5,
        wheelScrollSpeed: Double? = 0.5,
        thumbScrollSpeed: Double? = 0.5,
        naturalScrolling: Bool? = true,
        sensorDPI: Int? = nil,
        smoothScrolling: Bool? = true,
        gestureSets: [DeviceButton: GestureSet]? = nil,
        customGestureSets: [DeviceButton: [NamedGestureSet]]? = nil,
        selectedCustomGestureSetIDs: [DeviceButton: String]? = nil,
        dualSenseTabRepeatInterval: Double? = nil,
        windowMoveEnabled: Bool? = nil,
        windowResizeEnabled: Bool? = nil,
        windowThrowEnabled: Bool? = nil,
        windowOrganizeEnabled: Bool? = nil,
        windowMoveFlags: UInt64? = nil,
        windowResizeFlags: UInt64? = nil,
        windowThrowFlags: UInt64? = nil,
        windowOrganizeFlags: UInt64? = nil,
        windowOrganizeKey: UInt16? = nil,
        windowShakeEnabled: Bool? = nil,
        windowShakeScope: WindowShakeScope? = nil,
        windowDockClickMinimizeEnabled: Bool? = nil,
        windowDockClickEnabled: Bool? = nil,
        windowDockClickDoubleMinimizeEnabled: Bool? = nil,
        windowDockClickIgnoredBundleIDs: [String]? = nil,
        windowDockClickFrontAction: DockClickFrontAction? = nil,
        frontmostAppBundleID: String? = nil,
        appCategory: MouseAppCategory? = nil,
        isMXDefault: Bool? = nil,
        mxThumbWheelMode: MXWheelMode? = nil,
        mxThumbWheelSensitivity: Double? = nil,
        mxThumbWheelInvert: Bool? = nil,
        mxRatchetMode: MXRatchetMode? = nil,
        mxSmartShiftSensitivity: Int? = nil
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
        self.pointerSpeed = pointerSpeed
        self.hapticGestureSpeed = hapticGestureSpeed
        self.wheelScrollSpeed = wheelScrollSpeed
        self.thumbScrollSpeed = thumbScrollSpeed
        self.naturalScrolling = naturalScrolling
        self.sensorDPI = sensorDPI
        self.smoothScrolling = smoothScrolling
        self.gestureSets = gestureSets
        self.customGestureSets = customGestureSets
        self.selectedCustomGestureSetIDs = selectedCustomGestureSetIDs
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
        self.windowShakeEnabled = windowShakeEnabled
        self.windowShakeScope = windowShakeScope
        self.windowDockClickMinimizeEnabled = windowDockClickMinimizeEnabled
        self.windowDockClickEnabled = windowDockClickEnabled
        self.windowDockClickDoubleMinimizeEnabled = windowDockClickDoubleMinimizeEnabled
        self.windowDockClickIgnoredBundleIDs = windowDockClickIgnoredBundleIDs
        self.windowDockClickFrontAction = windowDockClickFrontAction
        self.frontmostAppBundleID = frontmostAppBundleID
        self.appCategory = appCategory
        self.isMXDefault = isMXDefault
        self.mxThumbWheelMode = mxThumbWheelMode
        self.mxThumbWheelSensitivity = mxThumbWheelSensitivity
        self.mxThumbWheelInvert = mxThumbWheelInvert
        self.mxRatchetMode = mxRatchetMode
        self.mxSmartShiftSensitivity = mxSmartShiftSensitivity
    }

    private static func clampSpeed(_ value: Double?) -> Double {
        min(max(value ?? 0.5, 0), 1)
    }

    public static func clampDisplayedDPI(_ value: Int) -> Int {
        clampDPI(value)
    }

    public static func clampSmartShiftSensitivity(_ value: Int?) -> Int {
        min(
            max(value ?? smartShiftSensitivityDefault, smartShiftSensitivityMin),
            smartShiftSensitivityMax
        )
    }

    private static func clampDPI(_ value: Int?) -> Int {
        min(max(value ?? defaultSensorDPI, 200), 8000)
    }

    private func inferredMXThumbWheelMode() -> MXWheelMode {
        let backward = bindings[.mxThumbLeft]
        let forward = bindings[.mxThumbRight]
        if (backward == nil || backward == .scroll), (forward == nil || forward == .scroll) {
            return .horizontalScroll
        }
        switch (backward, forward) {
        case (.tabPrevious?, .tabNext?):
            return .switchTabs
        case (.mediaVolumeDown?, .mediaVolumeUp?), (.mediaVolumeUp?, .mediaVolumeDown?):
            return .volume
        case (.spaceLeft?, .spaceRight?):
            return .switchDesktops
        case (.switchApplicationBack?, .switchApplication?):
            return .switchApplications
        default:
            return .horizontalScroll
        }
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

    /// Hold-to-swipe vs a 1000 DPI mouse. Sensor DPI is divided out so the
    /// same physical swipe stays the same. There is no user speed slider.
    public static func gestureSpeedFactor(dpi: Int) -> Double {
        let dpiRatio = Double(defaultSensorDPI) / Double(max(dpi, 1))
        return min(max(dpiRatio, 0.002), 8)
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
        if button == .mxHaptic, action != .gestures {
            clearLegacyMXGestureBindings()
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

    /// Retained as a persistence migration entry point. Gesture ownership is
    /// now per raw-XY-capable control; only the legacy single MX gesture map
    /// still needs projecting onto the dedicated control.
    public mutating func restrictGesturesToHapticPad() {
        let hasLegacyHapticGesture = hasLegacyHapticGestureBindings
        if hasLegacyHapticGesture {
            if bindings[.mxHaptic] == nil || bindings[.mxHaptic] == .gestures {
                var sets = gestureSets ?? [:]
                if sets[.mxHaptic] == nil {
                    sets[.mxHaptic] = GestureSet(
                        preset: .custom,
                        click: bindings[.mxGesture] ?? .missionControl,
                        up: bindings[.mxGestureUp] ?? .missionControl,
                        down: bindings[.mxGestureDown] ?? .appExpose,
                        left: bindings[.mxGestureLeft] ?? .spaceLeft,
                        right: bindings[.mxGestureRight] ?? .spaceRight
                    )
                }
                gestureSets = sets
                bindings[.mxHaptic] = .gestures
            }
            clearLegacyMXGestureBindings()
        } else if bindings[.mxHaptic] == nil,
                  gestureSets?[.mxHaptic] != nil {
            bindings[.mxHaptic] = .gestures
        }
    }

    private mutating func clearLegacyMXGestureBindings() {
        bindings[.mxGesture] = nil
        bindings[.mxGestureUp] = nil
        bindings[.mxGestureDown] = nil
        bindings[.mxGestureLeft] = nil
        bindings[.mxGestureRight] = nil
    }

    public var mxGestureOwners: Set<DeviceButton> {
        var candidates: Set<DeviceButton> = [
            .mxMiddle, .mxBack, .mxForward, .mxSmartShift, .mxModeShift,
            .mxHaptic, .mxSide
        ]
        candidates.formUnion(DeviceButton.mxExtraButtons)
        var owners = Set(bindings.compactMap { button, action in
            candidates.contains(button) && action == .gestures ? button : nil
        })
        owners.formUnion((gestureSets ?? [:]).keys.filter(candidates.contains))
        return owners
    }

    public func gestureSet(for button: DeviceButton) -> GestureSet? {
        guard button.canOwnGestures else { return nil }
        if let set = gestureSets?[button] { return set }
        if bindings[button] == .gestures {
            return .named(Self.defaultGesturePreset(for: button))
        }
        if button == .mxHaptic, hasLegacyHapticGestureBindings {
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

    private var hasLegacyHapticGestureBindings: Bool {
        bindings[.mxGesture] != nil
            || bindings[.mxGestureUp] != nil
            || bindings[.mxGestureDown] != nil
            || bindings[.mxGestureLeft] != nil
            || bindings[.mxGestureRight] != nil
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

    public func namedCustomGestureSets(for button: DeviceButton) -> [NamedGestureSet] {
        if let saved = customGestureSets?[button], !saved.isEmpty {
            return saved
        }
        guard let active = gestureSet(for: button), active.preset == .custom else {
            return []
        }
        return [
            NamedGestureSet(
                id: Self.legacyCustomGestureSetID(for: button),
                name: "Custom 1",
                set: active
            )
        ]
    }

    public func selectedNamedCustomGestureSetID(for button: DeviceButton) -> String? {
        let sets = namedCustomGestureSets(for: button)
        if let selected = selectedCustomGestureSetIDs?[button],
           sets.contains(where: { $0.id == selected }) {
            return selected
        }
        return sets.first?.id
    }

    public mutating func selectGesturePreset(_ preset: GesturePreset, for button: DeviceButton) {
        guard button.canOwnGestures else { return }
        persistActiveCustomGestureSet(for: button)
        guard preset == .custom else {
            setGestureSet(.named(preset), for: button)
            return
        }

        var sets = materializedCustomGestureSets(for: button)
        if sets.isEmpty {
            _ = addNamedCustomGestureSet(for: button)
            return
        }
        let selectedID = selectedCustomGestureSetIDs?[button] ?? sets[0].id
        let selected = sets.first(where: { $0.id == selectedID }) ?? sets[0]
        var active = selected.set
        active.preset = .custom
        var selectedIDs = selectedCustomGestureSetIDs ?? [:]
        selectedIDs[button] = selected.id
        selectedCustomGestureSetIDs = selectedIDs
        setGestureSet(active, for: button)
    }

    @discardableResult
    public mutating func addNamedCustomGestureSet(for button: DeviceButton) -> NamedGestureSet {
        var sets = materializedCustomGestureSets(for: button)
        let usedNames = Set(sets.map(\.name))
        var number = sets.count + 1
        while usedNames.contains("Custom \(number)") {
            number += 1
        }
        let named = NamedGestureSet(name: "Custom \(number)")
        sets.append(named)
        var libraries = customGestureSets ?? [:]
        libraries[button] = sets
        customGestureSets = libraries
        var selectedIDs = selectedCustomGestureSetIDs ?? [:]
        selectedIDs[button] = named.id
        selectedCustomGestureSetIDs = selectedIDs
        setGestureSet(named.set, for: button)
        return named
    }

    public mutating func selectNamedCustomGestureSet(_ id: String, for button: DeviceButton) {
        persistActiveCustomGestureSet(for: button)
        let sets = materializedCustomGestureSets(for: button)
        guard let selected = sets.first(where: { $0.id == id }) else { return }
        var active = selected.set
        active.preset = .custom
        var selectedIDs = selectedCustomGestureSetIDs ?? [:]
        selectedIDs[button] = id
        selectedCustomGestureSetIDs = selectedIDs
        setGestureSet(active, for: button)
    }

    public mutating func deleteNamedCustomGestureSet(_ id: String, for button: DeviceButton) {
        persistActiveCustomGestureSet(for: button)
        var sets = materializedCustomGestureSets(for: button)
        guard let removedIndex = sets.firstIndex(where: { $0.id == id }) else { return }
        let selectedID = selectedNamedCustomGestureSetID(for: button)
        sets.remove(at: removedIndex)

        var libraries = customGestureSets ?? [:]
        var selectedIDs = selectedCustomGestureSetIDs ?? [:]
        if sets.isEmpty {
            libraries[button] = nil
            selectedIDs[button] = nil
            customGestureSets = libraries.isEmpty ? nil : libraries
            selectedCustomGestureSetIDs = selectedIDs.isEmpty ? nil : selectedIDs
            setGestureSet(.named(.windowNavigation), for: button)
            return
        }

        libraries[button] = sets
        customGestureSets = libraries
        let nextID: String
        if selectedID == id {
            nextID = sets[min(removedIndex, sets.count - 1)].id
        } else if let selectedID, sets.contains(where: { $0.id == selectedID }) {
            nextID = selectedID
        } else {
            nextID = sets[0].id
        }
        selectedIDs[button] = nextID
        selectedCustomGestureSetIDs = selectedIDs
        if selectedID == id, let next = sets.first(where: { $0.id == nextID }) {
            var active = next.set
            active.preset = .custom
            setGestureSet(active, for: button)
        }
    }

    private mutating func materializedCustomGestureSets(
        for button: DeviceButton
    ) -> [NamedGestureSet] {
        if let saved = customGestureSets?[button], !saved.isEmpty {
            return saved
        }
        let migrated = namedCustomGestureSets(for: button)
        if !migrated.isEmpty {
            var libraries = customGestureSets ?? [:]
            libraries[button] = migrated
            customGestureSets = libraries
            var selectedIDs = selectedCustomGestureSetIDs ?? [:]
            selectedIDs[button] = migrated[0].id
            selectedCustomGestureSetIDs = selectedIDs
        }
        return migrated
    }

    private mutating func persistActiveCustomGestureSet(for button: DeviceButton) {
        guard var active = gestureSet(for: button), active.preset == .custom else { return }
        active.preset = .custom
        var sets = materializedCustomGestureSets(for: button)
        guard !sets.isEmpty else { return }
        let selectedID = selectedCustomGestureSetIDs?[button] ?? sets[0].id
        guard let index = sets.firstIndex(where: { $0.id == selectedID }) else { return }
        sets[index].set = active
        var libraries = customGestureSets ?? [:]
        libraries[button] = sets
        customGestureSets = libraries
    }

    private static func legacyCustomGestureSetID(for button: DeviceButton) -> String {
        "legacy-custom-\(button.rawValue)"
    }

    private static func defaultGesturePreset(for button: DeviceButton) -> GesturePreset {
        button == .touchpadTwoFinger ? .mediaControls : .windowNavigation
    }

    /// Saved DualSense profiles that never bound the finger rows get the
    /// new 1-finger / 2-finger Gestures defaults. Pointer/scroll touchpad
    /// profiles are left alone.
    /// Logitech Gesture button (CID `0x00C3`) on 3 / 3S / 4. Persisted as `mxSide`.
    /// Older MX4 profiles may already have a click action; only fill a missing row.
    public mutating func ensureThumbGestureButton() {
        if bindings[.mxSide] != nil { return }
        bindings[.mxSide] = .gestures
        var sets = gestureSets ?? [:]
        if sets[.mxSide] == nil {
            sets[.mxSide] = sets[.mxHaptic] ?? .named(.windowNavigation)
        }
        gestureSets = sets
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
        set.preset = .custom
        setGestureSet(set, for: button)
        persistActiveCustomGestureSet(for: button)
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
            pointerSpeed: pointerSpeed,
            hapticGestureSpeed: hapticGestureSpeed,
            wheelScrollSpeed: wheelScrollSpeed,
            thumbScrollSpeed: thumbScrollSpeed,
            naturalScrolling: naturalScrolling,
            sensorDPI: sensorDPI,
            smoothScrolling: smoothScrolling,
            gestureSets: gestureSets,
            customGestureSets: customGestureSets,
            selectedCustomGestureSetIDs: selectedCustomGestureSetIDs,
            dualSenseTabRepeatInterval: dualSenseTabRepeatInterval,
            windowMoveEnabled: windowMoveEnabled,
            windowResizeEnabled: windowResizeEnabled,
            windowThrowEnabled: windowThrowEnabled,
            windowOrganizeEnabled: windowOrganizeEnabled,
            windowMoveFlags: windowMoveFlags,
            windowResizeFlags: windowResizeFlags,
            windowThrowFlags: windowThrowFlags,
            windowOrganizeFlags: windowOrganizeFlags,
            windowOrganizeKey: windowOrganizeKey,
            windowShakeEnabled: windowShakeEnabled,
            windowShakeScope: windowShakeScope,
            windowDockClickMinimizeEnabled: windowDockClickMinimizeEnabled,
            windowDockClickEnabled: windowDockClickEnabled,
            windowDockClickDoubleMinimizeEnabled: windowDockClickDoubleMinimizeEnabled,
            windowDockClickIgnoredBundleIDs: windowDockClickIgnoredBundleIDs,
            windowDockClickFrontAction: windowDockClickFrontAction,
            frontmostAppBundleID: frontmostAppBundleID,
            appCategory: appCategory,
            isMXDefault: isMXDefault,
            mxThumbWheelMode: mxThumbWheelMode,
            mxThumbWheelSensitivity: mxThumbWheelSensitivity,
            mxThumbWheelInvert: mxThumbWheelInvert,
            mxRatchetMode: mxRatchetMode,
            mxSmartShiftSensitivity: mxSmartShiftSensitivity
        )
    }

    public static func makeDefault(
        name: String = "Default",
        isAppleTVRemote: Bool,
        isMXMaster: Bool = false,
        isMXKeyboard: Bool = false,
        gamepadHasTouchpad: Bool = true
    ) -> MappingProfile {
        if isMXKeyboard {
            return MappingProfile(
                name: name,
                summary: "Backlight, lighting effects, and battery.",
                bindings: [:]
            )
        }
        if isMXMaster {
            return MappingProfile(
                name: name,
                summary: "Gesture button is Gestures. MX4 Haptic button is the pad. Back and Forward are browser buttons.",
                bindings: mxMasterBindings,
                pointerSpeed: 0.21,
                hapticGestureSpeed: 0.5,
                wheelScrollSpeed: 0.5,
                thumbScrollSpeed: 0.5,
                naturalScrolling: false,
                sensorDPI: defaultSensorDPI,
                smoothScrolling: true,
                gestureSets: [
                    .mxHaptic: .named(.windowNavigation),
                    .mxSide: .named(.windowNavigation)
                ],
                windowMoveEnabled: true,
                windowResizeEnabled: true,
                windowMoveFlags: defaultWindowMoveFlags,
                windowResizeFlags: defaultWindowResizeFlags,
                isMXDefault: true,
                mxThumbWheelMode: .horizontalScroll
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
                pointerAccelerationAmount: 0.58
            )
        }
        if gamepadHasTouchpad {
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
        return MappingProfile(
            name: name,
            summary: "L1/R1 desktops, L2/R2 tabs. D-pad Mission Control, Desktop, and app switch. Left stick pointer, right stick scroll.",
            bindings: genericGamepadBindings,
            leftStick: .pointer,
            rightStick: .scroll,
            dualSenseTouchpad: .off,
            pointerAcceleration: true,
            pointerAccelerationAmount: 0.47,
            pointerSpeed: 0.32,
            hapticGestureSpeed: 0.29,
            wheelScrollSpeed: 0.97,
            naturalScrolling: true
        )
    }
}

private let mxMasterBindings: [DeviceButton: ControlAction] = [
    .mxHaptic: .gestures,
    .mxSide: .gestures,
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

private let genericGamepadBindings: [DeviceButton: ControlAction] = [
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
    .r3: .mouseRight
]

private let dualSenseBindings: [DeviceButton: ControlAction] = {
    var bindings = genericGamepadBindings
    bindings[.touchpadClick] = .mouseLeft
    bindings[.touchpadOneFinger] = .gestures
    return bindings
}()
