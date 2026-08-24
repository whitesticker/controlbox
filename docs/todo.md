# Fix list

Open items for MX Master / HID++ work. 3S and 4 can stay attached at once (separate HID++ readers).

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
- [x] 100ms arm delay so a haptic tap is not a swipe (see `docs/haptic-tap-starts-swipe.md`)
- [x] App Exposé is a discrete down-swipe, not live DockSwipe (see `docs/dockswipe-down-skips-app-expose.md`)
- [x] Media gesture left/right fires previous/next track (see `docs/media-gesture-skip-dead.md`)
- [x] Haptic pad is the only Gestures owner (click-as-gesture on Back / etc. is parked; see `docs/haptic-vs-back-gesture.md`)
- [ ] Watch for mid-swipe DockSwipe flicker after the 100ms arm delay (absolute progress + teleport reject are in; 180ms release debounce is not)
- [x] Split MX 3 / 3S / 4 into separate kinds; keep only MX4 HID++ attached for now
- [x] MX Master 3 / 3S reader (same CID table; BLE `0xB034` measured). Separate module from MX4.

## Do not regress

- [ ] Never call `IOBluetoothDevice.pairedDevices()`
- [ ] Keep Apple Development signing (do not go back to ad-hoc)
- [x] Two mice at once (3S + 4) — isolated HID++ readers; still needs a 3S+4 hardware pass
- [x] Device family sessions (DualSense, Apple TV A2540); host no longer owns those readers

## Later

- [ ] Confirm Unifying MX Master 3 (`0x4082`) if one shows up — same module, untested radio
- [ ] Logi Options+ / LogiPluginService occupying HID++
- [ ] Click-as-gesture on Back / Forward / etc. (desk laser, not the pad). Parked; haptic only for now.
- [ ] Per-app mouse Control profiles (frontmost app switches mappings). Product item in [roadmap.md](roadmap.md).

Product-facing work (mic, live gesture HUD, MX4 extra button, MX Keys, calibration art, MX4 swipe feel, onboarding, menu bar circle, per-app mouse profiles) lives in [roadmap.md](roadmap.md). DualSense BT mic probe (not in the app): [dualsense-bluetooth-mic.md](dualsense-bluetooth-mic.md). Media skip / play / mute already show an action HUD.
