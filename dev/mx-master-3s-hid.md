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

Solaar and logiops list the **same** Reprog V4 CIDs on both mice. Quiet clicks and Bolt vs Unifying do not change divert or gesture. One shared Logitech mouse module probes both; `LogitechMouseRegistry` labels 3 vs 3S from product ID. Master 3 itself has not been on this Mac.

## Gestures

On 3S, CID `0x00C3` is the **gesture button** (owner `.mxSide`). There is no haptic button. MX4 uses the same CID for the gesture button and CID `0x01A0` for the **haptic button**.

Divert flags are the same hold-only pair as MX4 (`0x33`). No persist, no force-raw-XY, no Force Sensing `0x19C0`. Divert that CID once at attach even if `getCidReporting` fails — 3S has no native pad fallback. MagSpeed writes can clear Reprog, so the dedicated CID is re-diverted after SmartShift.

## Code split

- `LogitechMouseRegistry` stores the 3/3S identity fallback and the MX4 haptic quirks as data; both run through `LogitechMouseReader`.
- `LogitechMouseReader` is the shared HID++ pipe + pointer/wheel/hold-to-swipe engine.
- A pool of readers claims one HID++ endpoint each so 3S and 4 (and other HID++ mice) can stay attached at once.

## Related

- [mx-master-3s-wrong-usage-page.md](mx-master-3s-wrong-usage-page.md)
- [hid-open-seize-dual-mouse.md](hid-open-seize-dual-mouse.md)
- [mx-master-4-ble-haptic.md](mx-master-4-ble-haptic.md)
- [logi-bolt-receiver.md](logi-bolt-receiver.md) — Bolt-only 3S is a `C548` slot, not product `0xB043`
