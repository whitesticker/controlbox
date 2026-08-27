# Gestures still control the Mac while Control Box is focused

## Symptom

**Allow while Control Box is focused** is off. Calibration (or any Control Box window) is frontmost. MX haptic / 3S gesture / DualSense touchpad still move Spaces, Mission Control, or other mapped actions.

## Cause

`ControlEngine` skipped ordinary button injection when the host was active, but `processGesture` and some button `perform` paths treated system-navigation actions as always allowed. Thumb HID++ scroll (`postInjectedScroll`) and MX window grab also ran before that gate.

Calibration is a Control Box window, so “don’t inject while we are focused” has to mean **all** injection, including DockSwipe and discrete system actions.

## What we changed

If the host is frontmost and `postsWhenHostIsActive` is false, return before gesture, scroll, window grab, and button perform. `isSystemNavigation` is not a bypass.

Window grab in `DualSenseMonitor` uses the same inject flag so Control+move does not drag windows while Control Box is focused.

## Do not

Re-add an `isSystemNavigation` exception in `processGesture` or `perform` so Spaces still works on the Calibration page.
