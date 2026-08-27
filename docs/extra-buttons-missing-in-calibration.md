# Extra buttons do not show in Calibration

## Symptom

On MX Master 4, Calibration lights up left / right / middle / wheel (when those arrive on report `0x02` or the shared click probe) but haptic, back, forward, mode shift, and **Side** do not.

Left / right / wheel themselves going dark is a different bug: [mx4-clicks-missing-in-calibration.md](mx4-clicks-missing-in-calibration.md).

## Cause

Those controls are not normal macOS mouse buttons on this machine. Logitech firmware keeps them on HID++ until we **divert** that CID.

On Bluetooth LE, the Master 4 haptic pad is not a missing HID++ CID. It is HID button 7 on the normal mouse report. See [mx-master-4-ble-haptic.md](mx-master-4-ble-haptic.md).

After we stopped seizing devices and stopped diverting aggressively (to keep the pointer alive), HID++ stopped delivering those button notifications. Calibration reads `MXMasterSnapshot`; if HID++ never sets `haptic` / `back` / `forward` / `side`, the diagram stays idle.

## MX4 Side (CID `0x00C3`)

Solaar “Mouse Gesture Button”. On MX4 this is the frontmost thumb button **under the roller**, in front of Back / Forward (factory Switch Desktop on Mac). It is **not** the haptic pad (`0x01A0` / HID button 7).

On 3S, CID `0x00C3` is the thumb **gesture** button (bound as `.mxHaptic`). Same CID, different hardware. Divert Side as a **button** (`0x03`), not gesture raw-XY (`0x33`).

Device button `.mxSide`, default `.missionControl`. Load `ensureMX4SideButton()` on MX4 profiles. Hide the row on 3S.

## What this is not

Not a SwiftUI refresh bug by itself. The snapshot never receives the press.

## Implication

Calibration for extra buttons and “hold haptic + swipe” both depend on a working, narrow HID++ divert. Event taps cannot replace that for Master 4 extra controls.
