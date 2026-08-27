import CoreGraphics
import Foundation

public final class ControlEngine: @unchecked Sendable {
    public var profile: MappingProfile
    public var enabled = false
    public var postsWhenHostIsActive = false
    public var isDualSense = false
    public var pointerSpeed: Double = 14
    public var scrollSpeed: Double = 0.35

    private var previousButtons: [DeviceButton: Bool] = [:]
    private var lastAnalog: [AnalogSource: AnalogSample] = [:]
    private var wheelRemainder: Double = 0
    private var wheelVelocity: Double = 0
    private var lastWheelSign: Double = 0
    private var scrollPixelRemainderY: Double = 0
    private var selectDownAt: Date?
    private var selectDidLongPress = false
    private let selectHoldDuration: TimeInterval = 0.7
    private var pointerRemainderX: Double = 0
    private var pointerRemainderY: Double = 0
    private var pointerSmoothX: Double = 0
    private var pointerSmoothY: Double = 0
    private var pointerSmoothGain: Double = 1
    private var stickSmoothX: Double = 0
    private var stickSmoothY: Double = 0
    private var stickSmoothGain: Double = 1
    private var pointerFrozenUntil = Date.distantPast
    private var wheelGestureLatched = false
    private var volumeRepeatAt = Date.distantPast
    private var volumeRepeatButton: DeviceButton?
    private var padGesture = HoldGesture()
    private var touchGesture = DualSenseTouchGesture()
    private var leftTriggerTravel = DualSenseTriggerTravel()
    private var rightTriggerTravel = DualSenseTriggerTravel()

    public init(profile: MappingProfile = MappingProfile.makeDefault(isAppleTVRemote: false)) {
        self.profile = profile
    }

    public var isAccessibilityTrusted: Bool {
        EventPoster.isTrusted()
    }

    public func promptForAccessibility() {
        EventPoster.promptForTrust()
    }

    public func reset() {
        previousButtons = [:]
        lastAnalog = [:]
        wheelRemainder = 0
        wheelVelocity = 0
        lastWheelSign = 0
        scrollPixelRemainderY = 0
        pointerRemainderX = 0
        pointerRemainderY = 0
        pointerSmoothX = 0
        pointerSmoothY = 0
        pointerSmoothGain = 1
        stickSmoothX = 0
        stickSmoothY = 0
        stickSmoothGain = 1
        pointerFrozenUntil = .distantPast
        wheelGestureLatched = false
        volumeRepeatAt = .distantPast
        volumeRepeatButton = nil
        padGesture.cancel()
        touchGesture.reset()
        leftTriggerTravel.reset()
        rightTriggerTravel.reset()
        AppSwitcher.cancel()
        clearSelectHold()
        StickyTargeting.hide()
    }

