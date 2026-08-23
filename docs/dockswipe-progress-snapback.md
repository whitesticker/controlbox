# Spaces / Mission Control snap backward mid-swipe

## Symptom

During a haptic hold-to-swipe, desktop or Mission Control progress jumps back toward the start, then continues. Feels like flicker, not a full cancel.

## Cause

Live DockSwipe was posted as **deltas**. One missing, reset, or teleport sample (HID accumulator cleared, first raw-XY ignored, or a report of 0) subtracted a large `dx`/`dy`. Field `124` walked backward.

Pointer motion during the hold could also cancel or fight the dock-swipe. The MX4 BLE haptic XY stays on the same mouse report as the pointer.

## What we changed

- `DockSwipe.Session.setAbsolute` posts the hold’s accumulated progress, not a per-sample delta.
- `LiveGestureState` ignores a sample that jumps toward the origin (teleport reject).
- While the pad is held, freeze the cursor and swallow mouse-move / dragged events.

Release ends the session immediately (`finishHapticNow`). Do not add a 180 ms release debounce; that hid dropouts but delayed Spaces commit.

## Do not

Go back to incremental `origin += delta` for live Spaces. Do not set `CGEvent.type = 30` (only field 55); that broke vertical.
