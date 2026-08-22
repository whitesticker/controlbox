# HID++ divert can steal the system pointer

## Symptom

HID / sidebar shows the MX Master as connected, but the cursor does not move. Quitting the app is not enough. Power-cycling the mouse restores movement.

## Cause

HID++ **divert** tells firmware to send a control to software instead of (or in addition to) native HID.

We armed the Master 4 haptic control (`0x01A0`) with flags around `0x33` (divert + persist + raw/force-XY style bits). That can make **all** movement come in as HID++ raw XY. macOS then gets no normal mouse X/Y.

Persist means the firmware can keep that mode after the app quits. A power cycle clears it.

Opening the normal Logitech mouse HID collection at launch can also steal the pointer while the app is running, even without persist.

## What we changed

- Stopped opening the mouse collection on launch
- Stopped seizing HID++
- Weakened or removed persist / force-raw-XY on quit
- On terminate, try to send divert flags `0` so firmware returns to native reporting

## Tradeoff

Safer flags keep the pointer alive but extra buttons and haptic gestures often stop reporting. That is the same mechanism, not a second mystery.

## Do not

Send persist or force-raw-XY on MX Master 4 while we are still stabilizing the pointer.
