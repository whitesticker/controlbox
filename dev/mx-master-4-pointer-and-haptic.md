# MX Master 4: pointer, DPI, and haptic swipes

Working model as of 2026-08-26. Active test device is **MX Master 4 over Bluetooth LE** (product `0xB042`). 3S and 4 can stay attached (isolated readers).

Hardware layout is in [mx-master-4-ble-haptic.md](mx-master-4-ble-haptic.md). This file is how Control Box maps that hardware to cursor speed and window gestures.

## What works

| Input | Behavior |
|---|---|
| Laser pointer | Cursor. **Pointer speed** slider + DPI compensation. |
| Wheel / thumb wheel | Native scroll unless that direction is remapped (`mxWheelUp/Down`, `mxThumbLeft/Right`). `.scroll` or a missing binding keeps native. Smooth scrolling + separate wheel / thumb speed sliders. |
| Haptic pad tap | The Gestures **Click** action (window preset: Mission Control). |
| Haptic pad hold 100ms + move | Hold-to-swipe. Left/right and up are live DockSwipe. Down is discrete App Exposé. |

**Gestures is haptic-pad only.** Click-as-gesture on Back / Forward / etc. is parked. See [haptic-vs-back-gesture.md](haptic-vs-back-gesture.md).

## Two sliders, plus DPI

Do not merge these. The user wants them independent.

| Control | What it changes | What it must not change |
|---|---|---|
| **DPI** | Sensor resolution. Higher = smoother tracking, more HID counts per inch. | Cursor feel. Haptic swipe feel. |
| **Pointer speed** | On-screen cursor only. | Hold-to-swipe Spaces / Mission Control / App Exposé. |
| **Haptic gesture speed** | Hold-to-swipe only. 50% = 1× native HID travel at 1000 DPI. 0% is a comfortable Spaces swipe on this Mac. | Cursor. |

There is **no** separate Acceleration slider. macOS tracking speed is how pointer speed is implemented. There is **no** Button gesture speed slider (that was for the parked click-as-gesture path).

Settings copy lives under Profiles → Pointer & scroll.

## Default MX profile

- Haptic → Gestures, preset **Window navigation**
- Back → browser back
- Forward → browser forward
- Side → Mission Control
- Wheel / thumb directions → Scroll (native)
- Summary: “Haptic pad is Gestures. Back and Forward are browser buttons. Side is Mission Control.”

Haptic presets:

| Preset | Click | Up | Down | Left | Right |
|---|---|---|---|---|---|
| Window navigation | Mission Control | Mission Control (live) | App Exposé (discrete) | Space left (live) | Space right (live) |
| Media controls | Play/pause | Volume up (live) | Volume down (live) | Previous track | Next track |
| App navigation | Switch app | Mission Control (live) | App Exposé | Next app | Previous app |
| Custom | Whatever is assigned to click / four directions | | | | |

Profiles only offer **Gestures** on the Haptic row. Other MX buttons use the normal action picker.

Saved profiles that still have Gestures on a non-haptic button are rewritten on load (`restrictGesturesToHapticPad`): Back → browser back, Forward → browser forward, others → none.

## Pointer path

`MappingProfile.pointerSpeedFactor` uses a steep low-end curve so small slider values are actually slow, then divides out sensor DPI (`1000 / dpi`) so raising DPI does not also make the cursor faster.

That factor is applied in two places:

1. HID++ feature `0x2205` (8.8 scale) in `LogitechMXMasterReader.sendSensorSettingsIfNeeded`.
2. OS properties `HIDPointerResolution` (lower = faster) and `HIDPointerAcceleration` / mouse acceleration in `PointerHIDSettings.swift`, including matching `IOHIDServiceClient`s.

50% at 1000 DPI is 1×. Do not clamp resolution to LinearMouse’s 1995 ceiling; that left high DPI too fast.

## Haptic path

While the haptic pad is held (HID button 7 / `0x40` on report `0x02`):

