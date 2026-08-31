# System Monitor row order cannot be dragged

## Symptom

System Monitor settings show a drag handle and say “Drag to reorder,” but rows do not move. A later `onDrag`/`onDrop` path could move them, but other rows did not slide aside.

## Cause

`top` uses a `List` plus `.onMove`, which is the native table reorder (rows make a gap). Control Box put the same `.onMove` on a `Form`, which does not start a drag on macOS.

## What we changed

Use a `List` with `.onMove`, same as `PreferencesView` in [top](https://github.com/whitesticker/top).

## Do not

Put this reorder list back in a `Form`, or replace `.onMove` with item-provider drag-and-drop.