    public func process(_ frame: ControlFrame, hostIsActive: Bool) {
        var stickyActive = false
        defer { StickyTargeting.sync(active: stickyActive) }

        guard EventPoster.isTrusted() else {
            clearSelectHold()
            return
        }

        pointerSpeed = 4 + profile.appliedPointerSpeed * 24
        scrollSpeed = isDualSense ? analogScrollGain : (0.08 + profile.appliedWheelScrollSpeed * 0.72)

        guard enabled else {
            previousButtons = frame.buttons
            lastAnalog = frame.analog
            AppSwitcher.cancel()
            clearSelectHold()
            padGesture.cancel()
            return
        }

        let injectAll = !hostIsActive || postsWhenHostIsActive
        if !injectAll {
            padGesture.cancel()
            previousButtons = frame.buttons
            lastAnalog = frame.analog
            AppSwitcher.cancel()
            clearSelectHold()
            applyVolumeRepeat(upPressed: false, downPressed: false, enabled: false)
            return
        }

        postInjectedScroll(frame)
        processGesture(frame, injectAll: true)
        if isDualSense {
            processTriggerTabs(frame, injectAll: true)
        }

        stickyActive = profile.stickyTargeting == true
            && AnalogSource.allCases.contains { profile.mode(for: $0) == .pointer }

        for (button, pressed) in frame.buttons
            where button != .clickSelect
            && button != .clickSelectLong
            && button != .volumeUp
            && button != .volumeDown
            && !usesTriggerTabs(button) {
            let wasPressed = previousButtons[button] ?? false
            if pressed != wasPressed {
                let action = resolvedAction(for: button)
                if action != .scroll {
                    perform(action, down: pressed)
                }
            }
        }
        applyVolumeRepeat(
            upPressed: frame.buttons[.volumeUp] ?? false,
            downPressed: frame.buttons[.volumeDown] ?? false,
            enabled: injectAll
        )
        if injectAll {
            applySelectClick(pressed: frame.buttons[.clickSelect] ?? false)
        } else {
            clearSelectHold()
        }
        previousButtons = frame.buttons

        guard injectAll else {
            lastAnalog = frame.analog
            return
        }

        let selectPressed = frame.buttons[.clickSelect] ?? false
        if selectPressed {
            pointerFrozenUntil = Date().addingTimeInterval(0.18)
        }

        let fingerDown = frame.analog[.appleTVClickpad]?.active == true
        let wheelIsScroll = profile.appleTVWheel == .scroll || profile.appleTVWheel == .volume
        if !fingerDown {
            wheelGestureLatched = false
        } else if wheelIsScroll,
                  frame.analog[.appleTVWheel]?.active == true,
                  abs(frame.wheelDegrees) > 0.2 {
            wheelGestureLatched = true
        }
        let freezeClickpadPointer = selectPressed || Date() < pointerFrozenUntil
        let treatAsWheel = wheelIsScroll && wheelGestureLatched && fingerDown

        for source in AnalogSource.allCases {
            if source == .appleTVClickpad, treatAsWheel || freezeClickpadPointer {
                lastAnalog[source] = frame.analog[source] ?? AnalogSample()
                continue
            }
            let sample = frame.analog[source] ?? AnalogSample()
            applyAnalog(source: source, sample: sample, wheelDegrees: frame.wheelDegrees)
        }
    }

    private func applyVolumeRepeat(upPressed: Bool, downPressed: Bool, enabled: Bool = true) {
        guard enabled else {
            volumeRepeatButton = nil
            return
        }
        let held: DeviceButton?
        if upPressed, !downPressed {
            held = .volumeUp
        } else if downPressed, !upPressed {
            held = .volumeDown
        } else {
            held = nil
        }

        guard let held else {
            volumeRepeatButton = nil
            return
        }

        let action = profile.bindings[held] ?? .none
        guard action != .none else {
            volumeRepeatButton = nil
            return
        }

        let now = Date()
        if volumeRepeatButton != held {
            pulse(action)
            volumeRepeatButton = held
            volumeRepeatAt = now.addingTimeInterval(0.32)
            return
        }
        guard now >= volumeRepeatAt else { return }
        pulse(action)
        volumeRepeatAt = now.addingTimeInterval(0.085)
    }

    private func pulse(_ action: ControlAction) {
        perform(action, down: true)
        perform(action, down: false)
    }

    private func applySelectClick(pressed: Bool) {
        let shortAction = profile.bindings[.clickSelect] ?? .none
        let longAction = profile.bindings[.clickSelectLong] ?? .mouseRight

        if pressed {
            if selectDownAt == nil {
                selectDownAt = Date()
                selectDidLongPress = false
            } else if !selectDidLongPress,
                      let start = selectDownAt,
                      Date().timeIntervalSince(start) >= selectHoldDuration {
                selectDidLongPress = true
                perform(longAction, down: true)
            }
            return
        }

        guard selectDownAt != nil else { return }
        if selectDidLongPress {
            perform(longAction, down: false)
        } else {
            perform(shortAction, down: true)
            perform(shortAction, down: false)
        }
        clearSelectHold()
    }

    private func clearSelectHold() {
        selectDownAt = nil
        selectDidLongPress = false
    }

    private func applyAnalog(source: AnalogSource, sample: AnalogSample, wheelDegrees: Double) {
        if source == .dualSenseTouchpad, profile.bindings[.touchpadOneFinger] == .gestures {
            lastAnalog[source] = sample
            return
        }
        let mode = profile.mode(for: source)
        defer { lastAnalog[source] = sample }
        guard mode != .off else { return }

        if source == .appleTVWheel {
            applyWheel(mode: mode, degrees: wheelDegrees, active: sample.active || wheelGestureLatched)
            return
        }

        switch mode {
        case .off:
            return
        case .pointer:
            movePointer(source: source, sample: sample)
        case .scroll:
            scroll(source: source, sample: sample)
        case .volume:
            volume(source: source, sample: sample, wheelDegrees: wheelDegrees)
        }
    }

