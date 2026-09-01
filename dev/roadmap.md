# Product roadmap

Open product work after the multi-device MVP. HID incident notes stay in [README.md](README.md) / [todo.md](todo.md).

## Input and devices

- [x] **DualSense touchpad gestures.** 1-finger and 2-finger are separate Gestures (window navigation / media by default). Same hold-to-swipe engine as the MX gesture button.
- [ ] **Microphone.** Capture and use the DualSense and Apple TV remote mics on macOS (Bluetooth HID-only today; USB DualSense jack is untested).
- [x] **MX Master 4 extra button.** MX4 Side is CID `0x00C3` (frontmost thumb button under the roller). Calibration and mappings show it; default is Mission Control.
- [x] **MX Mechanical settings.** Device family for MX Mechanical (`0xB366`) and Mini (`0xB367`): backlight, lighting effect, battery saving, battery %. See [mx-mechanical-hid.md](mx-mechanical-hid.md). Key remapping and MX Keys are still open.
- [ ] **MX keyboard remapping.** Map MX Keys / Mechanical extra keys the same way as the mice. Settings panel for Mechanical is shipped.
- [x] **Caps Lock as modifier.** Separate Mac pane: Caps Lock is a hold key that synthesizes a chosen modifier chord (default Control) for Control Box only, not a caps toggle. Off until the toggle is on. See [caps-lock-modifier.md](caps-lock-modifier.md).
- [ ] **Smoother wheel scrolling.** Improve the existing Pointer & Scroll smooth-scrolling path so MX and generic mice feel closer to the trackpad (less stepped, less lag). See also [trackpad-scroll-lag-with-mx.md](trackpad-scroll-lag-with-mx.md).
- [ ] **MX4 gesture feel.** Haptic-pad swipes on MX4 are less smooth than the 3S gesture button. Measure HID++ XY vs CG fallback and match 3S feel without seizing the pointer.
- [ ] **Logi Bolt.** MX 3S / 4 connected only through the USB receiver (`0xC548`) never attach: the mouse is a HID++ slot, not BLE product `0xB034` / `0xB042`. Open only the receiver vendor HID++ collection, walk slots by name, prefer BLE if both radios are up. Do not open the mouse collection. MX4 haptic XY cannot use nested report `0x02` on Bolt. Capture `C548` with `tools/hidpp-sniff.swift` when the dongle is plugged in. See [logi-bolt-receiver.md](logi-bolt-receiver.md).
- [ ] **Generic mouse / Xbox / other TV remotes.** Not this version. Family sessions are the add path.
- [ ] **Per-app mouse profiles.** Switch Control mappings (buttons, gestures, scroll) when the frontmost app changes, so one MX mouse can have a different profile in each app.

## Feedback and UI