1. Freeze the cursor (`CGAssociateMouseAndMouseCursorPosition(0)`) and swallow mouse-move events so pointer motion does not cancel DockSwipe.
2. Accumulate 12-bit X then 12-bit Y from that same report (`handleNativeMouseReport`).
3. Scale each sample with `MappingProfile.gestureSpeedFactor(slider, dpi)` — slider curve **and** `1000 / dpi`.
4. Publish `gestureOwner = .mxHaptic`, `gestureActive`, `gestureX` / `gestureY` on the control frame.
5. `ControlEngine.processGesture` runs `HoldGesture` only when the owner is haptic **and** that binding is Gestures.

HID++ diverted raw XY (`handleRawXY`) uses the same scaler when that pipe exists. HID++ is not required for BLE press or swipe.

HID usages `0x30` / `0x31` also accumulate only while the live owner is haptic, so a second XY stream cannot mix in.

Without the DPI term, 2000 DPI felt like twice the swipe of 1000 DPI. At 1000 DPI the haptic bar felt right; other DPI values now match that physical travel. See [haptic-swipe-scales-with-dpi.md](haptic-swipe-scales-with-dpi.md).

## Hold-to-swipe module

`HoldGesture` in ControlBoxCore is the only place that decides tap vs swipe, axis, Spaces, Mission Control, App Exposé, media skip, and volume.

The MX reader only captures pad down + raw XY and a pinned cursor. It does not know about media vs window navigation.

### Pipeline

```
report 0x02 (bit 0x40 + 12-bit XY)
        → LogitechMXMasterReader (pin cursor, scale XY)
        → ControlFrameBuilder (owner / active / X / Y)
        → ControlEngine.processGesture
        → HoldGesture (arm, axis, live DockSwipe or discrete action)
```

`setGestureOwners` intersects the profile’s owners with `{.mxHaptic}`. The reader will not start a session for Back or any other click.

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
- Do not divert MX4 Side `0x00C3` with gesture flags `0x33`. That CID is a click on MX4 (`0x03`). On 3S the same CID is the gesture button.
- Do not send Reprog persist or force-raw-XY. Clear divert with `0x22`.
- Do not call `IOBluetoothDevice.pairedDevices()`.
- Do not treat Bolt receiver `C548` as this mouse.
- Do not switch Mission Control back to a hotkey-only path. Live follow is intentional.
- Do not add a user-facing Acceleration slider.
- Do not `DispatchQueue.main.async` every BLE mouse report `0x02`; that floods the main thread. HID++ report `0x11` can hop to main; `0x02` is handled on the callback thread.
- Do not put Gestures back on Back / Forward / left / right / middle. Laser XY is not the pad. See [haptic-vs-back-gesture.md](haptic-vs-back-gesture.md).
- Do not HID++-divert `0x0050` / `0x0051` / `0x0052` to invent a second pad.

## Code map

| File | Role |
|---|---|
| `ControlBox/LogitechMXMasterReader.swift` | HID++, report `0x02` buttons + wheel + haptic XY, shared click probe, freeze cursor, 100ms tap classify. Gesture owners clamped to haptic. |
| `ControlBox/PointerHIDSettings.swift` | OS pointer resolution + acceleration from pointer slider + DPI |
| `ControlBox/ProfilesPane.swift` | DPI, Pointer speed, Haptic gesture speed. Gestures picker only on Haptic. |
| `ControlBox/DualSenseMonitor.swift` | Pushes sliders + DPI into the reader. Sanitizes saved profiles on load. |
| `ControlBox/ControlFrameBuilder.swift` | `gestureOwner` / `gestureActive` / `gestureX` / `gestureY` from the MX snapshot |
| `Packages/ControlBoxCore/.../MappingProfile.swift` | `pointerSpeedFactor`, `gestureSpeedFactor`, haptic-only `mxGestureOwners` |
| `Packages/ControlBoxCore/.../HoldGesture.swift` | 100ms arm, axis lock, live Spaces/MC, discrete App Exposé / media skip, volume |
| `Packages/ControlBoxCore/.../ControlEngine.swift` | Starts `HoldGesture` only for haptic + Gestures |
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
- [focused-host-still-injects.md](focused-host-still-injects.md)
