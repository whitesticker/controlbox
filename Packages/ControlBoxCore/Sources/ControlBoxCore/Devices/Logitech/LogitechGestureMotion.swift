import CoreGraphics

/// Hold-to-swipe motion for Logitech gesture controls.
///
/// HID++ raw XY and native report `0x02` XY both accumulate into the same
/// hid delta. Prefer that stream when it has moved; otherwise fall back
/// to pointer samples.
public enum LogitechGestureMotion {
    public static func liveDelta(hid: CGSize, pointer: CGSize) -> CGSize {
        if hid.width != 0 || hid.height != 0 {
            return hid
        }
        return pointer
    }
}
