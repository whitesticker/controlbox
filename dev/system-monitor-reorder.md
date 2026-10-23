# System Monitor row order cannot be dragged

## Symptom

System Monitor settings show a drag handle and say “Drag to reorder,” but rows do not move. A later `onDrag`/`onDrop` path could move them, but other rows did not slide aside.

## Cause

`top` uses a `List` plus `.onMove`, which is the native table reorder (rows make a gap). Control Box put the same `.onMove` on a `Form`, which does not start a drag on macOS.

## What we changed

First: a `List` with `.onMove`, same as `PreferencesView` in [top](https://github.com/whitesticker/top). The pane later went back to one grouped `Form` (Menu Bar Icon, History, and Quick launch sections), and dragging rows stopped again.

Now: each row has `.onDrag` plus a `DashboardRowDropDelegate` that moves the dragged row in `dropEntered` with `withAnimation(.snappy)`, so the other rows slide aside while dragging. This is the same pattern as the Quick launch tiles and Menu Bar Icon tiles on the same pane, which do drag inside the `Form`. The old “rows did not slide aside” problem came from moving only in `performDrop`.

## Do not

- Put `.onMove` back on these rows inside the `Form`.
- Move rows only in `performDrop`; move in `dropEntered` so the rows slide.
