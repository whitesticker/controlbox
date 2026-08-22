import CoreGraphics
import Foundation

public final class ControlEngine: @unchecked Sendable {
    public var profile: MappingProfile
    public var enabled = false
    public var postsWhenHostIsActive = false
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
    private var pointerFrozenUntil = Date.distantPast
    private var wheelGestureLatched = false
    private var volumeRepeatAt = Date.distantPast
    private var volumeRepeatButton: DeviceButton?
    private var liveGesture = LiveGestureState()

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
        pointerFrozenUntil = .distantPast
        wheelGestureLatched = false
        volumeRepeatAt = .distantPast
        volumeRepeatButton = nil
        liveGesture.cancel()
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
        scrollSpeed = 0.08 + profile.appliedWheelScrollSpeed * 0.72
        postInjectedScroll(frame)

        guard enabled else {
            previousButtons = frame.buttons
            lastAnalog = frame.analog
            clearSelectHold()
            return
        }

        let injectAll = !hostIsActive || postsWhenHostIsActive
        processGesture(frame, injectAll: injectAll)

        stickyActive = profile.stickyTargeting == true
            && AnalogSource.allCases.contains { profile.mode(for: $0) == .pointer }

        for (button, pressed) in frame.buttons
            where button != .clickSelect
            && button != .clickSelectLong
            && button != .volumeUp
            && button != .volumeDown {
            let wasPressed = previousButtons[button] ?? false
            if pressed != wasPressed {
                let action = profile.bindings[button] ?? .none
                if injectAll || action.isSystemNavigation {
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
            let dead: Float = 0.12
            let dx = abs(sample.x) > dead ? Double(sample.x) : 0
            let dy = abs(sample.y) > dead ? Double(-sample.y) : 0
            if dx != 0 || dy != 0 {
                EventPoster.moveMouse(dx: dx * pointerSpeed, dy: dy * pointerSpeed)
            }
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

            let base = pointerSpeed * 40
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

    private func scroll(source: AnalogSource, sample: AnalogSample) {
        switch source {
        case .dualSenseLeftStick, .dualSenseRightStick:
            let dead: Float = 0.18
            let dy = abs(sample.y) > dead ? Double(-sample.y) : 0
            let dx = abs(sample.x) > dead ? Double(sample.x) : 0
            EventPoster.scroll(deltaY: dy * scrollSpeed * 24 * scrollSign, deltaX: dx * scrollSpeed * 24 * scrollSign, continuous: true)
        case .dualSenseTouchpad, .appleTVClickpad:
            guard sample.active, let previous = lastAnalog[source], previous.active else { return }
            let dy = Double(sample.y - previous.y) * (source == .dualSenseTouchpad ? -1 : 1)
            EventPoster.scroll(
                deltaY: dy * scrollSpeed * 420 * scrollSign,
                deltaX: Double(sample.x - previous.x) * scrollSpeed * 420 * scrollSign,
                continuous: true
            )
        case .appleTVWheel:
            break
        }
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
        let owner = frame.gestureOwner ?? liveGesture.owner ?? .mxHaptic
        let set = profile.gestureSet(for: owner)
        let allow = injectAll
            || set?.click.isSystemNavigation == true
            || set?.up.isSystemNavigation == true
            || set?.down.isSystemNavigation == true
            || set?.left.isSystemNavigation == true
            || set?.right.isSystemNavigation == true
            || set?.up.isLiveVolume == true
            || set?.down.isLiveVolume == true

        if frame.gestureActive {
            guard allow else { return }
            liveGesture.handleMove(x: frame.gestureX, y: frame.gestureY, owner: owner, set: set)
            return
        }

        liveGesture.end()

        guard let slotButton = frame.gestureSlot,
              let slot = GestureSlot.slot(for: slotButton),
              slot == .click
        else { return }
        let action = profile.action(forGesture: slot, owner: owner)
        guard injectAll || action.isSystemNavigation else { return }
        perform(action, down: true)
        perform(action, down: false)
    }

    private func postInjectedScroll(_ frame: ControlFrame) {
        let dy = frame.scrollY * (0.35 + profile.appliedWheelScrollSpeed * 4.2) * scrollSign
        let dx = frame.scrollX * (0.35 + profile.appliedThumbScrollSpeed * 4.2) * scrollSign
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
        switch action {
        case .none, .gestures:
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
            if down { EventPoster.system(.spaceLeft) }
        case .spaceRight:
            if down { EventPoster.system(.spaceRight) }
        case .browserBack:
            EventPoster.key(33, flags: .maskCommand, down: down)
        case .browserForward:
            EventPoster.key(30, flags: .maskCommand, down: down)
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

private struct LiveGestureState {
    enum Axis {
        case horizontal
        case vertical
    }

    var owner: DeviceButton?
    private var lastX = 0.0
    private var lastY = 0.0
    private var hasSample = false
    private var axis: Axis?
    private var space = DockSwipe.Session()
    private var volumeHold = 0.0

    mutating func handleMove(x: Double, y: Double, owner: DeviceButton, set: GestureSet?) {
        self.owner = owner
        guard let set else {
            lastX = x
            lastY = y
            hasSample = true
            return
        }
        let dx = hasSample ? x - lastX : x
        let dy = hasSample ? y - lastY : y
        lastX = x
        lastY = y
        hasSample = true
        let travel = hypot(x, y)

        if axis == nil, travel >= 8 {
            axis = abs(y) >= abs(x) ? .vertical : .horizontal
        }
        guard let axis else { return }

        switch axis {
        case .horizontal:
            applySpace(dx: dx, set: set)
        case .vertical:
            applyVertical(dy: dy, set: set)
        }
    }

    mutating func end() {
        space.end()
        resetTracking()
    }

    mutating func cancel() {
        space.cancel()
        resetTracking()
    }

    private mutating func resetTracking() {
        owner = nil
        lastX = 0
        lastY = 0
        hasSample = false
        axis = nil
        volumeHold = 0
    }

    private mutating func applySpace(dx: Double, set: GestureSet) {
        let action = dx >= 0 ? set.right : set.left
        guard action.isLiveSpace else { return }
        let magnitude = abs(dx) / DockSwipe.horizontalSpan
        let signed = action == .spaceRight ? magnitude : -magnitude
        space.add(signed, axis: .horizontal)
    }

    private mutating func applyVertical(dy: Double, set: GestureSet) {
        let action = dy < 0 ? set.up : set.down
        if action.isLiveMissionSwipe {
            space.add(-dy / DockSwipe.liveVerticalSpan, axis: .vertical)
            return
        }
        applyVolume(dy: dy, set: set)
    }

    private mutating func applyVolume(dy: Double, set: GestureSet) {
        let action = dy < 0 ? set.up : set.down
        guard action.isLiveVolume else { return }
        let pixels = abs(dy)
        let amount = pixels / DockSwipe.verticalSpan
        volumeHold += action == .mediaVolumeUp ? amount : -amount
        guard abs(volumeHold) >= 0.001 else { return }
        if let level = SystemVolume.adjust(by: volumeHold) {
            VolumeHUD.show(level: level)
        }
        volumeHold = 0
    }
}
