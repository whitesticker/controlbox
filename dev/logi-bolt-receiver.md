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
| MX 3/3S reader | `0xB023`, `0x4082`, `0xB034`, `0xB043` | No BLE `IOHIDDevice`. Catalog walks `C548` slots and attaches HID++ 2.0 at the MX slot. |
| MX 4 reader | `0xB042`, `0x4069` | Same: Bolt-only uses the receiver slot, not `B042`. |
| Discovery | MX product IDs, then drop `C548` | Receiver is never a mouse matcher. |

`LogiBoltCatalog` owns `C548` for the life of the app (pair, list, and talk). BLE product-ID readers stay first: if the same unit is also on Bluetooth, the Bolt slot is not attached. Identity is unit ID, then WPID + name, then Easy-Switch BLE vs Bolt — one `DeviceRecord` / sidebar row.

`LogitechMXMasterReader` already walks HID++ indices `0xFF`, `0x00`, then 1–6 on BLE. On Bolt the slot is known, so the walk is that index only. BLE MX4 haptic still comes from native report `0x02` bit `0x40` on the **same** device as HID++ ([mx-master-4-ble-haptic.md](mx-master-4-ble-haptic.md)). On Bolt, haptic / gesture XY come from diverted HID++ (`0x01A0`, Force Sensing, analytics), not from parsing `0x02` on `C548`. Clicks still ride the shared `CGEvent` tap.

## Feasible shape

Open **only** the receiver’s vendor HID++ collection (`0xFF00`). Never the keyboard or mouse collections. Never seize.

1. One Bolt catalog owns `C548`. The 3S reader, MX4 reader, and keyboard reader never open it.
2. Walk slots, ping, read the name (feature `0x0005`). Divert only the slot that is an MX Master.
3. Prefer Bluetooth if the same mouse is also on BLE (Easy-Switch). Probe BLE product IDs before attaching a Bolt slot so BT users do not wait on empty-slot timeouts.
4. 3S gesture is already HID++ CID `0x00C3` — a correct slot is enough.
5. MX4 haptic on BLE is HID button 7 on report `0x02`. On Bolt that report lives on the receiver **mouse** collection, which must stay closed ([hidpp-divert-steals-pointer.md](hidpp-divert-steals-pointer.md)). Press / swipe XY have to come from diverted HID++ (`0x01A0`, Force Sensing `0x19C0`, analytics) plus the existing click tap — not from parsing `0x02` on `C548`.
6. Do not apply `PointerHIDSettings` to `C548` as if it were one mouse. That would hit every Bolt device on the dongle. DPI / pointer scale still go to the slot over HID++.

Mouser (macOS, 2026) used this layout for MX Master 3S For Mac on BLE and Bolt: non-exclusive IOKit on `C548`, keep scanning after a keyboard slot, BLE before the receiver.

## Where Bolt lives in the UI

The dongle is not a Mouse / Gamepad / Remote / Keyboard. Do **not** put `C548` in the Devices sidebar (not under Other either).

- **Already paired:** the occupant is a normal sidebar row under Mouse or Keyboard, caption `Logitech · Bolt` when that radio is the one in use. BLE and Bolt for the same unit collapse to one row (BLE caption when both are up).
- **Pair / unpair / empty slots:** **Add Device** sheet, **Bluetooth | Logi Bolt**. One row per dongle. **Add** and the slot-count line belong to that receiver section. Pairing success closes the guide and refreshes the list. The paired-count register can update before `0xB5:50+n` names; listing retries a missed slot instead of treating a timeout as empty, and keeps current rows on screen. Pairing pauses slot talk on that receiver.

See [todo.md](todo.md) Logitech-related improvements (Bolt talk still open).

## Pairing protocol (verified 2026-09-07)

Open **only** vendor `0xFF00` on `C548` (match VendorID + ProductID + usage page so TCC does not treat it as a keyboard). Receiver is HID++ 1.0 (`0xFF` index). Drain stale reports on open; match replies on device index + subID + register + sub-register.

| Register | Use |
|---|---|
| `0x00` | Notification flags. Discovery and connection reports need software_present (`byte1 \|= 0x08`) **and** wireless (`byte1 \|= 0x01`). Restore on exit. |
| `0x02` | Connection state. Short-read `p1` is the paired count (`B5:02` byte 1 is **not**). |
| `0xB5:02` | Receiver info. Byte 0 = slot count. |
| `0xB5:50+n` | Pairing record (WPID LE, unit ID, kind at offset 14, entropy at 15). |
| `0xB5:60+n` | Name. **`p1` must be `0x01`.** Length at reply `[6]`, ASCII at `[7+]`. |
| `0xC0` | Discovery. Short write: timeout seconds, action `01` start / `02` cancel. |
| `0xC1` | Long write only: `action, slot, address[6], auth, entropy`. `01` pair, `03` unpair. |

Notifications (receiver index `0xFF`): `0x4f` discovered device (address at `[10:15]`, kind `[16]`, auth `[7]`, WPID `[8:9]`); `0x4d` passkey (`[3]` = digit count, then ASCII digits — leading zeros matter); `0x4e` keypress (`00` started, `01` registered, `02` erased, `03` cleared, `04` completed); `0x53` discovery status; `0x54` pairing status; `0x41` / `0x40` connect / disconnect.

Entropy: mouse `0x0A` (10 clicks, MSB first, **RIGHT=1 / LEFT=0**, then Left+Right together); keyboard `0x14` (type the ASCII string, then Return). Auth comes from the `0x4f` frame (`0x02` mouse, `0x01` keyboard observed). Do not send entropy `0x00`.

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
