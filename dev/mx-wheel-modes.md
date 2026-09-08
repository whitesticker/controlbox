# MX wheel modes

Implemented 2026-09-07. Each MX profile has one mode for the thumb wheel.
The main wheel remains native vertical scroll and is not configurable. The UI
no longer exposes separate thumb Left / Right mappings.

## Modes

- Thumb wheel defaults to **Horizontal Scroll**.
- **Navigate Between Tabs** uses OpenLogi’s Control-Tab / Control-Shift-Tab
  (Safari, Chrome, and Firefox). Diverted `0x2150` increments accumulate to
  OpenLogi’s sensitivity threshold at 1.5× (fewer increments, ~133 ms cooldown).
  Command-Shift-bracket is Safari/Chrome-only and does nothing in Firefox.
  This is separate from the discrete Previous / Next Tab `ControlAction` used
  by buttons and gestures (same Control-Tab chord).
- **Volume** uses `SystemVolume.nudge`, which always shows the volume HUD
  (same HUD as the haptic / touchpad volume gesture). DualSense, Siri Remote,
  and mapped Volume Up / Down go through that same wrapper.
- **Zoom In/Out** emits `⌘=` / `⌘−` at a fixed rate. There is no public API for
  injecting a pinch/magnification gesture into another app; Universal Access
  Zoom magnifies the whole display and is not app-content zoom.
- **Switch Between Desktops** is a live DockSwipe session like the haptic
  hold-to-swipe, not one discrete Space per notch. A quarter-turn of the
  thumb wheel is one desktop at 1× Calibration sensitivity (`getThumbwheelInfo`
  diverted resolution / 4). Releasing the wheel (idle ~140 ms) commits the
  nearest Space.
- **Switch Between Apps** drives the existing Command-Tab session.
- **None** consumes that wheel.

“Switch Between Pages” is deliberately omitted. Logi Options+ uses the native
two-finger page-swipe concept (browser/Finder history), but public `CGEvent`
does not expose a system-wide swipe event. `⌘[` / `⌘]` would only be a
shortcut approximation.

## Input paths

The main wheel stays as native vertical `scrollWheel` events through
`MouseScrollTap` for speed, smoothness, and direction only. That tap is for
every USB/Bluetooth mouse, not MX only. Trackpad and Magic Mouse gestures
pass through.

The thumb wheel stays diverted through HID++ `0x2150`. Its accumulated delta
goes directly to `MXWheelActionEngine`; `ControlEngine` no longer interprets
thumb directions as buttons. Pointer & Scroll **Smooth scrolling** (default
on) runs OpenLogi’s 100 ms cubic interpolator on **every** thumb mode, not
only scroll: diverted increments are eased, then mapped to the live mode.
Scroll modes post pixel-continuous events with Began/Changed/Ended phases
(10 points per native tick, line = pixels/10, no forced ±1). Volume follows
the eased travel analog-style. Tabs, zoom, and apps fire from fractional
distance with no extra cooldown. Desktops keep live DockSwipe, filled in
between HID++ packets. Smooth **off** keeps OpenLogi line ticks for scroll
and the discrete increment threshold + cooldown for the other modes.
`getThumbwheelInfo` native/diverted still scales scroll. The Pointer & Scroll
tap skips injected events. Calibration **Thumb wheel** sensitivity is 14 = 1×.
Pointer & Scroll **Wheel speed** does not scale thumb.

**Invert thumb wheel** is a Calibration toggle on this mouse. HID++ `0x2150`
`setThumbwheelReporting` byte 1 (same packet as divert). OpenLogi uses that
bit to normalise `default_dir` polarity; Control Box exposes it as the user
invert. Firmware RAM is volatile, so it is stored on Default and re-applied
after attach. Pointer & Scroll Natural / Standard still only affects injected
thumb **scroll** sign. OpenLogi’s *Invert scroll direction* is a different
write: HiResWheel `0x2121` on the main wheel.

Old profiles with paired thumb-direction bindings migrate tabs, volume,
desktops, and apps when the new optional mode field is absent.

Main-wheel Free Spin / Ratchet is firmware SmartShift on Calibration.
See [mx-smartshift.md](mx-smartshift.md).
