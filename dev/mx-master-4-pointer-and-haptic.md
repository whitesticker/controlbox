# MX Master 4: pointer, DPI, and haptic swipes

Working model as of 2026-08-26. Active test device is **MX Master 4 over Bluetooth LE** (product `0xB042`). 3S and 4 can stay attached (isolated readers).

Hardware layout is in [mx-master-4-ble-haptic.md](mx-master-4-ble-haptic.md). This file is how Control Box maps that hardware to cursor speed and window gestures.

## What works

| Input | Behavior |
|---|---|
| Laser pointer | Cursor. **Pointer speed** slider + DPI compensation. |
| Wheel / thumb wheel | Main wheel always scrolls vertically. Free Spin / Ratchet and SmartShift sensitivity are on Calibration (`0x2111`). Thumb wheel has one per-profile mode, default Horizontal Scroll; travel uses Calibration thumb-wheel sensitivity. Smooth scrolling + one wheel speed slider for native mouse scroll. |
| Haptic pad tap | The Gestures **Click** action (window preset: Mission Control). |
| Haptic pad hold 100ms + move | Hold-to-swipe. Left/right and up are live DockSwipe. Down is discrete App Exposé. |
| Gesture button tap | Same Gestures **Click** as the pad (window preset). |
| Gesture button hold 100ms + move | Hold-to-swipe from HID++ `rawXYEvent` only. No pointer pin. |

Both default to Gestures. Other controls are offered only when their live Reprog descriptor advertises divertable raw XY. See [haptic-vs-back-gesture.md](haptic-vs-back-gesture.md).

## Pointer speed plus DPI

Do not fold DPI into pointer speed. The user wants them independent.

| Control | What it changes | What it must not change |
|---|---|---|
| **DPI** | Sensor resolution. Higher = smoother tracking, more HID counts per inch. | Cursor feel. Haptic swipe feel. |
| **Pointer speed** | On-screen cursor only. | Hold-to-swipe Spaces / Mission Control / App Exposé. |

Hold-to-swipe uses native HID travel at 1000 DPI. Higher sensor DPI is divided out (`1000 / dpi`) so the same physical pad move stays the same. There is no gesture-speed slider.

There is **no** separate Acceleration slider. macOS tracking speed is how pointer speed is implemented. There is **no** Button gesture speed slider (that was for the parked click-as-gesture path).

Pointer and wheel speed live under Mac → Pointer & Scroll (Control Box intercepts every USB/Bluetooth mouse). DPI is written to the mouse from Calibration.

## Default MX profile

- Haptic → Gestures, preset **Window navigation**
- Gesture button (CID `0x00C3`) → Gestures, preset **Window navigation**
- Back → browser back
- Forward → browser forward
- Wheel / thumb directions → Scroll (native)
- Summary: “Haptic button is the pad. Gesture button is the thumb button. Both default to Gestures.”

Haptic / Gesture presets:

| Preset | Click | Up | Down | Left | Right |
|---|---|---|---|---|---|
| Window navigation | Mission Control | Mission Control (live) | App Exposé (discrete) | Space left (live) | Space right (live) |
| Media controls | Play/pause | Volume up (live) | Volume down (live) | Previous track | Next track |
| App navigation | Switch app | Mission Control (live) | App Exposé | Next app | Previous app |
| Custom | Whatever is assigned to click / four directions | | | | |

Profiles offer **Gestures** on **Gesture-capable controls** (live Reprog raw XY). Defaults are Haptic and Gesture. Left/right stay native.

## Pointer path

`MappingProfile.pointerSpeedFactor` uses a steep low-end curve so small slider values are actually slow, then divides out sensor DPI (`1000 / dpi`) so raising DPI does not also make the cursor faster.

That factor is applied in two places:

1. HID++ feature `0x2205` (8.8 scale) in `LogitechMouseReader.sendSensorSettingsIfNeeded`.
2. OS properties `HIDPointerResolution` (lower = faster) and `HIDPointerAcceleration` / mouse acceleration in `PointerHIDSettings.swift`, including matching `IOHIDServiceClient`s.

50% at 1000 DPI is 1×. Do not clamp resolution to LinearMouse’s 1995 ceiling; that left high DPI too fast.

## Haptic path

While the haptic pad is held (HID button 7 / `0x40` on report `0x02`, plus the shared click-probe other-mouse events):

