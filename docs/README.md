# VibeRemote problem log

One issue type per file. These are failures we already hit while working on DualSense, Apple TV remote, and MX Master support.

| File | Symptom |
|---|---|
| [bluetooth-paired-devices-heap-corruption.md](bluetooth-paired-devices-heap-corruption.md) | App crashes on launch or while listing devices |
| [hid-open-seize-dual-mouse.md](hid-open-seize-dual-mouse.md) | Crash or dead input with two Logitech mice |
| [hidpp-divert-steals-pointer.md](hidpp-divert-steals-pointer.md) | Pointer dies until the mouse is power-cycled |
| [extra-buttons-missing-in-calibration.md](extra-buttons-missing-in-calibration.md) | Haptic / back / forward do not light up |
| [adhoc-signing-resets-tcc.md](adhoc-signing-resets-tcc.md) | Accessibility / Input Monitoring must be re-added every build |
| [mx-master-3s-wrong-usage-page.md](mx-master-3s-wrong-usage-page.md) | 3S never attaches while Master 4 does |
| [mx-master-4-ble-haptic.md](mx-master-4-ble-haptic.md) | BLE MX4 haptic/HID++ live on the mouse report, not `0xFF00` |

Open work: [todo.md](todo.md).

HID primer and “should we drop HID++?” live in chat and `AGENTS.md`, not here. This folder is incident notes plus that list.
