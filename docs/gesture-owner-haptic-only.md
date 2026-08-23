# Only the haptic pad runs gestures

## Current rule

**Gestures is haptic-pad only.** Profiles no longer offer Gestures on Back, Forward, middle, left, or right. Saved profiles that had those assignments are reset to ordinary clicks (Back / Forward → browser).

Click-as-gesture is parked. See [haptic-vs-back-gesture.md](haptic-vs-back-gesture.md).

## Why we tried more owners

The profile can store a `GestureSet` per button, but only the haptic pad has press + XY on the same report. Extra buttons are clicks. Hold-Back-and-move uses the desk laser, which is a different sensor and never followed live Spaces reliably.

Diverting left/right/middle over HID++ (`0x0050` / `0x0051` / `0x0052`) can steal the system pointer.

## Do not

HID++-divert the standard click CIDs to make left/right/middle into gesture buttons. Do not put Gestures back on those pickers until laser follow is actually solved.
