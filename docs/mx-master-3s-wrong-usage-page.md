# MX Master 3S HID++ collection is not the Master 4 collection

## Symptom

MX Master 4 could attach over HID++. MX Master 3S over Bluetooth did not. Gestures never started on the 3S.

## Cause

Master 4 HID++ is usage page `0xFF00`. Master 3S BLE HID++ is often `0xFF43` (product id around `0xB034`, Bolt sometimes `0xB043`). A matcher that only opens `0xFF00` never sees the 3S.

The 3S gesture control is also a different CID (thumb `0x00C3`), not the Master 4 haptic `0x01A0`.

## Status

3S matching was tried, then pulled back after dual-mouse crashes. **Do not resume 3S work until MX Master 4 is stable.** When we do, it should be a separate reader, not more branches inside one shared MX class.
