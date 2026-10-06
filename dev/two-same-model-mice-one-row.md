# Two MX Master 3S on one sidebar row

Seen 2026-10 with two MX Master 3S (units `B06CBDDA` and `A0669914`) on one Bolt receiver.

## Symptom

Both mice showed as one sidebar row. The saved row mixed one mouse's unit ID with the other mouse's address, so it matched either mouse, and both shared mappings.

## Cause

Every path that ties a connected mouse to a saved row could fall back to something weaker than the unit:

- `recordsMatch` fell back to the product name unless both addresses were 12-hex Bluetooth addresses. Bolt addresses are 8-hex unit tokens, so two Bolt 3S matched by name.
- Bolt row IDs are `bolt-<receiver>-<slot>`, and an exact row ID matched before identity. A different mouse in that slot took the old row.
- `refreshDevices` let several connected devices take the same row ID, which collapses them into one row.
- `rememberConnectedDevice` overwrote the row's address from whichever mouse matched, but kept the old unit ID.
- `liveMXRecord` and `LogitechDeviceSession.mouseReader(for:)` had name/model fallbacks with no unit check.
- `BluetoothDeviceCatalog` dropped any HID device whose product name was already listed, so a second Bluetooth 3S never appeared.

## Fix

- `DeviceIdentity.unitsConflict`: two known, different units veto every match (row ID, name, model). A unit token address counts as a unit.
- No name fallback when both addresses name a unit (`addressesNameUnits`: both 12-hex or both 8-hex).
- `assignRecordIDs`: each saved row backs at most one connected device; unit/address matches claim first, then exact row ID, then name. A device whose own ID collides with someone else's row gets a unit-suffixed ID.
- Load repair: a row with a unit ID and a different unit-token address takes the token of its unit ID.
- Bluetooth list keeps same-name devices with different addresses.

Row IDs are not migrated; an existing slot-keyed row keeps its ID as long as the same unit is in it.