    private func movePointer(source: AnalogSource, sample: AnalogSample) {
        switch source {
        case .dualSenseLeftStick, .dualSenseRightStick:
            moveStickPointer(sample: sample)
        case .dualSenseTouchpadSecondary:
            return
        case .dualSenseTouchpad, .appleTVClickpad:
            guard sample.active else {
                pointerSmoothX = 0
                pointerSmoothY = 0
                pointerSmoothGain = 1
                return
            }
            let previous = lastAnalog[source]
            guard let previous, previous.active else { return }
            let rawDx = Double(sample.x - previous.x)
            let rawDy = Double(sample.y - previous.y) * (source == .dualSenseTouchpad ? -1 : 1)
            let rawMag = hypot(rawDx, rawDy)
            let blend = min(0.85, 0.24 + rawMag * 32)
            pointerSmoothX += (rawDx - pointerSmoothX) * blend
            pointerSmoothY += (rawDy - pointerSmoothY) * blend
            let mag = hypot(pointerSmoothX, pointerSmoothY)
            guard mag >= 0.0003 else { return }

            let base = (source == .dualSenseTouchpad ? dualSensePointerSpeed : pointerSpeed) * 40
            var targetGain = 1.0
            if profile.pointerAcceleration ?? true {
                let amount = min(max(profile.pointerAccelerationAmount ?? 0.3, 0), 1)
                let speed = rawMag * 60
                let t = min(max(speed / 1.55, 0), 7)
                targetGain = 0.55 + pow(t, 1.38) * (0.1 + amount * 1.2)
            }
            let gainBlend = rawMag > 0.012 ? 0.55 : 0.28
            pointerSmoothGain += (targetGain - pointerSmoothGain) * gainBlend

            pointerRemainderX += pointerSmoothX * base * pointerSmoothGain
            pointerRemainderY += pointerSmoothY * base * pointerSmoothGain
            let emitX = pointerRemainderX
            let emitY = pointerRemainderY
            guard hypot(emitX, emitY) >= 0.06 else { return }
            pointerRemainderX = 0
            pointerRemainderY = 0
            EventPoster.moveMouse(dx: emitX, dy: emitY)
        case .appleTVWheel:
            break
        }
    }

    /// DualSense does not use the MX half-speed curve. 100% should cross the
    /// screen on a firm stick tilt.
    private var dualSensePointerSpeed: Double {
        12 + profile.resolvedPointerSpeed * 44
    }

    /// Stick / clickpad / touchpad analog scroll. Uses the full 0…1 slider.
    /// The MX `appliedWheelScrollSpeed` half-curve made 50%→100% only ~1.7×.
    /// 50% matches the old mid feel; 0% is clearly slow and 100% is clearly fast.
    private var analogScrollGain: Double {
        let slider = profile.resolvedWheelScrollSpeed
        if slider <= 0.5 {
            return 0.04 + (slider / 0.5) * 0.22
        }
        return 0.26 + ((slider - 0.5) / 0.5) * 0.94
    }

    private func moveStickPointer(sample: AnalogSample) {
        let dead = 0.10
        let x = Double(sample.x)
        let y = Double(-sample.y)
        let mag = hypot(x, y)
        if mag <= dead {
            stickSmoothX *= 0.58
            stickSmoothY *= 0.58
            stickSmoothGain += (1 - stickSmoothGain) * 0.35
            if hypot(stickSmoothX, stickSmoothY) < 0.008 {
                stickSmoothX = 0
                stickSmoothY = 0
                return
            }
        } else {
            let scaled = min((mag - dead) / (1 - dead), 1)
            let targetX = x / mag * scaled
            let targetY = y / mag * scaled
            let blend = 0.55
            stickSmoothX += (targetX - stickSmoothX) * blend
            stickSmoothY += (targetY - stickSmoothY) * blend
            var targetGain = 1.0
            if profile.pointerAcceleration ?? true {
                let amount = min(max(profile.pointerAccelerationAmount ?? 0.3, 0), 1)
                let t = min(hypot(stickSmoothX, stickSmoothY), 1)
                targetGain = 0.85 + pow(t, 1.35) * (0.35 + amount * 1.6)
            }
            stickSmoothGain += (targetGain - stickSmoothGain) * 0.38
        }
        EventPoster.moveMouse(
            dx: stickSmoothX * dualSensePointerSpeed * stickSmoothGain,
            dy: stickSmoothY * dualSensePointerSpeed * stickSmoothGain
        )
    }

