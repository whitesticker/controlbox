# Moving another app's window off a Space

## Symptom

**Move all windows here** (Dock modifier click, 0.1.47) gathered an app's windows onto the clicked display and organized them, but windows sitting on another Space never came along. That is the case people actually want, so the feature was pulled in 0.1.48 and parked on the [roadmap](roadmap.md).

## Why it did nothing

`gatherAndOrganize` was only ever handed `visibleAnywhere + minimized`. Windows on a non-current Space were filtered out before any move, because at the time there was no known way to relocate them.

## What was tried (2026-09-12, macOS Tahoe, three displays)

| Technique | Result |
|---|---|
| `SLSMoveWindowsToManagedSpace(cid, [wid], spaceID)` (SkyLight, what yabai uses) | Returns, no effect on another process's window. `SLSCopySpacesForWindows` still reports the old Space. On current macOS this only works from inside the Dock (yabai's scripting addition, SIP partly off). Not an option. |
| AX `kAXMinimized` true, then false | Window restores onto its **original** Space. |
| AX minimize, then press the Dock's minimized-window tile | This Mac has "Minimize windows into application icon" on, so there is no `AXMinimizedWindowDockItem` to press. Dock restore also switches *you* to the window's Space rather than moving the window. |
| AX `kAXPosition` to a point on **another display** | **Works.** Activity Monitor's window on a non-current Space of the right display (`1604`) landed on the main display's current desktop (`1487`) in one call; `SLSCopySpacesForWindows` confirmed the reassignment. macOS puts a window on the destination display's current Space when its frame crosses onto that display, even from an off-screen Space. |
| AX `kAXPosition` within the **same display** | Stays on its Space. Position is per-display; Space assignment only changes on a display crossing. |

Also seen: AX sometimes returns **zero** windows for an app whose window is on a non-current Space (Calendar here; Apple TV and Messages earlier in [dock-window-preview.md](dock-window-preview.md)). Those windows show in `CGWindowListCopyWindowInfo` but cannot be moved by any public call.

## If this comes back

- Other display → this display: drop the `visibleAnywhere + minimized` filter and let the existing `DockPreviewFocus.setFrame` move off-Space, non-fullscreen windows. One hop.
- Same display, other Space: bounce through a second display whose current Space is a desktop (not fullscreen), then back. Two hops, visible for a frame, impossible on one display.
- Fullscreen windows stay where they are (own Space).
- Expect AX-blind windows; list from CG, skip what AX cannot see.
- Do not use `SLSMoveWindowsToManagedSpace`, and do not inject into the Dock.
