# HID++ divert can steal the system pointer

## Symptom

HID / sidebar shows the MX Master as connected, but the cursor does not move. Quitting the app is not enough. Power-cycling the mouse restores movement.

## Cause

HID++ **divert** tells firmware to send a control to software instead of (or in addition to) native HID.

We misread HID++ `setCidReporting` flags. On Reprog Controls V4, each setting is a **value bit plus a valid bit**:

- `0x33` = divert + divert-valid + raw-XY + raw-XY-valid (hold-only gestures). This is what Solaar sends.
- Persist is `0x04` / valid `0x08`. Force raw XY is `0x40` / valid `0x80`.
- Sending `0` to undo does nothing (valid bits are 0). Clear with `0x22`.
- A 6th “mask” byte can confuse Master 4 (feature V6). The packet is 5 bytes: CID, flags, remap.

Persist means the firmware can keep that mode after the app quits. A power cycle clears it.

Opening the normal Logitech mouse HID collection at launch can also steal the pointer while the app is running, even without persist.

## What we changed

- Stopped opening the mouse collection on launch
- Stopped seizing HID++
- Weakened or removed persist / force-raw-XY on quit
- On terminate, send flags `0x22` (clear divert + raw XY with valid bits). Sending `0` does nothing.

## Tradeoff

Safer flags keep the pointer alive but extra buttons and haptic gestures often stop reporting. That is the same mechanism, not a second mystery.

## Do not

Send persist or force-raw-XY on MX Master 4 while we are still stabilizing the pointer.