    private func scroll(source: AnalogSource, sample: AnalogSample) {
        switch source {
        case .dualSenseLeftStick, .dualSenseRightStick:
            let dead: Float = 0.18
            let dy = abs(sample.y) > dead ? Double(-sample.y) : 0
            let dx = abs(sample.x) > dead ? Double(sample.x) : 0
            let mag = hypot(dx, dy)
            let gain = analogScrollFactor(magnitude: mag, stick: true)
            EventPoster.scroll(deltaY: dy * gain * 24 * scrollSign, deltaX: dx * gain * 24 * scrollSign, continuous: true)
        case .dualSenseTouchpadSecondary:
            return
        case .dualSenseTouchpad, .appleTVClickpad:
            guard sample.active, let previous = lastAnalog[source], previous.active else { return }
            let dx = Double(sample.x - previous.x)
            let dy = Double(sample.y - previous.y) * (source == .dualSenseTouchpad ? -1 : 1)
            let gain = analogScrollFactor(magnitude: hypot(dx, dy), stick: false)
            EventPoster.scroll(
                deltaY: dy * gain * 420 * scrollSign,
                deltaX: dx * gain * 420 * scrollSign,
                continuous: true
            )
        case .appleTVWheel:
            break
        }
    }

    private func usesTriggerTabs(_ button: DeviceButton) -> Bool {
        isDualSense && (button == .l2 || button == .r2) && (profile.bindings[button]?.isTabSwitch == true)
    }

    private func processTriggerTabs(_ frame: ControlFrame, injectAll: Bool) {
        guard injectAll else {
            leftTriggerTravel.reset()
            rightTriggerTravel.reset()
            return
        }
        let interval = profile.resolvedTabRepeatInterval
        if usesTriggerTabs(.l2) {
            let count = leftTriggerTravel.steps(value: frame.leftTrigger, interval: interval)
            pulseTab(profile.bindings[.l2] ?? .none, times: count)
        } else {
            leftTriggerTravel.reset()
        }
        if usesTriggerTabs(.r2) {
            let count = rightTriggerTravel.steps(value: frame.rightTrigger, interval: interval)
            pulseTab(profile.bindings[.r2] ?? .none, times: count)
        } else {
            rightTriggerTravel.reset()
        }
    }

    private func pulseTab(_ action: ControlAction, times: Int) {
        guard action.isTabSwitch, times > 0 else { return }
        for _ in 0..<times {
            perform(action, down: true)
            perform(action, down: false)
        }
    }

    private func analogScrollFactor(magnitude: Double, stick: Bool) -> Double {
        if isDualSense {
            return analogScrollGain * scrollAccelerationFactor(magnitude: magnitude, stick: stick)
        }
        return scrollSpeed
    }

    private func scrollAccelerationFactor(magnitude: Double, stick: Bool) -> Double {
        guard isDualSense, profile.scrollAcceleration == true else { return 1 }
        let amount = min(max(profile.scrollAccelerationAmount ?? 0.3, 0), 1)
        if stick {
            let t = min(max(magnitude, 0), 1)
            return 0.55 + pow(t, 1.45) * (0.7 + amount * 2.2)
        }
        let t = min(max(magnitude * 40, 0), 4)
        return 0.55 + pow(t, 1.3) * (0.15 + amount * 1.4)
    }

    private func applyWheel(mode: AnalogMode, degrees: Double, active: Bool) {
        switch mode {
        case .off:
            wheelVelocity = 0
            scrollPixelRemainderY = 0
            return
        case .scroll, .pointer:
            emitSmoothWheelScroll(degrees: degrees, active: active)
        case .volume:
            if !active {
                return
            }
            wheelRemainder += degrees
            if wheelRemainder > 18 {
                EventPoster.media(MediaKey.soundUp, down: true)
                EventPoster.media(MediaKey.soundUp, down: false)
                wheelRemainder = 0
            } else if wheelRemainder < -18 {
                EventPoster.media(MediaKey.soundDown, down: true)
                EventPoster.media(MediaKey.soundDown, down: false)
                wheelRemainder = 0
            }
        }
    }

