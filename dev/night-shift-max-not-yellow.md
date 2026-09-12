# Night Shift top of curve is not System Settings max yellow

## Symptom

Dragging a knot to the top of the Yellowness chart (100% / 2700 K in the Now line) still leaves headroom in System Settings → Displays → Night Shift → Color Temperature. Dragging that slider toward **More Warm** makes the screen yellower.

## Cause

`CBBlueLightClient` max is strength `1.0` / `getCCTRange.min` (2700 K on this Mac). Take-over treated any strength within **0.03** of the curve as already applied (`isHolding`), then stored `lastApplied` as 1.0 anyway. A 0.979 leftover from the evening ramp never got pushed to 1.0, so System Settings still had travel.

Dragging a knot a few pixels shy of the top also stored ~96% instead of the warm rail.

## What we changed

Do not skip apply unless strength is actually at the target (0.002), and at the top require strength ≥ 0.995 and CCT within 8 K of the range minimum. Snap editor drags onto the cool/warm rails so the top of the chart is Night Shift maximum.

## Do not

Treat a 3% strength miss as “already yellow.” Do not call `setCCT` below `getCCTRange.min` — CoreBrightness clamps there; that is also System Settings **More Warm**. Extra yellow past 2700 K is display gamma; see [night-shift-beyond-apple-yellow.md](night-shift-beyond-apple-yellow.md).
