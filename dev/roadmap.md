# Product roadmap

Open product work after the multi-device MVP. HID incident notes stay in [README.md](README.md) / [todo.md](todo.md).

## Input and devices

- [x] **DualSense touchpad gestures.** 1-finger and 2-finger are separate Gestures (window navigation / media by default). Same hold-to-swipe engine as the MX gesture button.
- [ ] **Microphone.** Capture and use the DualSense and Apple TV remote mics on macOS (Bluetooth HID-only today; USB DualSense jack is untested).
- [x] **MX Master 4 extra button.** MX4 **gesture button** is CID `0x00C3` (same thumb button as 3S). Default is Gestures. The force pad is the **haptic button**.
- [x] **MX Mechanical settings.** Device family for MX Mechanical (`0xB366`) and Mini (`0xB367`): backlight, lighting effect, battery saving, battery %. See [mx-mechanical-hid.md](mx-mechanical-hid.md). Key remapping and MX Keys are still open.
- [ ] **Keyboard key remap pane.** A device-page remap UI for MX Keys / Mechanical (and later other keyboards). Divert only bound keys; Mechanical settings (backlight) are already shipped. See also [todo.md](todo.md).
- [x] **Caps Lock as modifier.** Separate Mac pane: Caps Lock is a hold key that synthesizes a chosen modifier chord (default Control) for Control Box only, not a caps toggle. Off until the toggle is on. See [caps-lock-modifier.md](caps-lock-modifier.md).
- [ ] **Smoother main-wheel scrolling.** Thumb-wheel travel is already eased (every thumb mode) when Pointer & Scroll Smooth scrolling is on. The main wheel still only gets the MX high-res bit plus tap leftover rounding — intercept line ticks and feed the same interpolator. See also [trackpad-scroll-lag-with-mx.md](trackpad-scroll-lag-with-mx.md).
- [ ] **MX4 gesture feel.** Haptic-pad swipes on MX4 are less smooth than the 3S gesture button. Measure HID++ XY vs CG fallback and match 3S feel without seizing the pointer.
- [x] **Logi Bolt talk.** MX 3S / 4 / Mechanical connected only through the USB receiver (`0xC548`) attach over vendor-HID++ slots. Pairing / unpair is **Add Device → Logi Bolt**. Do not open the mouse collection. MX4 haptic XY cannot use nested report `0x02` on Bolt. BLE and Bolt for the same unit are one device. See [logi-bolt-receiver.md](logi-bolt-receiver.md).
- [ ] **Devices sidebar grouping.** Group by type (Mouse, Gamepad, Remote, Keyboard, Other), then by brand when a type has more than one. Hide empty types. See [todo.md](todo.md) Logitech-related improvements.
- [ ] **Generic mouse and gamepad mapper.** A settings pane that maps a generic USB/Bluetooth mouse or gamepad (Xbox, etc.) the same way as a known family: buttons, sticks, wheel. Family sessions are still the add path. Not this version’s HID stack.
- [x] **Per-app mouse profiles.** Switch Control mappings (buttons, gestures, thumb-wheel mode) when the frontmost app changes. MX device page **profile tiles**; known browsers and editors start from a preset. See [per-app-mouse-profiles.md](per-app-mouse-profiles.md).
- [x] **MX thumb-wheel sensitivity.** Calibration **On this mouse**: per-mouse scale of diverted HID++ `0x2150` thumb travel. Independent of Pointer & Scroll wheel speed. See [mx-smartshift.md](mx-smartshift.md).
- [x] **MX Free Spin / Ratchet.** Calibration **On this mouse**: segmented **Free Spin** / **Ratchet** plus a SmartShift sensitivity slider. Firmware `0x2111`, fallback `0x2110`. See [mx-smartshift.md](mx-smartshift.md).
- [x] **MX4 Gesture as a Gestures owner.** On MX Master 4, **Gesture button** is the thumb button (CID `0x00C3`, same as 3S). **Haptic button** stays the force-sensing pad. Both default to Gestures. Divert `0x33` and do not pin. Related: [haptic-vs-back-gesture.md](haptic-vs-back-gesture.md), [mx4-gesture-button-freezes-pointer.md](mx4-gesture-button-freezes-pointer.md).
- [x] **DualSense and Remote per-app profiles.** Same **profile tiles** treatment as MX mice: Default plus per-app button and gesture mappings that follow the frontmost app. Analog, Pointer & Scroll, and Calibration remain device-level outside Profiles; DualSense Tab repeat is on Calibration. See [per-app-mouse-profiles.md](per-app-mouse-profiles.md).

