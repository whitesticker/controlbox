# Fix list

Open items for MX Master / HID++work. 3S and 4 can stay attached at once (separate HID++ readers).

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
- [x] BLE MX4 haptic is native HID button 7 (see `mx-master-4-ble-haptic.md`)
- [x] 100ms arm delay so a haptic tap is not a swipe (see `haptic-tap-starts-swipe.md`)
- [x] App Exposé is a discrete down-swipe, not live DockSwipe (see `dockswipe-down-skips-app-expose.md`)
- [x] Media gesture left/right fires previous/next track (see `media-gesture-skip-dead.md`)
- [x] Gestures owners are capability-gated (divertable + raw XY). Defaults are the gesture button and MX4 haptic button. See [gesture-owner-haptic-only.md](gesture-owner-haptic-only.md).
- [ ] Watch for mid-swipe DockSwipe flicker after the 100ms arm delay (absolute progress + teleport reject are in; 180ms release debounce is not)
- [x] Live Space swipe commits the nearest desktop, not a reverse-tick cancel (see [dockswipe-commit-nearest.md](dockswipe-commit-nearest.md))
- [x] Split MX 3 / 3S / 4 into separate kinds; keep only MX4 HID++ attached for now
- [x] MX Master 3 / 3S reader (same CID table; BLE `0xB034` measured). Separate module from MX4.
- [x] MX4 **gesture button** CID `0x00C3` (same thumb button as 3S). Divert `0x33` when it owns Gestures; do not pin. See [extra-buttons-missing-in-calibration.md](extra-buttons-missing-in-calibration.md), [mx4-gesture-button-freezes-pointer.md](mx4-gesture-button-freezes-pointer.md).
- [x] MX4 left / right / wheel in Calibration (report `0x02` + one shared click tap). See [mx4-clicks-missing-in-calibration.md](mx4-clicks-missing-in-calibration.md).
- [x] Focused Control Box does not inject (including system-nav gestures). See [focused-host-still-injects.md](focused-host-still-injects.md).
- [x] Main wheel stays native vertical scroll; thumb wheel uses one delta-driven mode and old direction bindings migrate. See [mx-wheel-modes.md](mx-wheel-modes.md).
- [x] Main wheel must not pulse the thumb mapping (dominant axis + HID++ thumb). See [mx-wheel-fires-thumb.md](mx-wheel-fires-thumb.md).



## Do not regress

- [ ] Never call `IOBluetoothDevice.pairedDevices()`
- [ ] Keep Apple Development signing (do not go back to ad-hoc)
- [x] Two mice at once (3S + 4) — isolated HID++ readers; still needs a 3S+4 hardware pass
- [x] Device family sessions (DualSense, Apple TV A2540); host no longer owns those readers
- [x] Displays pane lists one row per `NSScreen` (no leftover DDC ghost). Apple-silicon DDC matching follows MonitorControl (MIT); credit is on the Displays page (see [ddc-identity-from-wrong-framebuffer.md](ddc-identity-from-wrong-framebuffer.md)).
- [x] Sound pane: system output + per-app volume via Apple process tap (no FineTune / Background Music code). Two tap mixers cannot own the same app; Sound warns if FineTune / SoundSource / etc. is already running (see [process-tap-exclusive.md](process-tap-exclusive.md)). Tahoe: tap-only + HALOutput. Sequoia 15: stacked speaker clock + IOProc gain, and do not rebuild taps on `!obj` (see [macbook-app-volume-binary.md](macbook-app-volume-binary.md), [macbook-app-volume-system-lag.md](macbook-app-volume-system-lag.md)).



## Later

- [x] Logi Bolt pair / unpair: **Add Device → Logi Bolt** lists Online / Not connected per receiver; Add discovers advertising devices, then mouse click string or keyboard passkey. Bolt-only MX / Mechanical talk uses the same vendor HID++ pipe. See [logi-bolt-receiver.md](logi-bolt-receiver.md).
- [ ] Confirm Unifying MX Master 3 (`0x4082`) if one shows up — same module, untested radio
- [ ] Logi Options+ / LogiPluginService occupying HID++
- [ ] Back / Forward / Middle as Gestures still need a laser-follow pass on each family that advertises raw XY. Do not treat them as a second haptic pad. See [haptic-vs-back-gesture.md](haptic-vs-back-gesture.md).
- [x] Per-app mouse Control profiles (frontmost app switches mappings). Design: [per-app-mouse-profiles.md](per-app-mouse-profiles.md).
- [x] **Delete device does not leave the sidebar.** Removing a device drops that **sidebar** row (and its remembered record) even if it is still connected.
- [x] **Device management and onboarding.** Add Device: **Add** when there is no Control Box page, **Settings** when there is. Connected hardware is not on the sidebar until Add. Product shape is in [roadmap.md](roadmap.md).



