# Haptic hold-to-swipe vs Back as Gestures

Parked 2026-08-22, reopened 2026-09-08 with capability-gated ownership. This file records why merely exposing a picker was insufficient. A button is now eligible only when its live Reprog descriptor is divertable and advertises raw XY; left/right remain excluded.

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

## What shipped after reopening

- Profiles separates **Gesture-capable controls** from ordinary **Buttons** using live Reprog flags.
- `MappingProfile` stores an independent `GestureSet` for each eligible control.
- `mxGestureOwners` may contain the gesture button, haptic button, Middle, Back, Forward, Mode shift, or generic Extra slots.
- Reader reporting changes between plain divert and raw-XY `0x33` as the active profile changes.
- The first held gesture owner owns unattributed raw XY; overlap motion is ignored.
- Default Back / Forward remain browser actions until the user promotes them.

Enforcement details: [gesture-owner-haptic-only.md](gesture-owner-haptic-only.md).

## Do not

- Treat a button as gesture-capable when its control descriptor does not advertise raw XY.
- HID++-divert left/right (`0x0050` / `0x0051`) for gestures. That can steal the pointer.
- Assume pad and desk-laser motion feel identical. Back/Forward/Middle gesture feel still needs hardware validation on every family that advertises raw XY.