## App settings

- [ ] **Export / import JSON.** Settings pane: export the whole Control Box configuration as JSON, and import a file to apply it quickly.
- [ ] **Pointer & Scroll vs System Settings.** Reconcile Control Box pointer and wheel sliders with macOS mouse tracking and scroll so they are not two competing controls.

## Feedback and UI

- [x] **Display arrangement presets.** Separate Mac pane: snapshot the current layout, sandbox editor (System Settings–style canvas), apply only when the same external combo (and built-in present/absent) is connected. Identity is UUID/EDID, not `CGDirectDisplayID`. Position, main display, and mirror only. Keyboard shortcut is a 3+ modifier chord plus 1–9 / arrows, with a snapshot HUD; chords cannot match Window Management move, resize, throw, or organize.
- [ ] **Gesture visual cue.** Stronger on-screen feedback when the 3S gesture button, MX4 haptic pad, or DualSense touchpad is held / swiping. Media skip / play / mute already use the action HUD; this is the live hold overlay.
- [x] **Media action cue.** Previous / next track, play/pause, mute, back/forward, and tab switch show the same card as volume (symbol + title).
- [ ] **Calibration layouts.** More accurate physical button placement on DualSense, Apple TV remote, and each MX body.
- [x] **Onboarding and device management.** First-launch: permissions, attach a device, Control this Mac, Calibration. A device is on the **sidebar** only after **Add** on Add Device (existing settings → **Settings**). **Delete Device** drops the sidebar row even if the hardware is still connected; Add Device brings it back. See also [todo.md](todo.md).
- [x] **System Monitor (top).** Separate Mac pane; optional second menu bar extra with live network speed and the top dashboard. Control Box’s own menu extra is unchanged.
- [x] **Night Shift curve.** Separate Mac pane; optional 24-hour yellowness curve that drives system Night Shift. Off until the pane toggle is on.
- [x] **Menu bar icon.** The Control Box extra is a template ring matching the app icon annulus, not `gamecontroller.fill`.
- [x] **Launch at login and Hide Dock.** Permissions pane: Launch at Login (`SMAppService.mainApp`). Hide Dock icon; Command-Q closes the window; quit from the Control Box menu bar extra.
- [x] **Brightness and Sound extras.** Optional separate menu bar icons from the Display Brightness and Sound panes. Off until each toggle is on.
- [x] **Caffeinate.** Separate Mac pane plus optional coffee-cup extra. Duration menu (1 minute through 1 day, plus forever), countdown while a session is on, and **Sleep Now** for immediate system sleep. IOPM idle-sleep and idle-display assertions. Off until the extra toggle is on.
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
- [ ] **Sound per-app icons.** Show each app’s icon on the Sound pane per-app volume rows.

## Site

- [ ] **Product page.** Public site is `docs/` (`index.html`, `styles.css`, `screenshots/`). GitHub Pages **Deploy from a branch** → `main` / `/docs` → `https://whitesticker.github.io/controlbox/`. Optional custom domain later (~$10–15/year) — `getcontrolbox.com` if a short URL is wanted. Do not buy aftermarket `controlbox.com`. Do not chase `controlbox.net` (existing Miami company). Cask `homepage` and the README point at the Pages URL. No backend, no analytics. Do not paste the incident log. Problem log lives in `dev/`. Regenerate pane shots with `ControlBox --export-screenshots docs/screenshots`.

## Do not

- Call `IOBluetoothDevice.pairedDevices()`.
- Seize Logitech mouse HID. Do not open Bolt `C548` except the planned vendor-HID++ slot walk in [logi-bolt-receiver.md](logi-bolt-receiver.md).
- Open the standard mouse collection just to watch buttons.
- Merge 3/3S and 4 into one HID matcher.
