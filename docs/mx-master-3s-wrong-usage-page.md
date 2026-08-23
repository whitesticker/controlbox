# MX Master 3S HID++ collection is not the Master 4 collection

## Symptom

MX Master 4 could attach over HID++. MX Master 3S over Bluetooth did not. Gestures never started on the 3S.

## Cause

Master 4 HID++ is usage page `0xFF00`. Master 3S BLE HID++ is often `0xFF43` (product id around `0xB034`, Bolt sometimes `0xB043`). A matcher that only opens `0xFF00` never sees the 3S.

The 3S gesture control is also a different CID (thumb `0x00C3`), not the Master 4 haptic `0x01A0`.

## Status

3S matching was pulled back after dual-mouse crashes, then resumed 2026-08-22 with MX4 disconnected. Matching is product `0xB034` / `0xB043` only (see [mx-master-3s-hid.md](mx-master-3s-hid.md)). Do not open Bolt `0xC548`. Keep 3S and 4 as separate HID modules; shared code is the HID++ pipe and gesture engine.
