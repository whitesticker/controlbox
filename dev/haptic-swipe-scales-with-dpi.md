# Haptic swipes follow sensor DPI

## Symptom

Hold-to-swipe (Spaces, Mission Control) is fine at **1000 DPI**. At higher DPI the same physical pad move is way too fast.

The old haptic gesture speed slider at 0% was the comfortable Spaces setting. That slider was not the bug; the HID counts were. The slider is gone; DPI compensation remains.

## Cause

The MX4 sensor emits more relative X/Y counts per inch at higher DPI. Haptic accumulation used those raw counts times a slider curve only.

Pointer speed already divides by `1000 / dpi` so the cursor does not get faster when DPI goes up. Haptic did not. So 2000 DPI was about 2× the swipe of 1000 DPI.

A short Mission Control span (~48 px vs screen-width for Spaces) made vertical look even faster on top of that.

## What this is not

Not a second Acceleration control. Not “fold swipe feel into pointer speed.”

## What we changed

- `gestureSpeedFactor(dpi:)` multiplies HID travel by `1000 / dpi` (1× at 1000 DPI).
- Live vertical span matches horizontal span (screen width) so one haptic bar maps both axes.
- Pointer still uses `pointerSpeedFactor` + `PointerHIDSettings` only.

## Do not

Drop the DPI term from haptic scaling, or apply pointer speed / OS cursor pixels to haptic X/Y.