1. Freeze the cursor (`CGAssociateMouseAndMouseCursorPosition(0)`) and swallow mouse-move and haptic other-mouse events so pointer motion does not cancel DockSwipe.
2. Accumulate 12-bit X then 12-bit Y from that same report (`handleNativeMouseReport`) into one hid delta.
3. Scale each sample with `MappingProfile.gestureSpeedFactor(dpi)` — `1000 / dpi` only.
4. Publish `gestureOwner = .mxHaptic`, `gestureActive`, `gestureX` / `gestureY` on the control frame.
5. `ControlEngine.processGesture` runs `HoldGesture` when the owner is haptic and that control is a Gestures owner.

HID++ diverted raw XY (`handleRawXY`) uses the same accumulator. Divert `0x01A0` once at attach; do not re-divert from the poll loop. Drop the first raw-XY sample on the haptic pad (OpenLogi contact jump). Native report `0x02` feeds that same hid delta only while the live owner is the haptic button.

Without the DPI term, 2000 DPI felt like twice the swipe of 1000 DPI. At 1000 DPI the haptic bar felt right; other DPI values now match that physical travel. See [haptic-swipe-scales-with-dpi.md](haptic-swipe-scales-with-dpi.md).

## Hold-to-swipe module

`HoldGesture` in ControlBoxCore is the only place that decides tap vs swipe, axis, Spaces, Mission Control, App Exposé, media skip, and volume.

The MX reader captures press + XY. Only the haptic pad pins the cursor.

### Pipeline

Haptic button:

```
report 0x02 (bit 0x40 + 12-bit XY) and HID++ rawXYEvent
        → LogitechMouseReader (pin cursor, scale XY)
        → ControlFrameBuilder (owner / active / X / Y)
        → ControlEngine.processGesture
        → HoldGesture (arm, axis, live DockSwipe or discrete action)
```

Gesture button (OpenLogi):

```
HID++ diverted-buttons + rawXYEvent (CID 0x00C3, flags 0x33)
        → LogitechMouseReader (no pin; swallow mouseMoved for 80ms after firmware XY)
        → ControlFrameBuilder
        → ControlEngine.processGesture
        → HoldGesture
```

`setGestureOwners` maps each owner to its CID. Dedicated `0x00C3` always diverts; raw XY is only while `.mxSide` owns Gestures. The reader will not start a non-haptic hold from a CG other-mouse event.

## Tap vs swipe

A short press is a **tap** (the click action, default Mission Control). Hold + move is a **swipe**.

Both layers wait **100ms** after press before a swipe can start:

- `HoldGesture.armDelay` is 0.10 s. No axis lock or DockSwipe until then.
- `finishGesture` classifies the release as a tap if the hold was under 100ms, even if the pad wobbled.

After 100ms, axis lock is: mostly vertical if `|y| >= 6` and `|y| >= |x|`; otherwise horizontal once travel ≥ 10.

Horizontal discrete skip (media prev/next) fires at `|x| >= 40`. App Exposé fires at `y >= 40`. Volume steps every 36 units of `-y`.

See [haptic-tap-starts-swipe.md](haptic-tap-starts-swipe.md).

## Live window gestures

Window navigation preset (haptic pad):

| Move | Action | How it runs |
|---|---|---|
| Tap | Mission Control | Discrete system action on release |
| Hold + left / right | Spaces / desktop switch | Live DockSwipe, horizontal |
| Hold + up | Mission Control | Live DockSwipe, vertical (`-y`) |
| Hold + down | App Exposé | Discrete Core Dock / Ctrl-Down once travel is clearly down (`y >= 40`) |

Media controls preset: tap is play/pause, up/down is live volume, left/right is previous/next track (one skip per hold, same 100ms arm + travel threshold). Not DockSwipe. See [media-gesture-skip-dead.md](media-gesture-skip-dead.md).

