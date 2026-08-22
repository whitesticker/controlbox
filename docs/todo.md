# Fix list

Open items for MX Master / HID++ work. MX Master 4 first.

## Done

- [x] **Stop the 3 s haptic rearm loop.** Divert once when HID++ setup succeeds.
- [x] **Retry only when the pipe drops** (HID removal, HID++ error `0x8F`, request timeout, detach). Fast retry: at most **3** attempts, **≥ 1 s** apart. Then **5 s** backoff.

## MX Master 4

- [ ] Extra buttons (haptic, back, forward, mode shift) in Calibration
- [ ] Haptic hold + swipe for window navigation, without stealing the pointer
- [ ] Divert without persist / force-raw-XY; restore native reporting on quit
- [ ] Do not open or seize the standard mouse HID collection
- [ ] Pointer / wheel / thumb speed feel (slider remap is in; revisit if still wrong)
- [ ] Split MX 3 / 3S / 4 into separate readers; keep only MX4 attached for now

## Do not regress

- [ ] Never call `IOBluetoothDevice.pairedDevices()`
- [ ] Keep Apple Development signing (do not go back to ad-hoc)
- [ ] Two mice at once (3S + 4) — after MX4 is stable

## Later

- [ ] MX Master 3S reader (`0xFF43`, CID `0x00C3`)
- [ ] MX Master 3 reader
- [ ] Logi Options+ / LogiPluginService occupying HID++
