# MX SmartShift and thumb-wheel sensitivity

Implemented 2026-09-07. HID++ bytes follow OpenLogi (`0x2110` / `0x2111` / `0x2150`).

## Main wheel: Free Spin / Ratchet

Each MX **Calibration** sidebar **On this mouse** card has a segmented control (Free Spin / Ratchet) and a **Sensitivity** slider. These write MagSpeed SmartShift on the mouse, not a Control mapping.

A SmartShift HID++ error must not drop the pipe: `dropsPipeOnError` is false, and thumb divert (`0x2150`) is re-applied after the write so MagSpeed does not leave the thumb wheel native.

| Feature | When | Functions |
|---|---|---|
| `0x2111` SmartShift Enhanced | MX Master 3 / 3S / 4 | Get status = fn 1. Set = fn 2 `[mode, autoDisengage, torque]`. Torque `0` = leave unchanged. |
| `0x2110` SmartShift | Fallback (MX Master 2S-class) | Get = fn 0. Set = fn 1 `[mode, autoDisengage, default]`. Default `0` = leave unchanged. |

Wire `mode`: `1` = free-spin, `2` = ratchet, `0` = do not change. `autoDisengage` `8…50` is the OpenLogi slider band (0.25 turn/s steps; higher keeps the ratchet longer before free-spin). `0` is the firmware preserve sentinel and must not be stored. `0xFF` is permanent ratchet (not exposed yet).

Firmware RAM resets on power cycle, so Control Box stores the choice on the mouse’s Default profile and re-applies after HID++ attach, same as DPI.

HiResWheel ratchet-switch events (`0x2121` fn 1) report the *mechanical* state, including auto-disengage. Do not drive the picker from those; they flicker during a fast scroll.

## Thumb wheel sensitivity

Calibration **On this mouse**, next to DPI. OpenLogi-style scale of diverted HID++ `0x2150` deltas in `MXWheelActionEngine` (50% = OpenLogi 14 = 1×). Thumb scroll is re-synthesised as line ticks. Pointer & Scroll **Wheel speed** stays on native / tap main-wheel events and does not write the thumb feature.

50% is 1× relative to the previous default feel. Device-level (Default profile), not per-app.

## Invert thumb wheel

Same `0x2150` `setThumbwheelReporting` packet as divert: byte 0 = diverted, byte 1 = invert. OpenLogi sets that invert bit from `getThumbwheelInfo` `default_dir` so positive rotation is always physical forward. Control Box exposes it as Calibration **Invert thumb wheel** on this mouse. Re-applied after HID++ attach. This is not HiResWheel `0x2121` (that invert is the main wheel).