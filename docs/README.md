# Control Box problem log

One issue type per file. These are failures we already hit while working on DualSense, Apple TV remote, and MX Master support.

## Read in this order (MX Master)

0. [mx-master-3s-hid.md](mx-master-3s-hid.md) — current 3S hardware: BLE `0xB034`, nested `0xFF43` / `0x11`, CID `0x00C3`.

1. [mx-master-4-pointer-and-haptic.md](mx-master-4-pointer-and-haptic.md) — current working model: sliders, defaults, haptic pipeline, what not to do.
2. [mx-master-4-ble-haptic.md](mx-master-4-ble-haptic.md) — BLE hardware: report `0x02` button 7, nested HID++ `0x11`.
3. [haptic-vs-back-gesture.md](haptic-vs-back-gesture.md) — why Gestures is haptic-only; what we tried on Back.
4. [todo.md](todo.md) — HID / MX fix list.
5. [roadmap.md](roadmap.md) — product backlog (mic, HUD, MX Keys / MX Mechanical, window management, onboarding, product page). System Monitor (top) and Dock Previews are shipped as Mac panes.

HID primer and “should we drop HID++?” live in chat and `AGENTS.md`. This folder is incident notes, the MX4 working model, plus that list. Repeating timers and system-API polls are listed in [polling-loops.md](polling-loops.md).

## Incident notes

| File | Symptom |
|---|---|
| [bluetooth-paired-devices-heap-corruption.md](bluetooth-paired-devices-heap-corruption.md) | App crashes on launch or while listing devices |
| [hid-open-seize-dual-mouse.md](hid-open-seize-dual-mouse.md) | Crash or dead input with two Logitech mice |
| [hidpp-divert-steals-pointer.md](hidpp-divert-steals-pointer.md) | Pointer dies until the mouse is power-cycled |
| [extra-buttons-missing-in-calibration.md](extra-buttons-missing-in-calibration.md) | Haptic / back / forward / Side do not light up |
| [mx4-clicks-missing-in-calibration.md](mx4-clicks-missing-in-calibration.md) | MX4 left / right / wheel stay idle in Calibration |
| [focused-host-still-injects.md](focused-host-still-injects.md) | Gestures still run the Mac while Control Box is focused |
| [adhoc-signing-resets-tcc.md](adhoc-signing-resets-tcc.md) | Accessibility / Input Monitoring must be re-added every build |
| [mx-master-3s-wrong-usage-page.md](mx-master-3s-wrong-usage-page.md) | 3S never attaches while Master 4 does |
| [mx-master-3s-hid.md](mx-master-3s-hid.md) | BLE 3S HID++ lives on the mouse device, not a second collection |
| [mx-settings-panel-wrong-model.md](mx-settings-panel-wrong-model.md) | 3S is controlled from the remembered MX4 settings panel |
| [mx-master-4-ble-haptic.md](mx-master-4-ble-haptic.md) | BLE MX4 haptic/HID++ live on the mouse report, not `0xFF00` |
| [haptic-swipe-scales-with-dpi.md](haptic-swipe-scales-with-dpi.md) | High DPI makes hold-to-swipe much faster than 1000 DPI |
| [dockswipe-down-skips-app-expose.md](dockswipe-down-skips-app-expose.md) | Swipe down never opens App Exposé |
| [haptic-tap-starts-swipe.md](haptic-tap-starts-swipe.md) | A tap also peeks Spaces or Mission Control |
| [dockswipe-progress-snapback.md](dockswipe-progress-snapback.md) | Spaces / Mission Control jump backward mid-swipe |
| [dockswipe-button-overshoot.md](dockswipe-button-overshoot.md) | L1/R1 desktop switch peeks into the next Space and bounces |
| [app-switcher-no-bar.md](app-switcher-no-bar.md) | Next/Previous application swaps apps with no Command-Tab bar |
| [app-switcher-window-preview.md](app-switcher-window-preview.md) | Application switcher has no window cards |
| [caps-lock-modifier.md](caps-lock-modifier.md) | Caps Lock toggles caps instead of acting as a modifier |
| [media-gesture-skip-dead.md](media-gesture-skip-dead.md) | Media left/right does not skip tracks |
| [gesture-owner-haptic-only.md](gesture-owner-haptic-only.md) | Gestures is haptic-pad only (enforcement) |
| [haptic-vs-back-gesture.md](haptic-vs-back-gesture.md) | Click-as-gesture on Back is parked (why) |
| [ddc-identity-from-wrong-framebuffer.md](ddc-identity-from-wrong-framebuffer.md) | Displays lists an extra monitor; a named slider does not drive that panel |
| [arrangement-duplicate-combo.md](arrangement-duplicate-combo.md) | Display Arrangement lists the same monitors as two groups |
| [process-tap-exclusive.md](process-tap-exclusive.md) | Per-app volume does nothing while FineTune or another tap mixer is open |
| [macbook-app-volume-binary.md](macbook-app-volume-binary.md) | MacBook speakers: per-app slider is 100% or silence |
| [macbook-app-volume-system-lag.md](macbook-app-volume-system-lag.md) | Sequoia: moving a Sound slider freezes the whole Mac |
| [audio-permission-stale.md](audio-permission-stale.md) | Permissions still asks after System Audio Recording is granted |
| [mac-panes-gated-on-mx.md](mac-panes-gated-on-mx.md) | Window Grab and Pointer & Scroll stay off until an MX Master is attached |
| [window-grab-only-own-app.md](window-grab-only-own-app.md) | Window grab moves Control Box but not Finder, Safari, or other apps |
| [night-shift-hijack-hang.md](night-shift-hijack-hang.md) | App beachballs on launch while Night Shift take-over is on |
| [trackpad-scroll-lag-with-mx.md](trackpad-scroll-lag-with-mx.md) | MacBook trackpad scroll stutters once an MX Master is attached |
| [system-monitor-reorder.md](system-monitor-reorder.md) | System Monitor dashboard rows cannot be dragged in settings |
| [system-monitor-arrow-jitter.md](system-monitor-arrow-jitter.md) | Menu bar ↑/↓ arrows slide when the speed digits change length |
| [menu-bar-extras-and-login.md](menu-bar-extras-and-login.md) | Launch at Login, Hide Dock / Command-Q, brightness and Sound extras |
| [dock-window-preview.md](dock-window-preview.md) | Dock hover does not show window thumbnails |
| [shake-to-focus.md](shake-to-focus.md) | Shaking a window does not hide the others |
| [modifier-chip-tint.md](modifier-chip-tint.md) | Modifier chips do not look selected on older macOS |
| [apple-tv-battery-registry-cpu.md](apple-tv-battery-registry-cpu.md) | Idle Control Box pegs a CPU core when the Apple TV remote is attached |
| [poll-timer-cpu.md](poll-timer-cpu.md) | After the battery walk, idle Debug still sits at 10–20% CPU |
| [polling-loops.md](polling-loops.md) | Inventory of timers and system-API polls (start here when idle CPU or a loop looks wrong) |
