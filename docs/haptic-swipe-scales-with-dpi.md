# Haptic swipes follow sensor DPI

## Symptom

Hold-to-swipe (Spaces, Mission Control) is fine at **1000 DPI**. At higher DPI the same physical pad move is way too fast. It can feel like the swipe is using **pointer speed** instead of **haptic gesture speed**, especially up/down.

Haptic gesture speed at 0% is the comfortable Spaces setting. That bar was not the bug; the HID counts were.

## Cause

The MX4 sensor emits more relative X/Y counts per inch at higher DPI. Haptic accumulation used those raw counts times `gestureSpeedFactor(slider)` only.

Pointer speed already divides by `1000 / dpi` so the cursor does not get faster when DPI goes up. Haptic did not. So 2000 DPI was about 2× the swipe of 1000 DPI.

A short Mission Control span (~48 px vs screen-width for Spaces) made vertical look even faster on top of that.

## What this is not

Not a second Acceleration control. Not “merge the two sliders.” The user wants pointer speed and haptic gesture speed independent.

## What we changed

- `gestureSpeedFactor(slider:dpi:)` multiplies the slider curve by `1000 / dpi`.
- Live vertical span matches horizontal span (screen width) so one haptic bar maps both axes.
- Pointer still uses `pointerSpeedFactor` + `PointerHIDSettings` only.

## Do not

Drop the DPI term from haptic scaling, or apply pointer speed / OS cursor pixels to haptic X/Y.
