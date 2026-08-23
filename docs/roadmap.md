# Product roadmap

Open product work after the multi-device MVP. HID incident notes stay in [README.md](README.md) / [todo.md](todo.md).

## Input and devices

- [ ] **Microphone.** Capture and use the DualSense and Apple TV remote mics on macOS (Bluetooth HID-only today; USB DualSense jack is untested).
- [ ] **MX Master 4 extra button.** MX4 has one more control than the 3 / 3S. Identify it and show it in calibration + mappings.
- [ ] **MX keyboard.** Add Logitech MX Keys (and family) as a new device family, same host registration as mice / remotes.
- [ ] **MX4 gesture feel.** Haptic-pad swipes on MX4 are less smooth than the 3S gesture button. Measure HID++ XY vs CG fallback and match 3S feel without seizing the pointer.
- [ ] **Generic mouse / Xbox / other TV remotes.** Not this version. Family sessions are the add path.

## Feedback and UI

- [ ] **Gesture visual cue.** Stronger on-screen feedback when the 3S gesture button or MX4 haptic pad is held / swiping.
- [ ] **Media action cue.** Previous / next track (and similar discrete gestures) should show a HUD so it is obvious the action fired.
- [ ] **Calibration layouts.** More accurate physical button placement on DualSense, Apple TV remote, and each MX body.
- [ ] **Onboarding.** First-launch page: permissions, attach a device, Control this Mac, Calibration.
- [ ] **Menu bar icon.** Replace `gamecontroller.fill` with a circle that matches the app icon ring.
- [x] **Background permission.** Permissions pane can request Allow in the Background (`SMAppService`) and open Login Items. Still confirm it survives logout on a fresh Mac.

## Do not

- Call `IOBluetoothDevice.pairedDevices()`.
- Seize Logitech mouse HID or open Bolt `C548`.
- Open the standard mouse collection just to watch buttons.
- Merge 3/3S and 4 into one HID matcher.
