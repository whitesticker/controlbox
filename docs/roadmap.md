# Product roadmap

Open product work after the multi-device MVP. HID incident notes stay in [README.md](README.md) / [todo.md](todo.md).

## Input and devices

- [x] **DualSense touchpad gestures.** 1-finger and 2-finger are separate Gestures (window navigation / media by default). Same hold-to-swipe engine as the MX gesture button.
- [ ] **Microphone.** Capture and use the DualSense and Apple TV remote mics on macOS (Bluetooth HID-only today; USB DualSense jack is untested).
- [x] **MX Master 4 extra button.** MX4 Side is CID `0x00C3` (frontmost thumb button under the roller). Calibration and mappings show it; default is Mission Control.
- [ ] **MX keyboard.** Add Logitech MX Keys and **MX Mechanical** as a new device family, same host registration as mice / remotes. Map keys, layers, and extra keys the same way as the mice.
- [ ] **Caps Lock as modifier.** Treat Caps Lock as another modifier for Control Box chords (Hyper-style), not a caps toggle. Must not collide with existing Window Management / Display Arrangement chords.
- [ ] **Smoother wheel scrolling.** Improve the existing Pointer & Scroll smooth-scrolling path so MX and generic mice feel closer to the trackpad (less stepped, less lag). See also [trackpad-scroll-lag-with-mx.md](trackpad-scroll-lag-with-mx.md).
- [ ] **MX4 gesture feel.** Haptic-pad swipes on MX4 are less smooth than the 3S gesture button. Measure HID++ XY vs CG fallback and match 3S feel without seizing the pointer.
- [ ] **Generic mouse / Xbox / other TV remotes.** Not this version. Family sessions are the add path.
- [ ] **Per-app mouse profiles.** Switch Control mappings (buttons, gestures, scroll) when the frontmost app changes, so one MX mouse can have a different profile in each app.

## Feedback and UI

- [x] **Display arrangement presets.** Separate Mac pane: snapshot the current layout, sandbox editor (System Settings–style canvas), apply only when the same external combo (and built-in present/absent) is connected. Identity is UUID/EDID, not `CGDirectDisplayID`. Position, main display, and mirror only. Keyboard shortcut is a 3+ modifier chord plus 1–9 / arrows, with a snapshot HUD; chords cannot match Window Grab move, resize, throw, or organize.
- [ ] **Gesture visual cue.** Stronger on-screen feedback when the 3S gesture button, MX4 haptic pad, or DualSense touchpad is held / swiping. Media skip / play / mute already use the action HUD; this is the live hold overlay.
- [x] **Media action cue.** Previous / next track, play/pause, mute, back/forward, and tab switch show the same card as volume (symbol + title).
- [ ] **Calibration layouts.** More accurate physical button placement on DualSense, Apple TV remote, and each MX body.
- [ ] **Onboarding.** First-launch page: permissions, attach a device, Control this Mac, Calibration.
- [x] **System Monitor (top).** Separate Mac pane; optional second menu bar extra with live network speed and the top dashboard. Control Box’s own menu extra is unchanged.
- [x] **Night Shift curve.** Separate Mac pane; optional 24-hour yellowness curve that drives system Night Shift. Off until the pane toggle is on.
- [x] **Menu bar icon.** The Control Box extra is a template ring matching the app icon annulus, not `gamecontroller.fill`.
- [x] **Launch at login and Hide Dock.** Permissions pane: Launch at Login (`SMAppService.mainApp`). Hide Dock icon; Command-Q closes the window; quit from the Control Box menu bar extra.
- [x] **Brightness and Sound extras.** Optional separate menu bar icons from the Display Brightness and Sound panes. Off until each toggle is on.
- [x] **Background permission.** Permissions pane can request Allow in the Background (`SMAppService`) and open Login Items. Still confirm it survives logout on a fresh Mac.
- [x] **Window throw and organize.** Window Grab pane: throw is hold-modifiers + pointer on a 3×3 snap map; organize is a recorded shortcut (default Control-Command-O) that tiles windows on the pointer’s screen. Off until each toggle is on. Modifier chords for move/resize/throw cannot match Display Arrangement. Organize cannot use Arrangement’s number/arrow keys with the same modifiers.
- [ ] **Window Management rename + more organize layouts.** Rename the Window Grab Mac pane to **Window Management**. Keep move / resize / throw. Add more Organize options than the current “tile visible windows on this screen” shortcut (e.g. columns, rows, left/right halves, leave one app full).
- [ ] **Shake to hide others.** Shake a window to hide every other window on that monitor (Windows Aero Shake). A second shake restores them. Hide Dock Previews while this is in progress, same as Window Grab hold.
- [ ] **App switcher window previews.** Show that app’s window cards (including minimized / other Spaces) in the tab / application switcher, same catalog as Dock Previews. Related: [app-switcher-no-bar.md](app-switcher-no-bar.md), [dock-window-preview.md](dock-window-preview.md).
- [ ] **Dock icon scroll.** Scroll up/down on a Dock icon to minimize or restore/maximize that app’s window. Do not intercept native Dock clicks.
- [ ] **Temp shelf.** A Dropover-style floating shelf: drop files onto a parked pane, keep them while you switch apps, drag them out later. Off until a pane toggle is on. Not a full Finder replacement.
- [ ] **Selection popup.** A PopClip-style bar when text is selected: copy, search, and a short list of actions. Accessibility required. Do not steal the selection or replace the system Services menu wholesale.
- [x] **Dock window previews.** Separate Mac pane: hover a Dock icon to see that app’s windows and click one to focus it. Off until the pane toggle is on. Live thumbnails need Screen Recording; titles work without it. Not gated on an MX Master.

## Do not

- Call `IOBluetoothDevice.pairedDevices()`.
- Seize Logitech mouse HID or open Bolt `C548`.
- Open the standard mouse collection just to watch buttons.
- Merge 3/3S and 4 into one HID matcher.