    private func emitSmoothWheelScroll(degrees: Double, active: Bool) {
        let frameSeconds = 1.0 / 60.0
        if !active || abs(degrees) < 0.04 {
            if abs(wheelVelocity) > 50 {
                let coast = lastWheelSign * min(abs(wheelVelocity) * frameSeconds * 0.45, 10)
                wheelVelocity *= 0.78
                postAcceleratedScroll(degrees: coast)
            } else {
                wheelVelocity = 0
                scrollPixelRemainderY *= 0.4
            }
            return
        }

        let instant = abs(degrees) / frameSeconds
        wheelVelocity = wheelVelocity * 0.62 + instant * 0.38
        lastWheelSign = degrees >= 0 ? 1 : -1
        postAcceleratedScroll(degrees: degrees)
    }

    private func postAcceleratedScroll(degrees: Double) {
        let speed = wheelVelocity
        let curve = 0.45 + pow(min(max(speed / 95, 0), 8), 1.22) * 0.78
        let pixels = degrees * 3.6 * curve * (scrollSpeed / 0.35)
        scrollPixelRemainderY += pixels
        guard abs(scrollPixelRemainderY) >= 0.4 else { return }
        let emit = scrollPixelRemainderY
        scrollPixelRemainderY = 0
        EventPoster.scroll(deltaY: emit * scrollSign, continuous: true)
    }

    private var scrollSign: Double {
        profile.resolvedNaturalScrolling ? 1.0 : -1.0
    }

    private func processGesture(_ frame: ControlFrame, injectAll: Bool) {
        let resolved = resolveGesture(frame)
        let holding = resolved.active
            && resolved.owner.canOwnGestures
            && profile.bindings[resolved.owner] == .gestures

        if !injectAll {
            padGesture.cancel()
            return
        }

        if holding, let set = profile.gestureSet(for: resolved.owner) {
            if padGesture.owner != resolved.owner {
                padGesture.begin(owner: resolved.owner, set: set)
            }
            if let action = padGesture.move(x: resolved.x, y: resolved.y) {
                perform(action, down: true)
                perform(action, down: false)
            }
            return
        }

        if let tap = padGesture.isActive ? padGesture.end() : nil {
            perform(tap, down: true)
            perform(tap, down: false)
        }
    }

    private func resolveGesture(_ frame: ControlFrame) -> (owner: DeviceButton, active: Bool, x: Double, y: Double) {
        if profile.bindings[.touchpadOneFinger] == .gestures
            || profile.bindings[.touchpadTwoFinger] == .gestures {
            let scale = MappingProfile.gestureSpeedFactor(
                slider: profile.resolvedHapticGestureSpeed,
                dpi: MappingProfile.defaultSensorDPI
            ) * DualSenseTouchGesture.pixelsPerUnit
            touchGesture.update(
                touch1: frame.analog[.dualSenseTouchpad] ?? AnalogSample(),
                touch2: frame.analog[.dualSenseTouchpadSecondary] ?? AnalogSample(),
                scale: scale
            )
            if let owner = touchGesture.owner {
                return (owner, touchGesture.active, touchGesture.x, touchGesture.y)
            }
        } else if touchGesture.active || touchGesture.owner != nil {
            touchGesture.reset()
        }

        return (
            frame.gestureOwner ?? .mxHaptic,
            frame.gestureActive,
            frame.gestureX,
            frame.gestureY
        )
    }

    private func resolvedAction(for button: DeviceButton) -> ControlAction {
        if let action = profile.bindings[button] {
            return action
        }
        return button.isMXScrollDirection ? .scroll : .none
    }

