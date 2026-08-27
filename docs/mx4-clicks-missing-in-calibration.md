# MX4 left / right / wheel do not light in Calibration

## Symptom

On MX Master 4, Calibration lights extra HID++ buttons (Back, Forward, Side, Mode) and the haptic pad. Left click, right click, and wheel motion stay idle. 3S on the same Mac still lights those controls.

## Cause

Left / right / wheel were supposed to come from a **per-reader** `CGEvent` session tap (`startClickProbe`). 3S starts first and creates a `defaultTap`. A second `CGEvent.tapCreate` for MX4 often returns nil. Calibration for MX4 reads `mx4Reader.current`, so those clicks never update that snapshot.

`startMouse()` (IOHIDManager on usage `0x01` / `0x02`) is intentionally unused. Opening the standard mouse collection just to watch buttons can steal the system pointer.

MX4 already receives native report `0x02` on the HID++ device callback (same path as haptic bit `0x40`). That path used to return after haptic / gesture XY and did **not** parse left / right / middle / wheel.

## What we changed

- One shared session tap (`MXClickProbe`) for every MX reader. Swallow if any reader wants swallow.
- Parse report `0x02` button bits (bit0 left, bit1 right, bit2 middle) and wheel / pan after the 12-bit X/Y field. MX4 has one button byte (`nativeMouseButtonBytes = 1`), so wheel is at index 5. Pulse wheel / thumb for 0.18s so Calibration can show motion.

Do not call `startMouse()`. Do not seize HID.

## Do not

Open the standard Logitech mouse collection (`0x01` / `0x02`) to fix this. Do not give each reader its own `CGEvent.tapCreate`.

## Related

- [extra-buttons-missing-in-calibration.md](extra-buttons-missing-in-calibration.md) — HID++ extra buttons, including MX4 Side
- [mx-master-4-ble-haptic.md](mx-master-4-ble-haptic.md) — report `0x02` layout
- [hid-open-seize-dual-mouse.md](hid-open-seize-dual-mouse.md)
