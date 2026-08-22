# Extra buttons do not show in Calibration

## Symptom

On MX Master 4, Calibration lights up left / right / middle / wheel (when the listen-only event tap is working) but haptic, back, forward, and mode shift do not.

## Cause

Those controls are not normal macOS mouse buttons on this machine. Logitech firmware keeps them on HID++ until we **divert** that CID.

On Bluetooth LE, the Master 4 haptic pad is not a missing HID++ CID. It is HID button 7 on the normal mouse report. See [mx-master-4-ble-haptic.md](mx-master-4-ble-haptic.md).

After we stopped seizing devices and stopped diverting aggressively (to keep the pointer alive), HID++ stopped delivering those button notifications. Calibration reads `MXMasterSnapshot`; if HID++ never sets `haptic` / `back` / `forward`, the diagram stays idle.

## What this is not

Not a SwiftUI refresh bug by itself. The snapshot never receives the press.

## Implication

Calibration for extra buttons and “hold haptic + swipe” both depend on a working, narrow HID++ divert. Event taps cannot replace that for Master 4 extra controls.
