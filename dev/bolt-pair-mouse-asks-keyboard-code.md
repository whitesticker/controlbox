# Bolt pairing a mouse asks for a typed keyboard code

Seen 2026-10-05 pairing an MX Master 3S through Add Device → Logi Bolt.

## Symptom

The pairing guide showed digits to type and Return, as if pairing a keyboard. A mouse should get the Left/Right click sequence.

## Cause

`captureDiscovery` in `LogiBoltPairing.swift` read the `0x4f` discovered-device report at the wrong offsets:

| Field | Was | Correct |
|---|---|---|
| Device kind | `report[16]` | `report[7]` |
| Auth | `report[7]` | `report[18]` |

Byte 16 is past the address (`[10:15]`), so the kind could come out as keyboard for a mouse. The guide and the entropy length (`0x14` keyboard vs `0x0A` mouse) both follow the kind.

Solaar's `handle_device_discovery` reads part 0 as `data[3]` kind, `data[6:12]` address, `data[14]` auth, where `data[i]` is `report[4 + i]`. Kind values match `DEVICE_KIND` (1 keyboard, 2 mouse, 8 trackball, 9 touchpad); Solaar uses the keyboard entropy only for kind 1.

## Fix

Read kind from `[7]` and auth from `[18]`. Address and the part-1 name parse were already right.

Not confirmed with a live discovery capture yet. Check the guide shows clicks the next time a mouse is paired.
