import ControlBoxCore

enum ControlFrameBuilder {
    static func make(from snapshot: DualSenseSnapshot) -> ControlFrame {
        ControlFrame(
            buttons: [
                .cross: snapshot.cross,
                .circle: snapshot.circle,
                .square: snapshot.square,
                .triangle: snapshot.triangle,
                .dpadUp: snapshot.dpadUp,
                .dpadDown: snapshot.dpadDown,
                .dpadLeft: snapshot.dpadLeft,
                .dpadRight: snapshot.dpadRight,
                .l1: snapshot.l1,
                .r1: snapshot.r1,
                .l2: snapshot.l2 > 0.15,
                .r2: snapshot.r2 > 0.15,
                .l3: snapshot.l3,
                .r3: snapshot.r3,
                .create: snapshot.create,
                .options: snapshot.options,
                .ps: snapshot.ps,
                .touchpadClick: snapshot.touchpadClick,
                .touchpadOneFinger: snapshot.touch1.active && !snapshot.touch2.active,
                .touchpadTwoFinger: snapshot.touch1.active && snapshot.touch2.active
            ],
            analog: [
                .dualSenseLeftStick: AnalogSample(x: snapshot.leftStick.x, y: snapshot.leftStick.y, active: true),
                .dualSenseRightStick: AnalogSample(x: snapshot.rightStick.x, y: snapshot.rightStick.y, active: true),
                .dualSenseTouchpad: AnalogSample(x: snapshot.touch1.x, y: snapshot.touch1.y, active: snapshot.touch1.active),
                .dualSenseTouchpadSecondary: AnalogSample(x: snapshot.touch2.x, y: snapshot.touch2.y, active: snapshot.touch2.active)
            ],
            leftTrigger: snapshot.l2,
            rightTrigger: snapshot.r2
        )
    }

    static func make(from snapshot: AppleTVRemoteSnapshot) -> ControlFrame {
        ControlFrame(
            buttons: [
                .back: snapshot.back,
                .tv: snapshot.tv,
                .siri: snapshot.siri,
                .mute: snapshot.mute,
                .playPause: snapshot.playPause,
                .power: snapshot.power,
                .volumeUp: snapshot.volumeUp,
                .volumeDown: snapshot.volumeDown,
                .clickSelect: snapshot.select,
                .clickUp: snapshot.clickUp,
                .clickDown: snapshot.clickDown,
                .clickLeft: snapshot.clickLeft,
                .clickRight: snapshot.clickRight
            ],
            analog: [
                .appleTVClickpad: AnalogSample(
                    x: snapshot.touchX,
                    y: snapshot.touchY,
                    active: snapshot.touchActive
                ),
                .appleTVWheel: AnalogSample(active: snapshot.wheelActive)
            ],
            wheelDegrees: snapshot.wheelDegrees
        )
    }

    static func make(from snapshot: MXMasterSnapshot) -> ControlFrame {
        let buttons: [DeviceButton: Bool] = [
            .mxBack: snapshot.back,
            .mxForward: snapshot.forward,
            .mxSmartShift: snapshot.smartShift,
            .mxModeShift: snapshot.modeShift,
            .mxHaptic: snapshot.haptic,
            .mxLeft: snapshot.left,
            .mxRight: snapshot.right,
            .mxMiddle: snapshot.middle,
            .mxWheelUp: snapshot.wheelUp,
            .mxWheelDown: snapshot.wheelDown,
            .mxThumbLeft: snapshot.thumbLeft,
            .mxThumbRight: snapshot.thumbRight,
            .mxSide: snapshot.side
        ]
        return ControlFrame(
            buttons: buttons,
            scrollY: snapshot.pendingScrollY,
            scrollX: snapshot.pendingScrollX,
            gestureSlot: snapshot.pendingGesture,
            gestureOwner: snapshot.pendingGestureOwner ?? snapshot.liveGestureOwner,
            gestureActive: snapshot.gestureHeld || snapshot.gestureDown || snapshot.haptic,
            gestureX: snapshot.gestureDX,
            gestureY: snapshot.gestureDY
        )
    }
}
