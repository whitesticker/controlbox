# Shake to focus

## Symptom

There is no Aero Shake on the Mac. Grabbing a window and shaking it does nothing to the rest of the desk.

## What we changed

**Shake to focus** and **Minimize on Dock click** live on the Window Management pane. Off until each toggle is on.

Shake a window left and right (native title bar, or while Move is held) to minimize every other visible window. Shake again to restore the ones this gesture hid.

If an app is already front and has a visible window, click its Dock icon to minimize that window. Native Dock clicks still fire (listen-only). No display picker on Dock click.

**This display** / **All displays** is Shake only. Physical monitors, not Spaces.

The listen-only tap only stashes mouse down / drag / up. Accessibility hit-testing and minimize run on the main queue. Pointer travel of ~16pt is enough to start watching a native shake so a coalesced down+drag is not dropped.

Dock Previews hide while a shake drag is being watched, same as a Window Management hold.

## Do not

Call Accessibility from the `CGEvent` tap callback. Do not hide the shaken window. Do not pin Dock auto-hide. Do not treat a second shake as “hide again” while a restore set is still live — restore first.
