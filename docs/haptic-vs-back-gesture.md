# Haptic hold-to-swipe vs Back as Gestures

Parked: only the haptic pad is a Gestures owner. This file is why click-as-gesture did not ship.

## Hardware

These are not the same control.

| | Haptic pad | Back button |
|---|---|---|
| What it is | Force-sensing thumb pad | A click (CID `0x0053`, often CG button 3) |
| Hold bit | Report `0x02` button 7 (`0x40`) on the same packet as X/Y | Separate HID++ notify or `otherMouse` |
| X/Y while held | 12-bit X then Y on that same `0x02` report. Finger on the pad **is** the sensor. | **No pad.** The only X/Y is the mouse laser (move the whole mouse) on report `0x02`. Swiping the thumb pad while Back is down usually sends **no** pad XY unless the haptic bit is also down. |

Hold haptic + move the thumb = designed gesture. Hold Back + move the thumb on the pad = often no direction. Hold Back + move the mouse on the desk = same XY stream the pointer uses.

That last case is not a second haptic pad. Laser counts, signs, and live-follow spans are different from the pad. Compensation never settled (activate without control, wrong direction).

## Do not

Treat Back as a second haptic pad. Do not HID++-divert left/right/middle to invent XY. Do not re-enable Gestures on non-haptic MX buttons until there is a laser-specific module that actually follows the hand.
