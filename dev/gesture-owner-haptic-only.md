# Gesture ownership follows raw-XY capability

## Resolved rule (2026-09-08)

Profiles offers **Gestures** for every Logitech mouse control whose Reprog descriptor is both divertable and raw-XY capable. Defaults are the **gesture button** (`0x00C3` on 3 / 3S / 4) and the MX4 **haptic button**. Middle, Back, Forward, Mode shift, and generic Extra controls join the **Gesture-capable controls** subcard only when firmware reports support.

Left and right click are always excluded. Main-wheel rotation also stays native.

## How it works

| Layer | Current behavior |
|---|---|
| Feature probe | `LogitechHIDPPControlDescriptor.canOwnGestures` requires divertable + raw XY. |
| Profiles UI | Capability-backed controls are separated from ordinary Buttons. |
| Persistence | `MappingProfile` stores independent `GestureSet` values per control; loading no longer deletes non-haptic owners. |
| Reader | `setGestureOwners` maps each owner to its CID and changes reporting between plain divert (`0x03`) and `0x33` raw XY. Dedicated `0x00C3` is always diverted; raw XY is only while it owns Gestures. |
| Engine | `ControlEngine` resolves the gesture owner from the normalized frame and uses that owner’s gesture map. |

Raw-XY reports do not identify which held CID generated motion. The first held gesture owner owns the stream; overlap motion is ignored until only one owner remains.

## Generic Logitech mice

Unknown Reprog controls are assigned stable Extra slots by sorted CID. A control is diverted only when its active profile needs capture. Turning Control this Mac off restores the reporting state captured before Control Box took ownership (`0x22` plus the original value bits when native).

## Historical failure

The earlier UI-only implementation allowed selecting Gestures on Back without teaching the reader to arm that CID or attribute its hold. It therefore continued routing every swipe as haptic. The fix had to cover the feature probe, profile migration, reporting flags, hold ownership, frame owner, and UI identity together.

## Do not

- Never make left or right click gesture owners.
- Never force raw XY when the control table does not advertise it.
- Never persist diversion or clear it with zero; restore with valid clear flags `0x22`.
- Never pin the pointer for the gesture button. OpenLogi uses HID++ raw XY for that CID; cursor-travel swipe is not the Logitech path.