## Logitech-related improvements

Do not become Options+. Do not divert left/right. Do not list the Bolt dongle as a device.

- [x] **More Logitech HID++ mice** — capability-driven `LogitechMouseReader` plus audited discovery; not an MX-only product-ID allowlist. Non-Logitech mice are later. See [logitech-generic-hidpp.md](logitech-generic-hidpp.md).
- [x] **Logi Bolt — talk** — one catalog owns `C548` vendor HID++ only; walk slots 1–6; prefer BLE if both radios are up; MX4 haptic from HID++ (not report `0x02`). Same Easy-Switch unit is one sidebar row.
- [x] **Easy-Switch channels** — MX mouse and keyboard **device pages** list three channels from `0x1814` / `0x1815` (BLE or Bolt). Section stays up with **Pending**; **Refresh** re-reads. No forget-host UI.
- [x] **Logi Bolt — pair** — **Add Device** sheet, Bluetooth / Logi Bolt panels (discover list / passkey / unpair). Occupied slots split Online / Not connected. Not Other. Not a Devices sidebar row.
- [ ] **Unifying / Lightspeed** — same slot walk as Bolt; Unifying pairing can be another Add Device tab later.
- [ ] **Restore original divert** — read flags before divert; put those back on quit / failed start (not a blanket `0x22`).
- [x] **One HID++ pipe, two addresses** — BLE = nested `0xFF43` on the mouse; Bolt = slot on `C548`. Same catalog pipe; readers do not open the dongle.
- [ ] **Detect Options+ / LogiPluginService** — say so up front, not only after HID++ timeout.
- [ ] **Software-ID lease on a shared dongle** — required when two sessions share `C548`.
- [x] **Per-app mouse profiles** — MX device page **profile tiles**; live mapping follows the frontmost app. See [per-app-mouse-profiles.md](per-app-mouse-profiles.md).
- [x] **SmartShift as a wheel setting** — firmware `0x2111` (fallback `0x2110`) on Calibration: Free Spin / Ratchet plus sensitivity. See [mx-smartshift.md](mx-smartshift.md). Mode Shift stays a mappable button.
- [ ] **Keyboard remapping, carefully** — divert only bound keys; do not divert MX Mechanical keys.
- [x] **Thumb-wheel smooth travel** — Pointer & Scroll Smooth scrolling eases diverted thumb HID++ for every thumb mode (100 ms cubic, pixel-continuous scroll). Main-wheel intercept is still open; see [roadmap.md](roadmap.md).
- [ ] **Smooth-scroll animation (main wheel)** — keep hi-res firmware; intercept native line ticks (not trackpad) and feed the same interpolator.
- [x] **Devices sidebar by type, then brand** — sections Mouse / Gamepad / Remote / Keyboard / Other. Brand is a row caption until a type has two brands. Hide empty types. Connection is a caption (`Logitech · Bluetooth` / `Logitech · Bolt`), not a type.

## CI

Unsigned Debug compile on GitHub Actions plus hard-constraint greps. One job is better than none. Do not upload the `.app`.

- [x] **Compile check** — `xcodebuild` Debug, `CODE_SIGNING_ALLOWED=NO` (local Debug stays Apple Development).
- [x] **Constraint greps** — `pairedDevices()`, ad-hoc `CODE_SIGN_IDENTITY`, Logitech HID seize (Apple TV seize is still allowed).
- [x] **Unit tests** — ControlBoxCore XCTest for HID++ encoding, capabilities, and gesture-owner migration. CI runs `swift test --package-path Packages/ControlBoxCore`.
- [ ] **Release configuration** — CI is Debug-only today; add a Release build so shipping flags get compiled too.
- [ ] **Pin Xcode** — lock the runner image / Xcode version so a silent GitHub image bump does not fail `main` overnight.

Product-facing work (mic, live gesture HUD, MX Keys remapping, generic non-Logitech mapper, window management extras, Dropover-style shelf, PopClip-style selection bar, calibration art, MX4 haptic swipe feel, product page, settings export, Pointer & Scroll vs System Settings, Sound per-app icons) lives in [roadmap.md](roadmap.md). MX Mechanical settings, MX4 gesture button, Caps Lock, window management, Dock Previews, per-app mouse and DualSense profiles, SmartShift, thumb-wheel sensitivity, and Add Device onboarding are shipped. Media skip / play / mute already show an action HUD.