    private func postInjectedScroll(_ frame: ControlFrame) {
        var dy = frame.scrollY
        var dx = frame.scrollX
        if dy > 0, !profile.keepsNativeScroll(for: .mxWheelUp) { dy = 0 }
        if dy < 0, !profile.keepsNativeScroll(for: .mxWheelDown) { dy = 0 }
        if dx > 0, !profile.keepsNativeScroll(for: .mxThumbRight) { dx = 0 }
        if dx < 0, !profile.keepsNativeScroll(for: .mxThumbLeft) { dx = 0 }
        dy *= (0.35 + profile.appliedWheelScrollSpeed * 4.2) * scrollSign
        dx *= (0.35 + profile.appliedThumbScrollSpeed * 4.2) * scrollSign
        EventPoster.scroll(deltaY: dy, deltaX: dx, continuous: true)
    }

    private func volume(source: AnalogSource, sample: AnalogSample, wheelDegrees: Double) {
        if source == .appleTVWheel {
            applyWheel(mode: .volume, degrees: wheelDegrees, active: true)
            return
        }
        let value = sample.y
        if value > 0.55 {
            EventPoster.media(MediaKey.soundUp, down: true)
            EventPoster.media(MediaKey.soundUp, down: false)
        } else if value < -0.55 {
            EventPoster.media(MediaKey.soundDown, down: true)
            EventPoster.media(MediaKey.soundDown, down: false)
        }
    }

    private func perform(_ action: ControlAction, down: Bool) {
        if down {
            ActionHUD.show(action)
        }
        switch action {
        case .switchApplication, .switchApplicationBack, .none, .gestures, .scroll:
            break
        default:
            AppSwitcher.cancel()
        }
        switch action {
        case .none, .gestures, .scroll:
            return
        case .key(let virtualKey, let flags):
            EventPoster.key(virtualKey, flags: CGEventFlags(rawValue: flags), down: down)
        case .mediaPlayPause:
            EventPoster.media(MediaKey.play, down: down)
        case .mediaVolumeUp:
            EventPoster.media(MediaKey.soundUp, down: down)
        case .mediaVolumeDown:
            EventPoster.media(MediaKey.soundDown, down: down)
        case .mediaMute:
            EventPoster.media(MediaKey.mute, down: down)
        case .mediaNext:
            EventPoster.media(MediaKey.next, down: down)
        case .mediaPrevious:
            EventPoster.media(MediaKey.previous, down: down)
        case .mouseLeft:
            if profile.stickyTargeting == true,
               !EventPoster.wouldBeDoubleClick(right: false),
               StickyTargeting.handleMouse(right: false, down: down) {
                if down { EventPoster.recordClick(right: false) }
                return
            }
            EventPoster.mouseClick(right: false, down: down)
        case .mouseRight:
            if profile.stickyTargeting == true,
               !EventPoster.wouldBeDoubleClick(right: true),
               StickyTargeting.handleMouse(right: true, down: down) {
                if down { EventPoster.recordClick(right: true) }
                return
            }
            EventPoster.mouseClick(right: true, down: down)
        case .missionControl:
            if down { EventPoster.system(.missionControl) }
        case .appExpose:
            if down { EventPoster.system(.appExpose) }
        case .showDesktop:
            if down { EventPoster.system(.showDesktop) }
        case .spaceLeft:
            if down {
                if isDualSense {
                    DockSwipe.playOneSpace(axis: .horizontal, towardPositive: false)
                } else {
                    EventPoster.system(.spaceLeft)
                }
            }
        case .spaceRight:
            if down {
                if isDualSense {
                    DockSwipe.playOneSpace(axis: .horizontal, towardPositive: true)
                } else {
                    EventPoster.system(.spaceRight)
                }
            }
        case .browserBack:
            EventPoster.key(33, flags: .maskCommand, down: down)
        case .browserForward:
            EventPoster.key(30, flags: .maskCommand, down: down)
        case .tabPrevious:
            EventPoster.key(33, flags: [.maskCommand, .maskShift], down: down)
        case .tabNext:
            EventPoster.key(30, flags: [.maskCommand, .maskShift], down: down)
        case .switchApplication:
            if down { EventPoster.system(.switchApplication) }
        case .switchApplicationBack:
            if down { EventPoster.system(.switchApplicationBack) }
        case .screenCapture:
            EventPoster.key(21, flags: [.maskCommand, .maskShift], down: down)
        case .closeWindow:
            EventPoster.key(13, flags: .maskCommand, down: down)
        }
    }
}
