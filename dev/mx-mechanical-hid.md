# MX Mechanical HID++ is on the BLE keyboard device

Shipped 2026-08-31. Live hardware was **MX Mechanical Mini** over Bluetooth, product **`0xB367`**, name **MX MCHNCL M**. Full-size Mechanical is **`0xB366`**.

This family is settings-only: backlight, lighting effect, battery saving, battery %. No key divert, no remapping, no **Control this Mac**.

## What the machine exposes

| Device | Product ID | Primary collection | Notes |
|---|---|---|---|
| MX Mechanical | `0xB366` | Keyboard `0x01` / `0x06` | Not on this Mac; same HID++ features as Mini. |
| MX Mechanical Mini | `0xB367` | Keyboard `0x01` / `0x06` | Vendor HID++ is **nested** on this same device (report `0x11`). |
| USB Receiver (Bolt) | `0xC548` | `0xFF00` plus keyboard / mouse | **Not** the keyboard. Do not open it. Slots: [logi-bolt-receiver.md](logi-bolt-receiver.md). |

`0xB366` is this keyboard, not MX Master 4. `MXMaster4Support.productIDs` must stay `[0xB042, 0x4069]`.

There is no separate `0xFF00` collection. Match product IDs only. Do not treat non-`0x10` / `0x11` reports as HID++.

## HID++ features we use

| Feature | ID | What |
|---|---|---|
| Device Name | `0x0005` | Sidebar label |
| Unified Battery | `0x1004` | Percent; 30 s while HID++ is ready |
| Backlight2 | `0x1982` | On/off, lighting effect, battery saving |

Effects: Static, Breathing, Contrast, Reaction, Random, Waves. Firmware **None** stays hidden unless the keyboard is already on it.

## Do not

- Divert keys (Solaar #2824). The keyboard stays a normal Mac keyboard.
- Seize HID. Do not open Bolt `C548`.
- Call `IOBluetoothDevice.pairedDevices()`.
- Block the UI on `IOHIDDeviceSetReport`. Backlight toggle and effect picker publish first, write on a serial IO queue, and do not read the keyboard back after every write.
- Offer “Use F1, F2 as standard function keys”. Firmware `K375S FN INVERSION` `0x40A3` exists but Mini often replies with software ID 0, and the control froze mid-click.

Logi Options+ / LogiPluginService can hold the HID++ pipe. Quit those if the device page stays disconnected.

## Code split

- `MXMechanicalSupport` — product IDs `0xB366` / `0xB367`
- `MXKeyboardReader` — HID++ settings client
- `MXKeyboardSession` — `DeviceFamilySession`
- Host (`DualSenseMonitor`) is records and the poll loop. Do not add `captureKeyboard()`-style I/O on the host beyond copying the snapshot.

MX Keys and key remapping are still open ([roadmap.md](roadmap.md)).

## Related

- [logi-bolt-receiver.md](logi-bolt-receiver.md) — do not attach `C548` from this matcher
- [polling-loops.md](polling-loops.md) — 30 s battery, not 120 Hz
- [hid-open-seize-dual-mouse.md](hid-open-seize-dual-mouse.md)
