# Logi Bolt: the mouse is a slot on `C548`, not a BLE product ID

Investigated 2026-08-31. No live Bolt capture on this Mac yet (receiver not plugged in). Product item: [roadmap.md](roadmap.md).

Control Box talks to MX mice as **their own Bluetooth HID devices**. A mouse that is on only through Logi Bolt never matches. Adding `0xB043` to the 3S product-ID set does not fix that.

## What the USB device actually is

The dongle is Logitech vendor `0x046D`, product **`0xC548`**. It is a 6-slot multiplexer. Paired devices do **not** show up as IOKit product IDs `0xB034` / `0xB042` / `0xB043`.

Linux Solaar dumps of MX Master 4 and 3S on Bolt look the same: USB id `046d:C548`, mouse `Device path: None`, HID++ addressed by **slot** (often not slot 1). MX4’s wireless ID on Bolt is still **`B042`** (same as BLE). 3S Bolt WPID is listed as `B043` in some tables and `B034` in others; either way it is a pairing ID, not an `IOHIDDevice` product ID.

This Mac already saw `C548` while MX4 was on BLE (2026-08-22, `tools/hidpp-sniff.swift`, no seize):

| Device | Product ID | Primary collection | Notes |
|---|---|---|---|
| USB Receiver (Bolt) | `0xC548` | `0xFF00` plus keyboard / mouse | HID++ slots are whoever is paired. Slot 1 was a keyboard (no `0x01A0`). |
| MX Master 4 | `0xB042` | Mouse `0x01` / `0x02` over BLE | Nested HID++ on this device. Independent of the dongle. |

Diverting haptic CID `0x01A0` on the receiver talked to the keyboard. That is why matchers **never open `C548`** today. See [hid-open-seize-dual-mouse.md](hid-open-seize-dual-mouse.md), [mx-master-4-ble-haptic.md](mx-master-4-ble-haptic.md).

## What the app does today

| Path | Product IDs | Result on Bolt-only |
|---|---|---|
| MX 3/3S reader | `0xB023`, `0x4082`, `0xB034`, `0xB043` | No `IOHIDDevice` with those IDs |
| MX 4 reader | `0xB042`, `0x4069` | No `B042` device. `0x4069` is MX Master 2S’s Unifying WPID, not MX4 Bolt. |
| Discovery | MX product IDs, then drop `C548` | Receiver is discarded on purpose |

`LogitechMXMasterReader` already walks HID++ indices `0xFF`, `0x00`, then 1–6, then reads the device name and refuses a non-MX. That walk never runs on `C548`. BLE MX4 haptic still comes from native report `0x02` bit `0x40` on the **same** device as HID++ ([mx-master-4-ble-haptic.md](mx-master-4-ble-haptic.md)).

## Feasible shape

Open **only** the receiver’s vendor HID++ collection (`0xFF00`). Never the keyboard or mouse collections. Never seize.

1. One Bolt session owns `C548`. Do not let the 3S reader, MX4 reader, and keyboard reader each open it.
2. Walk slots, ping, read the name (feature `0x0005`). Divert only the slot that is an MX Master.
3. Prefer Bluetooth if the same mouse is also on BLE (Easy-Switch). Probe BLE product IDs before the receiver so BT users do not wait on empty-slot timeouts.
4. 3S gesture is already HID++ CID `0x00C3` — a correct slot is enough.
5. MX4 haptic on BLE is HID button 7 on report `0x02`. On Bolt that report lives on the receiver **mouse** collection, which must stay closed ([hidpp-divert-steals-pointer.md](hidpp-divert-steals-pointer.md)). Press / swipe XY have to come from diverted HID++ (`0x01A0`, Force Sensing `0x19C0`, analytics) plus the existing click tap — not from parsing `0x02` on `C548`.
6. Do not apply `PointerHIDSettings` to `C548` as if it were one mouse. That would hit every Bolt device on the dongle.

Mouser (macOS, 2026) used this layout for MX Master 3S For Mac on BLE and Bolt: non-exclusive IOKit on `C548`, keep scanning after a keyboard slot, BLE before the receiver.

## Capture when the receiver is plugged in

Use `tools/hidpp-sniff.swift` (no seize). Kill it when done.

- List `C548` collections (usage page / usage / product name). Confirm vendor HID++ vs keyboard vs mouse.
- Ping slots 1–6; read names. Note which slot is the MX and which are keyboard / other.
- One haptic / gesture hold and extra buttons. Confirm whether MX4 pad events arrive as HID++ `0x01A0` / analytics, CG `otherMouse` button 6, or only on the mouse collection.
- Check Logi Options+ / LogiPluginService if HID++ times out (`dev/todo.md`).

Do not open the mouse collection (`0x01` / `0x02`) for this capture.

## Do not

- Treat `C548` as “the MX Master 4.”
- Assume slot 1 is the mouse.
- Match Bolt by adding more wireless IDs to `MXMaster3Support` / `MXMaster4Support`.
- Open or seize the receiver mouse collection.
- Let every family matcher attach `C548`.
- Apply pointer DPI / speed to the receiver as a whole.

## Related

- [roadmap.md](roadmap.md) — product item
- [hid-open-seize-dual-mouse.md](hid-open-seize-dual-mouse.md) — why one matcher on every Logitech interface blew up
- [mx-master-4-ble-haptic.md](mx-master-4-ble-haptic.md) — BLE MX4; slot 1 was a keyboard
- [mx-master-3s-hid.md](mx-master-3s-hid.md) — BLE 3S; `C548` still plugged in, not opened
- [hidpp-divert-steals-pointer.md](hidpp-divert-steals-pointer.md)
- [todo.md](todo.md)
