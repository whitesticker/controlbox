# Haptic tap starts a swipe

## Symptom

A tap on the haptic pad (click action) also starts Spaces or Mission Control. The desktop peeks or switches when the user only meant to click.

## Cause

The pad reports X/Y while the finger is down. A tap always has a little travel. Live DockSwipe used to lock an axis as soon as travel hit ~10 px and post swipe events during the press.

Release classification also used distance only (`pointerSwipeDistance` 70). A wobbly tap could be labeled a swipe, and then neither a clean tap nor a real swipe fired.

## What we changed

Wait **100ms** after press before any swipe action:

- `LiveGestureState` records hold start and ignores axis lock / DockSwipe / App Exposé until 100ms.
- `finishGesture` treats a hold shorter than 100ms as a tap even if the pad moved.

After 100ms, hold + move is a swipe as before.

## Do not

Bring back a 180 ms **release** debounce to fix this. That delay was for HID++ dropouts and made Spaces commit late. Tap vs swipe is an **arm** delay on press, not a delay on release.
