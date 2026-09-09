# Generic Logitech HID++ mouse support

## Scope

Unknown Logitech mice can use the existing device page when Control Box proves that a standard mouse collection and an audited HID++ vendor endpoint belong to the same product. Known MX 3/3S/4 modules still win and retain their report quirks.

This is capability support, not a Logitech-vendor allow-all:

- HID++ endpoints: `0xFF00/0x0002`, `0xFF43/0x0202`, `0xFF43/0x0602`
- Known Bolt, Unifying, Nano, and Lightspeed receiver PIDs are excluded.
- A plain Logitech mouse with no correlated HID++ endpoint remains unsupported by the device page. Mac → Pointer & Scroll still applies globally.

## Runtime

`LogitechDeviceSession` owns one pool of identical, capability-driven mouse readers. Each reader claims one direct HID++ endpoint so multiple physical mice do not share a snapshot. Bolt slots are allocated once across that pool. `LogitechMouseRegistry` applies compact data quirks after identity is known; there are no per-model mouse modules. `DeviceInformation 0x0003` supplies the physical unit ID used to collapse the same unit across BLE and Bolt; WPID alone never proves identity.

## Capability gating

The HID++ Feature Set and Reprog control table drive the existing UI:

- Easy-Switch appears only for `0x1814` / `0x1815`.
- Thumb wheel appears only for implemented `0x2150`.
- Mouse Settings shows only implemented DPI `0x2201`, SmartShift `0x2110` / `0x2111`, and thumb-wheel controls.
- Reprog controls map to known semantic buttons or one of twelve stable Extra slots sorted by CID.
- Gesture-capable controls require both temporary diversion and raw-XY capability.

Extended DPI `0x2202` and legacy battery `0x1000` / `0x1001` are catalogued but do not advertise working UI until their wire clients exist.

## Ownership

Discovery is read-only. A generic mouse receives no firmware writes until it has a remembered `DeviceRecord`.

Before changing any Reprog CID, the reader calls `getCidReporting`, stores temporary diversion, raw XY, remap, and analytics state, then changes only the required fields. Disabling control, switching ownership, disconnecting, or quitting restores that captured state. Persistent diversion and force-raw-XY valid bits are never sent.

Hi-res and thumb-wheel modes are also read before the first write and restored from their original values.

System `CGEvent` mouse events are not attributed to a reader and therefore never start a gesture. HID++ control presses own gesture lifecycle; the shared event tap only swallows pointer events after that reader has an active attributed gesture. Logitech products stay on HID++ divert + firmware XY (OpenLogi `rawXYEvent` for CID `0x00C3`). Cursor-travel swipe for other mice is later.

## Files

- `ControlBox/Devices/Logitech/Shared/LogitechHIDPPDiscovery.swift`
- `ControlBox/Devices/Logitech/Mouse/LogitechMouseHIDModel.swift`
- `ControlBox/Devices/Logitech/Mouse/LogitechMouseReader.swift`
- `ControlBox/Devices/Logitech/LogitechDeviceSession.swift`
- `Packages/ControlBoxCore/Sources/ControlBoxCore/Devices/Logitech/`
