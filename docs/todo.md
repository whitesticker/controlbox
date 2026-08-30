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
- [x] MX4 Side button CID `0x00C3` (not the 3S gesture; divert `0x03`). See [extra-buttons-missing-in-calibration.md](extra-buttons-missing-in-calibration.md).
- [x] MX4 left / right / wheel in Calibration (report `0x02` + one shared click tap). See [mx4-clicks-missing-in-calibration.md](mx4-clicks-missing-in-calibration.md).
- [x] Focused Control Box does not inject (including system-nav gestures). See [focused-host-still-injects.md](focused-host-still-injects.md).
- [x] Wheel / thumb remappable per direction; `.scroll` keeps native.

## Do not regress

- [ ] Never call `IOBluetoothDevice.pairedDevices()`
- [ ] Keep Apple Development signing (do not go back to ad-hoc)
- [x] Two mice at once (3S + 4) — isolated HID++ readers; still needs a 3S+4 hardware pass
- [x] Device family sessions (DualSense, Apple TV A2540); host no longer owns those readers
- [x] Displays pane lists one row per `NSScreen` (no leftover DDC ghost). Apple-silicon DDC matching follows MonitorControl (MIT); credit is on the Displays page (see [ddc-identity-from-wrong-framebuffer.md](ddc-identity-from-wrong-framebuffer.md)).
- [x] Sound pane: system output + per-app volume via Apple process tap (no FineTune / Background Music code). Two tap mixers cannot own the same app; Sound warns if FineTune / SoundSource / etc. is already running (see [process-tap-exclusive.md](process-tap-exclusive.md)). MacBook speakers use a tap-only aggregate plus HALOutput; do not drive speaker IO from the tap (see [macbook-app-volume-binary.md](macbook-app-volume-binary.md), [macbook-app-volume-system-lag.md](macbook-app-volume-system-lag.md)).

## Later

- [ ] Confirm Unifying MX Master 3 (`0x4082`) if one shows up — same module, untested radio
- [ ] Logi Options+ / LogiPluginService occupying HID++
- [ ] Click-as-gesture on Back / Forward / etc. (desk laser, not the pad). Parked; haptic only for now.
- [ ] Per-app mouse Control profiles (frontmost app switches mappings). Product item in [roadmap.md](roadmap.md).

Product-facing work (mic, live gesture HUD, MX Keys, calibration art, MX4 swipe feel, onboarding, menu bar circle, per-app mouse profiles) lives in [roadmap.md](roadmap.md). MX4 Side is shipped. Media skip / play / mute already show an action HUD.
