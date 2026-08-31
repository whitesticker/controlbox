# MX Master 3S HID++ is on the BLE mouse device

Captured 2026-08-22 with MX Master 4 disconnected. The 3S is **Bluetooth LE**, product `0xB034`.

## What the machine exposes

| Device | Product ID | Primary collection | Notes |
|---|---|---|---|
| USB Receiver (Bolt) | `0xC548` | `0xFF00` plus keyboard / mouse | Still plugged in. **Not** the 3S. Do not open it. |
| MX Master 3S | `0xB034` | Mouse `0x01` / `0x02` | Vendor HID++ is **nested** on this same device. |

Device usage pairs on the 3S: mouse (`0x01`/`0x02`), pointer (`0x01`/`0x01`), and vendor page **`0xFF43` usage `0x0202`**. Primary usage page stays `0x01`, so a matcher that requires primary page `0xFF43` never sees the mouse.

Report descriptor (97 bytes):

- Report `0x02`: **16** buttons, then 12-bit X, 12-bit Y, wheel, AC Pan. Two button bytes, not the MX4 one-byte layout.
- Report `0x11`: 19-byte HID++ long in/out. No short report `0x10`.

There is also an `AppleUserHIDEventService` copy of the same product. Prefer the `IOHIDDevice` that has a report descriptor. Do not seize. Do not open the mouse collection just to watch buttons.

## Master 3 vs 3S

Solaar and logiops list the **same** Reprog V4 CIDs on both mice. Quiet clicks and Bolt vs Unifying do not change divert or gesture. One module (`MXMaster3Support`) covers both; the sidebar still labels 3 vs 3S from product ID. Master 3 itself has not been on this Mac.

## Gestures

3S has no haptic pad and no CID `0x01A0`. The thumb **gesture button** is CID `0x00C3`. Hold it and move; a tap is Click. Control Box still binds that control as `.mxHaptic` so the shared gesture engine / ControlEngine stay unchanged. UI copy says Gesture, not Haptic.

Divert flags are the same hold-only pair as MX4 (`0x33`). No persist, no force-raw-XY, no Force Sensing `0x19C0`.

## Code split

- `MXMaster3Support` covers Master 3 and 3S (same CIDs). `MXMaster4Support` is the haptic-pad mouse.
- `LogitechMXMasterReader` is the shared HID++ pipe + pointer/wheel/hold-to-swipe engine.
- Discovery picks one model from connected product IDs. One mouse at a time.

## Related

- [mx-master-3s-wrong-usage-page.md](mx-master-3s-wrong-usage-page.md)
- [hid-open-seize-dual-mouse.md](hid-open-seize-dual-mouse.md)
- [mx-master-4-ble-haptic.md](mx-master-4-ble-haptic.md)
- [logi-bolt-receiver.md](logi-bolt-receiver.md) — Bolt-only 3S is a `C548` slot, not product `0xB043`
