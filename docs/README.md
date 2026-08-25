# VibeRemote problem log

One issue type per file. These are failures we already hit while working on DualSense, Apple TV remote, and MX Master support.

## Read in this order (MX Master)

0. [mx-master-3s-hid.md](mx-master-3s-hid.md) — current 3S hardware: BLE `0xB034`, nested `0xFF43` / `0x11`, CID `0x00C3`.

1. [mx-master-4-pointer-and-haptic.md](mx-master-4-pointer-and-haptic.md) — current working model: sliders, defaults, haptic pipeline, what not to do.
2. [mx-master-4-ble-haptic.md](mx-master-4-ble-haptic.md) — BLE hardware: report `0x02` button 7, nested HID++ `0x11`.
3. [haptic-vs-back-gesture.md](haptic-vs-back-gesture.md) — why Gestures is haptic-only; what we tried on Back.
4. [todo.md](todo.md) — HID / MX fix list.
5. [roadmap.md](roadmap.md) — product backlog (mic, HUD, MX Keys, onboarding, menu bar icon).

HID primer and “should we drop HID++?” live in chat and `AGENTS.md`. This folder is incident notes, the MX4 working model, plus that list.

## Incident notes

| File | Symptom |
|---|---|
| [bluetooth-paired-devices-heap-corruption.md](bluetooth-paired-devices-heap-corruption.md) | App crashes on launch or while listing devices |
| [hid-open-seize-dual-mouse.md](hid-open-seize-dual-mouse.md) | Crash or dead input with two Logitech mice |
| [hidpp-divert-steals-pointer.md](hidpp-divert-steals-pointer.md) | Pointer dies until the mouse is power-cycled |
| [extra-buttons-missing-in-calibration.md](extra-buttons-missing-in-calibration.md) | Haptic / back / forward do not light up |
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
| [media-gesture-skip-dead.md](media-gesture-skip-dead.md) | Media left/right does not skip tracks |
| [gesture-owner-haptic-only.md](gesture-owner-haptic-only.md) | Gestures is haptic-pad only (enforcement) |
| [haptic-vs-back-gesture.md](haptic-vs-back-gesture.md) | Click-as-gesture on Back is parked (why) |
| [ddc-identity-from-wrong-framebuffer.md](ddc-identity-from-wrong-framebuffer.md) | Displays lists an extra monitor; a named slider does not drive that panel |
| [process-tap-exclusive.md](process-tap-exclusive.md) | Per-app volume does nothing while FineTune or another tap mixer is open |
| [apple-tv-battery-registry-cpu.md](apple-tv-battery-registry-cpu.md) | Idle VibeRemote pegs a CPU core when the Apple TV remote is attached |
| [poll-timer-cpu.md](poll-timer-cpu.md) | After the battery walk, idle Debug still sits at 10–20% CPU |
