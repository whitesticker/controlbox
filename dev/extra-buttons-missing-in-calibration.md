# Extra buttons do not show in Calibration

## Symptom

On MX Master 4, Calibration lights up left / right / middle / wheel (when those arrive on report `0x02` or the shared click probe) but haptic, back, forward, mode shift, and the **gesture button** do not.

Left / right / wheel themselves going dark is a different bug: [mx4-clicks-missing-in-calibration.md](mx4-clicks-missing-in-calibration.md).

## Cause

Those controls are not normal macOS mouse buttons on this machine. Logitech firmware keeps them on HID++ until we **divert** that CID.

On Bluetooth LE, the Master 4 haptic pad is not a missing HID++ CID. It is HID button 7 on the normal mouse report. See [mx-master-4-ble-haptic.md](mx-master-4-ble-haptic.md).

After we stopped seizing devices and stopped diverting aggressively (to keep the pointer alive), HID++ stopped delivering those button notifications. Calibration reads `MXMasterSnapshot`; if HID++ never sets `haptic` / `back` / `forward` / `side`, the diagram stays idle.

## Gesture button (CID `0x00C3`)

Logitech Options+ **Gesture button**. Solaar “Mouse Gesture Button”. On 3 / 3S / 4 this is the thumb button in front of Back / Forward. It is **not** the MX4 haptic pad (`0x01A0` / HID button 7). Internal enum is still `.mxSide` (Codable `"mxSide"`); the title is **Gesture button**.

When it owns Gestures, divert hold-only raw XY (`0x33`), same as OpenLogi. Do not pin the pointer. Click-only divert (`0x03`) restores a tap but kills swipe. See [mx4-gesture-button-freezes-pointer.md](mx4-gesture-button-freezes-pointer.md).

Default on 3 / 3S / 4 is Gestures (window navigation). `ensureThumbGestureButton()` loads that on saved profiles that have no row yet.

## What this is not

Not a SwiftUI refresh bug by itself. The snapshot never receives the press.

## Implication

Calibration for extra buttons and “hold haptic + swipe” both depend on a working, narrow HID++ divert. Event taps cannot replace that for Master 4 extra controls. Cursor-travel (OS-hook) swipe is not how OpenLogi drives this CID; do not use it for Logitech products.
