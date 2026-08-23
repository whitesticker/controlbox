# MX Master 4: pointer, DPI, and haptic swipes

Working model as of 2026-08-22. Active test device is **MX Master 4 over Bluetooth LE** (product `0xB042`). Leave MX Master 3 / 3S disconnected.

Hardware layout is in [mx-master-4-ble-haptic.md](mx-master-4-ble-haptic.md). This file is how VibeRemote maps that hardware to cursor speed and window gestures.

## Two sliders, plus DPI

Do not merge these. The user wants them independent.

| Control | What it changes | What it must not change |
|---|---|---|
| **DPI** | Sensor resolution. Higher = smoother tracking, more HID counts per inch. | Cursor feel. Haptic swipe feel. |
| **Pointer speed** | On-screen cursor only. | Hold-to-swipe Spaces / Mission Control / App Exposé. |
| **Haptic gesture speed** | Hold-to-swipe only. 50% = 1× native HID travel at 1000 DPI. 0% is a comfortable Spaces swipe on this Mac. | Cursor. |

There is **no** separate Acceleration slider. macOS tracking speed is how pointer speed is implemented.

Settings copy lives under Profiles → Pointer & scroll.

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
4. Feed `gestureX` / `gestureY` into `ControlEngine` live gestures.

HID++ diverted raw XY (`handleRawXY`) uses the same scaler when that pipe exists. HID++ is not required for BLE press or swipe.

Without the DPI term, 2000 DPI felt like twice the swipe of 1000 DPI. At 1000 DPI the haptic bar felt right; other DPI values now match that physical travel. See [haptic-swipe-scales-with-dpi.md](haptic-swipe-scales-with-dpi.md).

## Hold-to-swipe module

`HoldGesture` in IRemoteControl is the only place that decides tap vs swipe, axis, Spaces, Mission Control, App Exposé, media skip, and volume. `ControlEngine` starts it when the haptic pad is held and that binding is Gestures.

The MX reader only captures pad down + raw XY and a pinned cursor. It does not know about media vs window navigation.

## Gestures is the haptic pad only

Profiles expose **Gestures** on the haptic pad. Back, Forward, and the other clicks stay ordinary button bindings.

Click-as-gesture (hold Back and move the mouse) is parked. The Back button has no pad XY; the only motion is the desk laser, and that path never controlled live Spaces reliably. See [haptic-vs-back-gesture.md](haptic-vs-back-gesture.md).

## Tap vs swipe

A short press is a **tap** (the click action, default Mission Control). Hold + move is a **swipe**.

Both layers wait **100ms** after press before a swipe can start:

- `LiveGestureState` does not lock an axis or post DockSwipe until 100ms.
- `finishGesture` classifies the release as a tap if the hold was under 100ms, even if the pad wobbled.

After 100ms, axis lock is: mostly vertical if `|y| >= 6` and `|y| >= |x|`; otherwise horizontal once travel ≥ 10.

See [haptic-tap-starts-swipe.md](haptic-tap-starts-swipe.md).

## Live window gestures

Window navigation preset (haptic pad):

| Move | Action | How it runs |
|---|---|---|
| Tap | Mission Control | Discrete system action on release |
| Hold + left / right | Spaces / desktop switch | Live DockSwipe, horizontal |
| Hold + up | Mission Control | Live DockSwipe, vertical |
| Hold + down | App Exposé | Discrete Core Dock / Ctrl-Down once travel is clearly down (`y >= 40`) |

Media controls preset: tap is play/pause, up/down is live volume, left/right is previous/next track (one skip per hold, same 100ms arm + travel threshold). Not DockSwipe. See [media-gesture-skip-dead.md](media-gesture-skip-dead.md).

Live follow posts the Mac Mouse Fix / [dockswipe](https://github.com/oomol-lab/dockswipe) field recipe: companion type-29 marker + type-30 dock-control, subtype 23, axis 1 horizontal / 2 vertical. Post **e30 then e29**. Field `124` is absolute progress. Do **not** set `CGEvent.type` to 30; that made vertical look like magnify.

Progress is **absolute**, not incremental. A dropped or reset sample that looks like a teleport toward the origin is ignored so Spaces does not snap backward. See [dockswipe-progress-snapback.md](dockswipe-progress-snapback.md).

Horizontal and vertical live spans are the same (`screen width`) so one haptic-speed slider maps both. A ~48 px Mission Control span made up/down finish in a flick.

There is **no** 180 ms haptic-release debounce. Release ends the DockSwipe session immediately so Spaces commits.

Downward DockSwipe does not open App Exposé on this Mac (darwin 25.5 / macOS 26.5). That direction fires the system App Exposé action instead. See [dockswipe-down-skips-app-expose.md](dockswipe-down-skips-app-expose.md).

## What not to do

- Do not apply pointer speed or OS tracking pixels to haptic X/Y.
- Do not omit the DPI term from haptic scaling. 50% “1× HID” without `1000 / dpi` is only true at 1000 DPI.
- Do not open or seize the standard mouse collection (`0x01` / `0x02`) just to watch buttons.
- Do not send Reprog persist or force-raw-XY. Clear divert with `0x22`.
- Do not call `IOBluetoothDevice.pairedDevices()`.
- Do not treat Bolt receiver `C548` as this mouse.
- Do not switch Mission Control back to a hotkey-only path. Live follow is intentional.
- Do not add a user-facing Acceleration slider.
- Do not `DispatchQueue.main.async` every BLE mouse report `0x02`; that floods the main thread. HID++ report `0x11` can hop to main; `0x02` is handled on the callback thread.

## Code map

| File | Role |
|---|---|
| `IRemote/LogitechMXMasterReader.swift` | HID++, report `0x02` haptic XY, freeze cursor, 100ms tap classify |
| `IRemote/PointerHIDSettings.swift` | OS pointer resolution + acceleration from pointer slider + DPI |
| `IRemote/ProfilesPane.swift` | DPI, Pointer speed, Haptic gesture speed |
| `IRemote/DualSenseMonitor.swift` | Pushes both sliders + DPI into the reader every poll |
| `IRemote/ControlFrameBuilder.swift` | `gestureActive` from held / down / haptic |
| `Packages/IRemoteControl/.../MappingProfile.swift` | `pointerSpeedFactor`, `gestureSpeedFactor` |
| `Packages/IRemoteControl/.../ControlEngine.swift` | 100ms arm, axis lock, live Spaces/MC, discrete App Exposé |
| `Packages/IRemoteControl/.../DockSwipe.swift` | Absolute dock-swipe events |
| `Packages/IRemoteControl/.../SystemNavigation.swift` | Core Dock / symbolic hotkeys for MC and App Exposé |

## Related

- [mx-master-4-ble-haptic.md](mx-master-4-ble-haptic.md)
- [hidpp-divert-steals-pointer.md](hidpp-divert-steals-pointer.md)
- [extra-buttons-missing-in-calibration.md](extra-buttons-missing-in-calibration.md)
