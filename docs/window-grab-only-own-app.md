# Window grab only moves Control Box

## Symptom

Move and resize work on the Control Box window. Finder, Safari, and every other app stay put. It often shows up after the Control Box window has been opened, then you try grab on another app.

Throw and Organize are off unless their toggles are on; the default-on actions are move and resize.

## Cause

Move and resize batch window writes on a tick. That tick was `NSScreen.displayLink`, which AppKit pauses while Control Box is not the frontmost app. Starting a grab over another app (the usual case) created a paused link, so `flush()` never ran.

The Control Box window still moved because that gesture happens while this app is key, so the display link fired. Own-process Accessibility also works without talking to another app.

`SLSMoveWindow` uses this process’s window-server connection. A `0` return on another app’s window is a no-op; the old code treated that as success and skipped `AXPosition`.

## What we changed

Drive the grab tick with a common-mode `Timer` so it keeps firing when another app is focused. The event tap only records pointer and flags — Accessibility and window-server writes run on that timer, not inside the tap callback (that beachballs the app). Use `SLSMoveWindow` only for Control Box windows; other apps always get Accessibility `AXPosition` / `AXSize`. Timeouts on those calls are 0.2 s so Chrome / Electron can answer.

## Do not

Go back to `NSScreen.displayLink` or `CADisplayLink` for this path. Those pause in the background. Do not treat `SLSMoveWindow == 0` as proof that another app’s window moved. Do not call AX from the `CGEvent` tap callback.
