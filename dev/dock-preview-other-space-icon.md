# Other-Space Dock preview is only the app icon

## Symptom

On the desk Mac (several displays), a window on another Space shows as the app icon in Dock Previews. The same 0.1.32 build on the MacBook stills that window.

## Cause

ScreenCaptureKit’s `SCShareableContent` list often omits off-screen windows on a multi-display Mac, even with `onScreenWindowsOnly: false`. Capture only stills IDs that appear in that list, so the card has no image and falls back to the icon. The MacBook’s single display still includes those windows.

## What we changed

Keep ScreenCaptureKit as the primary still. If that list has no window (or capture throws), take one `CGWindowListCreateImage` of that window ID. Do not call it on a timer or as the first path. Also match AX frames to CG in both Cocoa and Quartz so other-Space cards keep a real window ID.

## Do not

Replace ScreenCaptureKit with `CGWindowListCreateImage` for on-screen stills. Do not capture from the `CGEventTap` callback.
