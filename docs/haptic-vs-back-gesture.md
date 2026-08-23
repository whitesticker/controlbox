# Haptic hold-to-swipe vs Back as Gestures

Parked 2026-08-22. Only the haptic pad is a Gestures owner. This file is the full record of why click-as-gesture did not ship.

## Hardware

These are not the same control.

| | Haptic pad | Back (and other clicks) |
|---|---|---|
| What it is | Force-sensing thumb pad | A click. Back is CID `0x0053`, often CG `otherMouse` button 3. Forward `0x0054` / `0x0056`. |
| Hold bit | Report `0x02` button 7 (`0x40`) on the same packet as X/Y | Separate HID++ notify or `otherMouse` |
| X/Y while held | 12-bit X then Y on that same `0x02` report. Finger on the pad **is** the sensor. | **No pad.** The only X/Y is the mouse laser (slide the whole mouse) on report `0x02`. Swiping the thumb pad while Back is down usually sends **no** pad XY unless the haptic bit is also down. |

Hold haptic + move the thumb = designed gesture. Hold Back + move the thumb on the pad = often no direction. Hold Back + move the mouse on the desk = same XY stream the pointer uses.

That last case is not a second haptic pad. Laser counts are larger, Y is often opposite the pad, and warping the cursor to freeze it fights the only motion the click has.

## What we tried

The UI already had a Gestures assignment on every MX button. Wiring it so Back actually started a session exposed a stack of failures. None of these made live Spaces follow the hand.

1. **Engine required `snapshot.back` to stay true.** HID++ `applyPressed` rewrote that map and killed the hold mid-swipe.
2. **HID++ `pressed = next` ended Back** when a later notify had an empty or different CID list. Finger still down. Next press never came. Felt stuck.
3. **Hold latch (`cg` + `hidpp`).** Session ended only when both sources said up. Fixed stuck; did not fix follow or direction.
4. **Warping the cursor every poll** while Back was held. The laser *is* the swipe. Warp fought the hand. Sticky, wrong direction.
5. **Same pad speed factor and pad signs (`-y`)** applied to laser XY. Laser counts overshoot; Y is often flipped vs the pad.
6. **Report `0x02` 12-bit *and* HID usages `0x30` / `0x31`** both added into the same delta. Double-count / mixed signs.
7. **`ButtonHoldGesture`** as a second interpreter: larger desk-motion thresholds, 2.2× DockSwipe spans, inverted capture (`-dx`, `-dy`), separate `buttonGestureSpeedFactor` (about 0.32× at 50% / 1000 DPI). Swipe would **activate** (axis lock / session start) but **not control** — the 2.2× span meant the hand never filled the follow. Direction still felt wrong.
8. **Media used a stricter axis lock than the pad** for a while. Another reason left/right felt dead.

Conclusion: this is a different sensor. It needs a laser-specific module that actually follows, not pad math with a scale tweak. That is not close. Parked.

## What shipped instead

- Profiles: Gestures picker only on **Haptic**.
- `MappingProfile.setBinding` / `setGestureSet` / `gestureSet(for:)` refuse non-haptic Gestures.
- `mxGestureOwners` is `{.mxHaptic}` or empty.
- Load-time `restrictGesturesToHapticPad()` rewrites saved Back-as-Gestures (etc.) to ordinary clicks.
- Reader `setGestureOwners` intersects with `{.mxHaptic}`.
- Engine `processGesture` starts `HoldGesture` only for haptic.
- `ButtonHoldGesture` and the Button gesture speed slider were removed.
- Extra buttons stay normal bindings (default Back / Forward = browser).

Enforcement details: [gesture-owner-haptic-only.md](gesture-owner-haptic-only.md).

## Do not

- Treat Back as a second haptic pad.
- HID++-divert left/right/middle (`0x0050` / `0x0051` / `0x0052`) to invent XY. That steals the pointer.
- Re-enable Gestures on non-haptic MX buttons until a laser-specific path actually follows the hand (correct signs, one XY source, spans that track, no cursor warp fighting the laser).
- Reuse `HoldGesture` pad thresholds / `-y` / `gestureSpeedFactor` for desk motion.
