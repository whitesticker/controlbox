# Dock hover does not show window thumbnails

## Symptom

Pointing at a Dock icon only shows the app name. There is no way to see every open window and click the one you want.

## Cause

Stock macOS Dock has no hover thumbnail strip. App Exposé is a full-screen mode, not a popover. Window Grab already lists on-screen windows, but that list skips minimized and other-Space windows and is private to the grab controller.

A shell spike on this Mac (Tahoe / darwin 25.5) could see Dock pid `690`. The terminal is not Accessibility-trusted, so Dock AX children were empty. Control Box already has that grant.

Auto-hide Dock: the pointer can stop on the reveal strip before AX icon frames exist, so there is no further `mouseMoved`. Retry while the pointer stays in the strip. Hit-test AX frames in Quartz (`CGEvent.location`), same as Sticky Targeting; convert to Cocoa only to place the panel.

Do not treat the tilesize strip as the auto-hide trigger. Stock reveal is the last few pixels of the display edge. The tilesize strip plus 16 px padding is ~100 px tall when the Dock is hidden (`visibleFrame` has no inset), so “close to the bottom but not touching” used to arm a preview and pick the nearest tile within 140 px. Arm only on the 3 px edge hit; keep the fat strip after that so icons still work once the bar is out. Leave the fat strip and the next hover must hit the edge again. Minimize on Dock click: auto-hide AX tiles stay full-size while the bar is in, so frame size is not a reveal signal. Hidden chrome is off-screen. Minimize only when the Dock bar window is on-screen and the click hits a tile.

Do not flip `CoreDockSetAutoHideEnabled` to keep the Dock out. That changes `visibleFrame` and every tiled / maximized window on that display jumps. Do not try to pin or delay auto-hide while the pointer is on the preview — leave the Dock’s hide behavior alone. Place the panel above the icon (from the AX frame) so native Dock clicks still work. Do not show a card for an app with no windows. While the pointer is on the panel, do not retarget a neighboring icon.

Three displays: macOS keeps the Dock on one screen and can move it to the display you approach. Do not assume `NSScreen.main` or a single strip at the origin. Build a strip per `NSScreen` from that screen’s `visibleFrame` vs `frame` inset, Dock `orientation`, and `tilesize`. Place the panel from the hovered icon’s AX frame on that screen — never a hardcoded point or a 1920×1080 assumption.

There is no public Dock-hover webhook. Closest is an `AXObserver` on `com.apple.dock` (`kAXSelectedChildrenChangedNotification` only) plus the listen-only mouse tap. Do not subscribe to `kAXLayoutChangedNotification` — Dock magnification fires it continuously and walks AX on every ping. Do not sample the pointer on a timer.

Hover CPU: a mouse move used to run the tap plus two `NSEvent` monitors, each walking the whole Dock AX tree and then `axMatch` per window. Stay on one icon and that is tens of AX calls per second. Coalesce to one resolve per run-loop turn. Hit-test a cached tile list; refresh that list at most ~8 Hz. One AX window list per pid when revealing. ScreenCaptureKit stills are capped (6), cached, and not re-fetched for the same window for a few seconds. Do not rebuild the SwiftUI hosting view on every move.

The Dock app-name tooltip has no public hide API. The pane can clear pinned-tile `file-label` strings (after snapshotting them) so the native name is empty; turning the toggle back on restores the copy. Do not `killall Dock`. Running-only icons may still show a name. Cover leftover labels with the panel if needed. Help-window level.

Keep-alive is the panel plus a thin corridor from the current icon to the panel. Do not union the whole Dock strip. That swallows neighboring icons and leaves the previous preview up.

Do not sample the pointer on a timer. A listen-only session `CGEvent` tap fires on real mouse moves (including over the Dock). `NSEvent` monitors stay as a backup. One short retry is allowed only after a miss while the pointer is already in the Dock strip (auto-hide frames not up yet). Auto-hide: that strip is the 3 px reveal edge until the hover is armed; then the tilesize strip.

## What we changed

New **Dock Previews** Mac pane, off until the toggle is on. Catalog lives on the app delegate so hover still works after the window closes.

