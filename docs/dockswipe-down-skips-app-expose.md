# Downward DockSwipe does not open App Exposé

## Symptom

At 1000 DPI, Spaces (left/right) and live Mission Control (up) work. Hold + swipe **down** for App Exposé does nothing.

## Cause

Up and down both went through the same live vertical DockSwipe session (`field 124` offset sign). On this Mac (darwin 25.5 / macOS 26.5) an upward dock-swipe previews Mission Control. A downward dock-swipe does not open App Exposé.

App Exposé still works as a discrete system action: Core Dock `com.apple.expose.front.awake`, symbolic hotkey 33, or Control-Down.

## What this is not

Not “switch Mission Control back to a hotkey.” Live follow for up / left / right stays. App Exposé has no useful live scrub on this OS.

## What we changed

When the locked axis is vertical and accumulated `y >= 40` (down), cancel any live DockSwipe and fire `.appExpose` once per hold.

## Do not

Assume DockSwipe axis 2 negative offset is App Exposé on every macOS version. Re-check before replacing the discrete trigger.
