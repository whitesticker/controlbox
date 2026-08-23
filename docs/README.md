# VibeRemote problem log

One issue type per file. These are failures we already hit while working on DualSense, Apple TV remote, and MX Master support.

Working model (read this first for MX4 feel): [mx-master-4-pointer-and-haptic.md](mx-master-4-pointer-and-haptic.md).

| File | Symptom |
|---|---|
| [bluetooth-paired-devices-heap-corruption.md](bluetooth-paired-devices-heap-corruption.md) | App crashes on launch or while listing devices |
| [hid-open-seize-dual-mouse.md](hid-open-seize-dual-mouse.md) | Crash or dead input with two Logitech mice |
| [hidpp-divert-steals-pointer.md](hidpp-divert-steals-pointer.md) | Pointer dies until the mouse is power-cycled |
| [extra-buttons-missing-in-calibration.md](extra-buttons-missing-in-calibration.md) | Haptic / back / forward do not light up |
| [adhoc-signing-resets-tcc.md](adhoc-signing-resets-tcc.md) | Accessibility / Input Monitoring must be re-added every build |
| [mx-master-3s-wrong-usage-page.md](mx-master-3s-wrong-usage-page.md) | 3S never attaches while Master 4 does |
| [mx-master-4-ble-haptic.md](mx-master-4-ble-haptic.md) | BLE MX4 haptic/HID++ live on the mouse report, not `0xFF00` |
| [haptic-swipe-scales-with-dpi.md](haptic-swipe-scales-with-dpi.md) | High DPI makes hold-to-swipe much faster than 1000 DPI |
| [dockswipe-down-skips-app-expose.md](dockswipe-down-skips-app-expose.md) | Swipe down never opens App Exposé |
| [haptic-tap-starts-swipe.md](haptic-tap-starts-swipe.md) | A tap also peeks Spaces or Mission Control |
| [dockswipe-progress-snapback.md](dockswipe-progress-snapback.md) | Spaces / Mission Control jump backward mid-swipe |
| [media-gesture-skip-dead.md](media-gesture-skip-dead.md) | Media left/right does not skip tracks |

Open work: [todo.md](todo.md).

HID primer and “should we drop HID++?” live in chat and `AGENTS.md`, not here. This folder is incident notes, the MX4 working model, plus that list.