Live follow posts the Mac Mouse Fix / [dockswipe](https://github.com/oomol-lab/dockswipe) field recipe: companion type-29 marker + type-30 dock-control, subtype 23, axis 1 horizontal / 2 vertical. Post **e30 then e29**. Field `124` is absolute progress. Do **not** set `CGEvent.type` to 30; that made vertical look like magnify.

Progress is **absolute**, not incremental. A dropped or reset sample that looks like a teleport toward the origin is ignored so Spaces does not snap backward. See [dockswipe-progress-snapback.md](dockswipe-progress-snapback.md).

Horizontal and vertical live spans are the same (`screen width`) so one haptic-speed slider maps both. A ~48 px Mission Control span made up/down finish in a flick.

There is **no** 180 ms haptic-release debounce. Each full Space locks in during the hold (macOS only commits one desktop per DockSwipe session); release rounds the leftover page. See [dockswipe-commit-nearest.md](dockswipe-commit-nearest.md).

Downward DockSwipe does not open App Exposé on this Mac (darwin 25.5 / macOS 26.5). That direction fires the system App Exposé action instead. See [dockswipe-down-skips-app-expose.md](dockswipe-down-skips-app-expose.md).

## What not to do

- Do not apply pointer speed or OS tracking pixels to haptic X/Y.
- Do not omit the DPI term from haptic scaling. 50% “1× HID” without `1000 / dpi` is only true at 1000 DPI.
- Do not open or seize the standard mouse collection (`0x01` / `0x02`) just to watch buttons. Parse left / right / wheel from report `0x02` on the HID++ device; share one `CGEvent` tap across readers ([mx4-clicks-missing-in-calibration.md](mx4-clicks-missing-in-calibration.md)).
- Divert MX4 **gesture button** `0x00C3` with `0x33` when it owns Gestures (OpenLogi raw XY). Do not pin the pointer. The **haptic button** `0x01A0` keeps `0x33` plus pin. Do not treat `0x00C3` as Side. See [mx4-gesture-button-freezes-pointer.md](mx4-gesture-button-freezes-pointer.md).
- Do not send Reprog persist or force-raw-XY. Clear divert with `0x22`.
- Do not call `IOBluetoothDevice.pairedDevices()`.
- Do not treat Bolt receiver `C548` as this mouse.
- Do not switch Mission Control back to a hotkey-only path. Live follow is intentional.
- Do not add a user-facing Acceleration slider.
- Do not `DispatchQueue.main.async` every BLE mouse report `0x02`; that floods the main thread. HID++ report `0x11` can hop to main; `0x02` is handled on the callback thread.
- Do not default Gestures onto Back / Forward / middle. Laser XY is not the pad; capability-gated ownership is allowed when firmware advertises raw XY. See [haptic-vs-back-gesture.md](haptic-vs-back-gesture.md).
- Do not re-divert the haptic CID from `setGestureOwners` on every poll. Attach-time `divertKnownButtons` is enough; a flickering eligible set undiverts the pad while Back/Forward stay up.
- Do not HID++-divert `0x0050` / `0x0051` / `0x0052` to invent a second pad.

## Code map

| File | Role |
|---|---|
| `ControlBox/Devices/Logitech/Mouse/LogitechMouseReader.swift` | HID++, report `0x02` buttons + wheel + haptic XY, shared click probe, freeze cursor, 100ms tap classify. Gesture owners come from each control’s raw-XY capability; left/right stay native. |
| `ControlBox/Mac/PointerScroll/PointerHIDSettings.swift` | OS pointer resolution + acceleration from pointer slider + DPI |
| `ControlBox/Devices/UI/ProfilesPane.swift` | Gestures picker on Gesture-capable controls. |
| `ControlBox/Devices/Logitech/Mouse/MXMasterCalibrationView.swift` | Calibration: live clicks. DPI lives in Mouse Settings. |
| `ControlBox/DualSenseMonitor.swift` | Pushes sliders + DPI into the reader. Sanitizes saved profiles on load. |
| `ControlBox/ControlFrameBuilder.swift` | `gestureOwner` / `gestureActive` / `gestureX` / `gestureY` from the MX snapshot |
| `Packages/ControlBoxCore/.../MappingProfile.swift` | `pointerSpeedFactor`, `gestureSpeedFactor`, per-control `mxGestureOwners` |
| `Packages/ControlBoxCore/.../HoldGesture.swift` | 100ms arm, axis lock, live Spaces/MC, discrete App Exposé / media skip, volume |
| `Packages/ControlBoxCore/.../ControlEngine.swift` | Starts `HoldGesture` for any Gestures owner |
| `Packages/ControlBoxCore/.../DockSwipe.swift` | Absolute dock-swipe events |
| `Packages/ControlBoxCore/.../SystemNavigation.swift` | Core Dock / symbolic hotkeys for MC and App Exposé |
| `Packages/ControlBoxCore/.../GestureSet.swift` | Presets and click / up / down / left / right slots |

## Related

- [mx-master-4-ble-haptic.md](mx-master-4-ble-haptic.md)
- [haptic-vs-back-gesture.md](haptic-vs-back-gesture.md)
- [gesture-owner-haptic-only.md](gesture-owner-haptic-only.md)
- [hidpp-divert-steals-pointer.md](hidpp-divert-steals-pointer.md)
- [extra-buttons-missing-in-calibration.md](extra-buttons-missing-in-calibration.md)
- [mx4-clicks-missing-in-calibration.md](mx4-clicks-missing-in-calibration.md)
- [mx4-gesture-button-freezes-pointer.md](mx4-gesture-button-freezes-pointer.md)
- [focused-host-still-injects.md](focused-host-still-injects.md)
