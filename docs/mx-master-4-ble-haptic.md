# MX Master 4 over Bluetooth LE: haptic is a normal mouse button

## Symptom

Calibration and HID++ divert never saw the haptic pad. Extra buttons could light up. Hold-to-swipe did nothing. A listen-only HID++ matcher on usage page `0xFF00` never found the mouse.

## What the machine actually exposes

Captured 2026-08-22 on this Mac with `tools/hidpp-sniff.swift` (no seize).

The MX Master 4 is **Bluetooth Low Energy**, product ID `0xB042`. It does **not** appear as a separate Logitech HID++ collection.

| Device | Product ID | Primary collection | Notes |
|---|---|---|---|
| USB Receiver (Bolt) | `0xC548` | `0xFF00` plus keyboard / mouse | Receiver HID++ slots are not this MX4. Slot 1 looked like a keyboard (no `0x01A0`). |
| MX Master 4 | `0xB042` | Mouse `0x01` / `0x02` over BLE | Vendor HID++ is **nested** on this same device. |

### Nested HID++ (page `0xFF43`, report `0x11`)

The BLE report descriptor includes usage page `0xFF43` (same family as MX Master 3S) with **report ID `0x11`**: 19 data bytes in, 19 out. That is a HID++ long report on the mouse device, not a second `IOHIDDevice`.

Pings on that report get replies at device index `0xFF` and `0x00`. There is no short report `0x10` on this descriptor.

### Haptic pad (report `0x02`, button 7)

The same descriptor’s mouse report (`0x02`) has **7 buttons**. The haptic thumb pad is bit `0x40` (HID button 7).

While held, X/Y stay on that mouse report (12-bit X, then 12-bit Y). A tap is `02 40 …` then `02 00 …`. A hold-and-move keeps `0x40` set and changes the X/Y fields. No Reprog CID `0x01A0` is required for press or swipe on BLE.

CGEvent `otherMouse` button number **6** is the same pad (0 = left).

## Why the app missed it

VibeRemote only opened Logitech collections whose **primary** usage page was `0xFF00`, and treated product `0xC548` as “not an MX Master 4.” On BLE there is no such collection. Diverting `0x01A0` on the Bolt receiver talked to the wrong device.

Opening the standard mouse collection **only to watch buttons** can still steal the pointer. Reading report `0x02` / `0x11` without seize did not, in this capture. Earlier pointer-death was persist / force-raw-XY divert, not this report layout.

## What to do

- Match BLE MX4 by product `0xB042`, not by a standalone `0xFF00` device.
- Treat haptic as HID button 7 / CG button 6. Accumulate X/Y from report `0x02` while that bit is down.
- Talk HID++ on report `0x11` of that same device when extra firmware features are needed.
- Do not assume Bolt receiver slot 1 is the MX4. Walk slots and read the name.
- Keep `tools/hidpp-sniff.swift` for the next capture. Kill it when done so it does not hold the device.

## Related

- [mx-master-4-pointer-and-haptic.md](mx-master-4-pointer-and-haptic.md) — pointer vs haptic sliders, live swipe, tap delay
- [extra-buttons-missing-in-calibration.md](extra-buttons-missing-in-calibration.md)
- [hidpp-divert-steals-pointer.md](hidpp-divert-steals-pointer.md)
- [mx-master-3s-wrong-usage-page.md](mx-master-3s-wrong-usage-page.md)
