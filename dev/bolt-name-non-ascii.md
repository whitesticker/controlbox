# Bolt page shows a Chinese device name as "3"

Seen 2026-10-05 after renaming an MX Master 3S to `一只鼠标 3S`.

## Symptom

The Bolt page listed the mouse as `3`.

## Cause

- The Bolt receiver keeps its own short copy of each name (`B5` `0x60+slot`, one long report, about 13 bytes of name). The mouse itself stores the full name (HID++ `0x0007` Device Friendly Name). Bytes, not characters: a Chinese character is 3 UTF-8 bytes.
- `LogiBoltSupport.ascii` dropped every byte outside printable ASCII, so `一只鼠标 3` became ` 3`, trimmed to `3`. The pairing discovery name used the same decoder. Solaar caps at 14 and decodes ASCII too.
- `MXFriendlyNameHIDPP.set` cut the UTF-8 bytes at the mouse's max length, which could split a character.

## Fix

- `LogiBoltSupport.name`: decode UTF-8, drop a cut-off trailing character, strip control characters; ASCII filter only if the bytes are not UTF-8.
- Readers read `getFriendlyNameLen` byte 1 after setup and publish `friendlyNameMaxLength`. The device-page Name field (`DeviceNameField`) clips to that many bytes on whole characters and shows a `used/limit` byte counter. `renameSelectedDevice` and `MXFriendlyNameHIDPP.set` clip the same way (`MXFriendlyNameHIDPP.clipped`).

## Open

- Long names are still short on the Bolt page because of the receiver copy. Prefer the Control Box nickname / mouse `0x0007` name for a known unit (in `todo.md`).
- An exact 13-byte cut would give `一只鼠标`, not `3`; the receiver's raw bytes were never captured. Read `B5 0x61` read-only if it ever looks wrong again.
