# Fix list

Open items for MX Master / HID++ work. MX Master 4 first.

## Done

- [x] **Stop the 3 s haptic rearm loop.** Divert once when HID++ setup succeeds.
- [x] **Retry only when the pipe drops** (HID removal, HID++ error `0x8F`, request timeout, detach). Fast retry: at most **3** attempts, **≥ 1 s** apart. Then **5 s** backoff.

## MX Master 4

- [x] Extra buttons (haptic, back, forward, mode shift) diverted once on MX4 attach
- [x] Haptic divert uses hold-only flags (no persist / force-raw-XY); native restore on quit
- [x] Do not open or seize the standard mouse HID collection
- [x] Pointer / wheel / thumb speed feel (slider 50% applies the old 25%)
- [x] MX4 sensor DPI + smooth scrolling (HiRes wheel), with settings controls
- [x] Haptic swipes keep 1000-DPI physical travel; pointer speed stays on its own slider.
- [x] BLE MX4 haptic is native HID button 7 (see `docs/mx-master-4-ble-haptic.md`)
- [ ] Confirm window-navigation actions fire on haptic hold + swipe without mid-swipe DockSwipe cancel/flicker
- [x] Split MX 3 / 3S / 4 into separate kinds; keep only MX4 HID++ attached for now

## Do not regress

- [ ] Never call `IOBluetoothDevice.pairedDevices()`
- [ ] Keep Apple Development signing (do not go back to ad-hoc)
- [ ] Two mice at once (3S + 4) — after MX4 is stable

## Later

- [ ] MX Master 3S reader (`0xFF43`, CID `0x00C3`)
- [ ] MX Master 3 reader
- [ ] Logi Options+ / LogiPluginService occupying HID++
