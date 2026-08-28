# Trackpad scroll feels laggy when an MX Master is attached

## Symptom

On a MacBook, two-finger trackpad scroll stutters or feels delayed once Pointer & Scroll is live (an MX Master is attached). MX wheel itself may also feel a notch behind.

## Cause

The system scroll tap rewrites every session scroll event so MX wheel speed and direction apply. Trackpad gestures are also continuous, same as an MX high-res wheel. The old 2-finger HID gesture probe often missed, so the tap scaled the trackpad like a mouse wheel.

A second `defaultTap` on the MX click probe also sat on `scrollWheel`, so each tick waited on two blocking taps on the main thread.

## What we changed

Pass through any scroll with a gesture `phase` or `momentumPhase` (trackpad and Magic Mouse). Keep MX wheel rewriting. Watch wheel motion for Calibration with a listen-only tap, not a second `defaultTap`.

## Do not

Apply wheel speed to events that have a scroll phase. Do not put `scrollWheel` back on the MX click `defaultTap`.
