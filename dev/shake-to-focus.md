# Shake to focus

## Symptom

There is no Aero Shake on the Mac. Grabbing a window and shaking it does nothing to the rest of the desk.

## What we changed

**Shake to focus** and **Dock click** (Switch to Space, When already in front) live on the Window Management pane. Off until each toggle is on.

Shake a window left and right (native title bar, or while Move is held) to minimize every other visible window. Shake again to restore the ones this gesture hid.

Dock click is one plain click, state-driven, layered on the native click (no double-click, no timer):

- App was frontmost at mouse-down with a visible window → **When already in front**: Minimize window / Hide app / nothing. Not fullscreen.
- No window on any current Space, at least one not minimized → **Switch to Space**: DockSwipe slide of that window’s display (this or another) to its Space. The window does not move. Other-monitor switches hop the pointer to the nearest edge of that display, then put it back as soon as the slide starts. Fullscreen is a Space; never exit it.
- Everything else (visible but not in front, all minimized, hidden with ⌘H, any modifier held) → native. Control Box does nothing.

**Move all windows here** (modifier click, gather that app onto this display) was removed in 0.1.48: it could not reach windows on other Spaces. See [move-windows-across-spaces.md](move-windows-across-spaces.md).

Read the frontmost app at **mouse-down**. Dock activates the clicked app on the same click, so a mouse-up read makes every click look “already in front”. **Ignored apps** skip Dock click. Native Dock clicks still fire (listen-only).

Auto-hide: do not treat the tilesize strip or leftover AX frames as a clickable icon. Hidden Dock chrome is off-screen (full-display layer-20 window). Minimize only when that bar is on-screen **and** the click hits an AX tile (`requireHit`, no 140 px nearest fallback). Close-but-not-touching while the bar is still in must not minimize.

**This display** / **All displays** is Shake only. Physical monitors, not Spaces.

The listen-only tap only stashes mouse down / drag / up. Accessibility hit-testing and minimize run on the main queue. Pointer travel of ~16pt is enough to start watching a native shake so a coalesced down+drag is not dropped.

Dock Previews hide while a shake drag is being watched, same as a Window Management hold.

## Do not

Call Accessibility from the `CGEvent` tap callback. Do not hide the shaken window. Do not pin Dock auto-hide. Do not treat a second shake as “hide again” while a restore set is still live — restore first.
