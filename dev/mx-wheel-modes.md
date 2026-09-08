# MX wheel modes

Implemented 2026-09-07. Each MX profile has one mode for the thumb wheel.
The main wheel remains native vertical scroll and is not configurable. The UI
no longer exposes separate thumb Left / Right mappings.

## Modes

- Thumb wheel defaults to **Horizontal Scroll**.
- **Switch Between Tabs** repeats `⌘⇧[` / `⌘⇧]` from raw wheel deltas. One MX
  ratchet is one tab; it does not accelerate. This is separate from the
  discrete Previous / Next Tab `ControlAction` used by buttons and gestures.
- **Volume** emits repeated media-volume events and accelerates during a burst.
- **Zoom In/Out** emits `⌘=` / `⌘−` at a fixed rate. There is no public API for
  injecting a pinch/magnification gesture into another app; Universal Access
  Zoom magnifies the whole display and is not app-content zoom.
- **Switch Between Desktops** uses the existing Dock swipe event path and is
  rate-limited so Space animations do not stack.
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
thumb directions as buttons. Thumb **scroll** modes use the same Pointer &
Scroll wheel speed as the main wheel.

Old profiles with paired thumb-direction bindings migrate tabs, volume,
desktops, and apps when the new optional mode field is absent.