- [x] **Display arrangement presets.** Separate Mac pane: snapshot the current layout, sandbox editor (System Settings–style canvas), apply only when the same external combo (and built-in present/absent) is connected. Identity is UUID/EDID, not `CGDirectDisplayID`. Position, main display, and mirror only. Keyboard shortcut is a 3+ modifier chord plus 1–9 / arrows, with a snapshot HUD; chords cannot match Window Management move, resize, throw, or organize.
- [ ] **Gesture visual cue.** Stronger on-screen feedback when the 3S gesture button, MX4 haptic pad, or DualSense touchpad is held / swiping. Media skip / play / mute already use the action HUD; this is the live hold overlay.
- [x] **Media action cue.** Previous / next track, play/pause, mute, back/forward, and tab switch show the same card as volume (symbol + title).
- [ ] **Calibration layouts.** More accurate physical button placement on DualSense, Apple TV remote, and each MX body.
- [ ] **Onboarding.** First-launch page: permissions, attach a device, Control this Mac, Calibration.
- [x] **System Monitor (top).** Separate Mac pane; optional second menu bar extra with live network speed and the top dashboard. Control Box’s own menu extra is unchanged.
- [x] **Night Shift curve.** Separate Mac pane; optional 24-hour yellowness curve that drives system Night Shift. Off until the pane toggle is on.
- [x] **Menu bar icon.** The Control Box extra is a template ring matching the app icon annulus, not `gamecontroller.fill`.
- [x] **Launch at login and Hide Dock.** Permissions pane: Launch at Login (`SMAppService.mainApp`). Hide Dock icon; Command-Q closes the window; quit from the Control Box menu bar extra.
- [x] **Brightness and Sound extras.** Optional separate menu bar icons from the Display Brightness and Sound panes. Off until each toggle is on.
- [x] **Caffeinate.** Separate Mac pane plus optional coffee-cup extra. Duration menu (1 minute through 1 day, plus forever); countdown while a session is on. IOPM idle-sleep and idle-display assertions. Off until the extra toggle is on.
- [x] **Background permission.** Permissions pane can request Allow in the Background (`SMAppService`) and open Login Items. Still confirm it survives logout on a fresh Mac.
- [x] **Window throw and organize.** Window Management pane: throw is hold-modifiers + pointer on a 3×3 snap map; organize is a recorded shortcut (default Control-Command-O) that tiles windows on the pointer’s screen. Off until each toggle is on. Modifier chords for move/resize/throw cannot match Display Arrangement. Organize cannot use Arrangement’s number/arrow keys with the same modifiers.
- [x] **Window Management rename.** The Window Grab Mac pane is now **Window Management**. Move, resize, throw, organize, shake, and Dock-click minimize live there.
- [ ] **More organize layouts.** More Organize options than the current “tile visible windows on this screen” shortcut (e.g. columns, rows, left/right halves, leave one app full).
- [x] **Shake to hide others.** Window Management pane: shake a window (title bar or Move) to hide every other visible window. Second shake restores. Scope is this display or all displays (monitors). Off until the toggle is on. Hide Dock Previews while the shake drag is watched.
- [x] **Minimize on Dock click.** Window Management pane: if that app is already front with a visible window, click its Dock icon to minimize that window. Off until the toggle is on. Listen-only — do not swallow the native click. No display picker.
- [x] **App switcher window previews.** Dock Previews pane: while Command-Tab (or Next / Previous application) is up, show that app’s window cards from the same catalog. No title line, no HUD. Off until the toggle is on. Related: [app-switcher-window-preview.md](app-switcher-window-preview.md), [app-switcher-no-bar.md](app-switcher-no-bar.md).
- [ ] **Temp shelf.** A Dropover-style floating shelf: drop files onto a parked pane, keep them while you switch apps, drag them out later. Off until a pane toggle is on. Not a full Finder replacement.
- [ ] **Selection popup.** A PopClip-style bar when text is selected: copy, search, and a short list of actions. Accessibility required. Do not steal the selection or replace the system Services menu wholesale.
- [x] **Dock window previews.** Separate Mac pane: hover a Dock icon to see that app’s windows and click one to focus it. Off until the pane toggle is on. Live thumbnails need Screen Recording; titles work without it. Not gated on an MX Master.

## Site

- [ ] **Product page.** Public site is `docs/` (`index.html`, `styles.css`, `screenshots/`). GitHub Pages **Deploy from a branch** → `main` / `/docs` → `https://whitesticker.github.io/controlbox/`. Optional custom domain later (~$10–15/year) — `getcontrolbox.com` if a short URL is wanted. Do not buy aftermarket `controlbox.com`. Do not chase `controlbox.net` (existing Miami company). Cask `homepage` and the README point at the Pages URL. No backend, no analytics. Do not paste the incident log. Problem log lives in `dev/`. Regenerate pane shots with `ControlBox --export-screenshots docs/screenshots`.

## Do not

- Call `IOBluetoothDevice.pairedDevices()`.
- Seize Logitech mouse HID. Do not open Bolt `C548` except the planned vendor-HID++ slot walk in [logi-bolt-receiver.md](logi-bolt-receiver.md).
- Open the standard mouse collection just to watch buttons.
- Merge 3/3S and 4 into one HID matcher.
