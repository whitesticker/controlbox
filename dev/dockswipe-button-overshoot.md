# Discrete desktop switch peeks into the next Space

## Symptom

L1 / R1 (or any button) mapped to Previous / Next desktop slides past the target Space — e.g. 1 → 2 briefly shows 3 — then rubber-bands back to 2.

## Cause

`SystemNavigation` played a live DockSwipe with offset **±1.5**. Progress 1.0 is one desktop. 1.5 is halfway into the *next* one. On `.ended`, macOS commits one Space and snaps the extra half back.

High exit speed (`lastDelta * 100`) on that synthetic burst made the fling worse.

## What we changed

DualSense only (`ControlEngine.isDualSense` → `DockSwipe.playOneSpace`). Lands at **±1.0** with a modest exit speed.

Apple TV and MX buttons still use `DockSwipe.play(±1.5)` and end as posted (`snapToNearestPage: false`). Live haptic / touchpad hold-to-swipe snaps to the nearest page on release. See [dockswipe-commit-nearest.md](dockswipe-commit-nearest.md).
