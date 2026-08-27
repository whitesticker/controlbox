# Product roadmap

Open product work after the multi-device MVP. HID incident notes stay in [README.md](README.md) / [todo.md](todo.md).

## Input and devices

- [x] **DualSense touchpad gestures.** 1-finger and 2-finger are separate Gestures (window navigation / media by default). Same hold-to-swipe engine as the MX gesture button.
- [ ] **Microphone.** Capture and use the DualSense and Apple TV remote mics on macOS (Bluetooth HID-only today; USB DualSense jack is untested).
- [x] **MX Master 4 extra button.** MX4 Side is CID `0x00C3` (frontmost thumb button under the roller). Calibration and mappings show it; default is Mission Control.
- [ ] **MX keyboard.** Add Logitech MX Keys (and family) as a new device family, same host registration as mice / remotes.
- [ ] **MX4 gesture feel.** Haptic-pad swipes on MX4 are less smooth than the 3S gesture button. Measure HID++ XY vs CG fallback and match 3S feel without seizing the pointer.
- [ ] **Generic mouse / Xbox / other TV remotes.** Not this version. Family sessions are the add path.
- [ ] **Per-app mouse profiles.** Switch Control mappings (buttons, gestures, scroll) when the frontmost app changes, so one MX mouse can have a different profile in each app.

## Feedback and UI

- [x] **Display arrangement presets.** Separate Mac pane: snapshot the current layout, sandbox editor (System Settings–style canvas), apply only when the same external combo (and built-in present/absent) is connected. Identity is UUID/EDID, not `CGDirectDisplayID`. Position, main display, and mirror only. Keyboard shortcut is a 3+ modifier chord plus 1–9 / arrows, with a snapshot HUD; chords cannot match Window Grab.
- [ ] **Gesture visual cue.** Stronger on-screen feedback when the 3S gesture button, MX4 haptic pad, or DualSense touchpad is held / swiping. Media skip / play / mute already use the action HUD; this is the live hold overlay.
- [x] **Media action cue.** Previous / next track, play/pause, mute, back/forward, and tab switch show the same card as volume (symbol + title).
- [ ] **Calibration layouts.** More accurate physical button placement on DualSense, Apple TV remote, and each MX body.
- [ ] **Onboarding.** First-launch page: permissions, attach a device, Control this Mac, Calibration.
- [x] **System Monitor (top).** Separate Mac pane; optional second menu bar extra with live network speed and the top dashboard. Control Box’s own menu extra is unchanged.
- [x] **Night Shift curve.** Separate Mac pane; optional 24-hour yellowness curve that drives system Night Shift. Off until the pane toggle is on.
- [ ] **Menu bar icon.** Replace `gamecontroller.fill` with a circle that matches the app icon ring.
- [x] **Background permission.** Permissions pane can request Allow in the Background (`SMAppService`) and open Login Items. Still confirm it survives logout on a fresh Mac.

## Do not

- Call `IOBluetoothDevice.pairedDevices()`.
- Seize Logitech mouse HID or open Bolt `C548`.
- Open the standard mouse collection just to watch buttons.
- Merge 3/3S and 4 into one HID matcher.
