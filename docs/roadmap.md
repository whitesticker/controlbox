# Product roadmap

Open product work after the multi-device MVP. HID incident notes stay in [README.md](README.md) / [todo.md](todo.md).

## Input and devices

- [x] **DualSense touchpad gestures.** 1-finger and 2-finger are separate Gestures (window navigation / media by default). Same hold-to-swipe engine as the MX gesture button.
- [ ] **Microphone.** DualSense Bluetooth HID Opus capture works in a standalone probe (~47 mic frames/s on this Mac, coils can latch). Not in the app. See [dualsense-bluetooth-mic.md](dualsense-bluetooth-mic.md). USB DualSense jack and Apple TV remote mic still open.
- [ ] **MX Master 4 extra button.** MX4 has one more control than the 3 / 3S. Identify it and show it in calibration + mappings.
- [ ] **MX keyboard.** Add Logitech MX Keys (and family) as a new device family, same host registration as mice / remotes.
- [ ] **MX4 gesture feel.** Haptic-pad swipes on MX4 are less smooth than the 3S gesture button. Measure HID++ XY vs CG fallback and match 3S feel without seizing the pointer.
- [ ] **Generic mouse / Xbox / other TV remotes.** Not this version. Family sessions are the add path.
- [ ] **Per-app mouse profiles.** Switch Control mappings (buttons, gestures, scroll) when the frontmost app changes, so one MX mouse can have a different profile in each app.

## Feedback and UI

- [ ] **Gesture visual cue.** Stronger on-screen feedback when the 3S gesture button, MX4 haptic pad, or DualSense touchpad is held / swiping. Media skip / play / mute already use the action HUD; this is the live hold overlay.
- [x] **Media action cue.** Previous / next track, play/pause, mute, back/forward, and tab switch show the same card as volume (symbol + title).
- [ ] **Calibration layouts.** More accurate physical button placement on DualSense, Apple TV remote, and each MX body.
- [ ] **Onboarding.** First-launch page: permissions, attach a device, Control this Mac, Calibration.
- [ ] **Menu bar icon.** Replace `gamecontroller.fill` with a circle that matches the app icon ring.
- [x] **Background permission.** Permissions pane can request Allow in the Background (`SMAppService`) and open Login Items. Still confirm it survives logout on a fresh Mac.

## Do not

- Call `IOBluetoothDevice.pairedDevices()`.
- Seize Logitech mouse HID or open Bolt `C548`.
- Open the standard mouse collection just to watch buttons.
- Merge 3/3S and 4 into one HID matcher.