- Listen-only mouse tap + local `NSEvent` monitor (panel) + Dock selected-child `AXObserver`. Moves are coalesced. Tile frames are cached. No pointer sampling.
- Panel eases in from the Dock and slides between icons; fade out on dismiss. Do not snap `setFrame` with animations forced off.
- One strip per display from that screen’s inset / `tilesize`; panel from the icon AX frame on that screen.
- Auto-hide: arm only on a 3 px screen-edge hit (stock reveal). The tilesize strip is for staying on icons after that, not for the first hover.
- Liquid Glass (`NSGlassEffectView`) on macOS 26; `NSVisualEffectView` `.hudWindow` below that. No SwiftUI material on top of the glass.
- Place the panel above the icon from its AX frame. Help-window level. Do not pin Dock auto-hide.
- Identify the icon by enumerating AX children of `com.apple.dock`, not hit-test.
- List windows from Accessibility (current Space + minimized) and add off-screen CG windows that look like real frames (other **Spaces**, not other displays). A window on another physical display of the current Space is on-screen and must stay. Drop title-bar strips, 500×500 placeholders, parked frames, popovers / sheets, nested chrome, and non-minimized surfaces smaller than 35% of that app’s largest window on the same display. Calendar’s event inspector sits *beside* the host, not inside it — a nested-only filter is not enough. One real window is one card. Animation duration follows Dock `autohide-time-modifier` (stock 0.25s). Chrome is always the flat panel. Optional **Show Dock icon names** writes pinned `file-label` values (snapshot / restore). Do not restart Dock.
- Still thumbnails via ScreenCaptureKit only while the panel is up. If an other-Space window is missing from that list (multi-display Macs), take one `CGWindowListCreateImage` of that window ID. Titles and the app icon still work if Screen Recording is off.
- Card height is fixed (slider 80–200%, default 130%). Width follows that window’s aspect so a tall frame is not cropped. Thumbnail uses fit, not fill.
- Click a card: unminimize if needed, AX raise, activate the app.
- Hover a card on this Space: a tight Liquid Glass HUD — red close, yellow minimize (or green restore when minimized), purple quit. No zoom. Other-Space cards always show quit (close / minimize need this Space). Quit calls `NSRunningApplication.terminate()` (graceful, not force).
- Place the panel above the revealed Dock, not the screen edge. If auto-hide is instant and AX still has a collapsed tile, use tilesize clearance and refresh the icon frame after the hover delay.
- Hide the panel while a Dock right-click menu is up. Right-click dismisses and stays down until that menu is gone. Do not cover the native menu (our panel is above menu level).
- Hide the panel while Window Grab is busy, Shake to focus is watching a drag, or a Window Grab modifier chord is held.
- Native Dock left-click is not intercepted. The panel sits above the icons.

Screen Recording is a **separate** grant from System Audio Recording. Do not fold it into `screenCaptureTrusted` or `allPermissionsGranted`.

## Do not

- Replace or seize the Dock.
- Run Accessibility or capture inside a `CGEventTap` callback.
- Use `CGWindowListCreateImage` as the primary path. Fallback for an other-Space window that ScreenCaptureKit omitted is allowed.
- Call `CGRequestScreenCaptureAccess()` from Sound.
- Gate the pane on an MX Master.
- Poll captures when the pointer is not on a Dock icon.
- Walk Dock AX or call `SCShareableContent` on every `mouseMoved`.
- Observe Dock `kAXLayoutChangedNotification` (magnification storm).
- Flip Dock autohide on/off to keep the bar visible (resizes windows).
- `killall Dock` to apply a `file-label` change.
- Show a “No open windows” card. Native Dock is enough.
- Treat nested inspectors, palettes, or mini widgets as their own cards. Also do not keep sibling chrome just because it is `AXStandardWindow` or sits beside the host.
- Keep a nested-only prune. 0.1.31 shipped that and Calendar still showed inspector + mini month cards.
- Drop a real second window that is ≥ 35% of the largest on that display.
- Treat every off-screen CG window as minimized.
- Show the preview over a Dock right-click menu.

Shipped 0.1.31–0.1.33. Related: [dock-preview-lists-window-chrome.md](dock-preview-lists-window-chrome.md), [dock-preview-other-space-icon.md](dock-preview-other-space-icon.md).
