# Mouse mappings stop after Mac sleep / wake

Seen 2026-10 with an MX Master 3S on Bolt: after the Mac slept and woke (and after logout/login), extra buttons and gestures acted native until Control Box was restarted.

## Cause

The mouse firmware forgets diverts (`0x1B04` `setCidReporting`) when its link drops and comes back. Control Box never noticed, so it never set them again:

- `LogiBoltSupport.isLinkEstablished` read the `0x41` link flags from `report[3]`. That byte is the protocol (`0x10` on Bolt); the flags are `report[4]`, bit `0x40` = link not established (Solaar `notifications.py`). Every `0x41` looked like "established", so link loss was invisible and the slot stayed Online.
- `syncBoltMouse` returns early when the reader is already on that slot and connected, so a re-established link never re-ran setup.
- No device code listened for Mac wake or a user-session switch.
- `0x1D4B` Wireless Device Status (payload byte 1 == 1: "reconfigure me") was ignored.
- `restorePendingCIDReporting` and the wheel restore retried every 0.5 s with no cap, so one stuck write could block setup forever.

Logout/login was most likely the shared-row bug in [two-same-model-mice-one-row.md](two-same-model-mice-one-row.md).

## Fix

- Read link flags from `report[4]`. Link lost → `boltLinkLost()`: keep the original reporting as pending restore and detach without writing. Link back → the session re-attaches the same reader (a reader owing a slot its restore keeps that slot) and full setup runs: restore, then divert.
- `NSWorkspace.didWakeNotification` / `sessionDidBecomeActiveNotification` → 2.5 s later `LogitechDeviceSession.handleSystemWake()`: `LogiBoltCatalog.recheckLinks()` re-arms receiver notifications and re-reads slots; every ready mouse reader runs `reconfigure`.
- `0x1D4B` event with byte 1 == 1 → `reconfigure`.
- `reconfigure` (Bolt: detach + attach on the same link; Bluetooth: drop the pipe without writes and let the recover scan re-open it) is debounced to once per 3 s and only runs on a ready reader.
- Restore retries stop after 10 attempts; the originals stay recorded for quit.

Side effects: a napping mouse shows Not connected, and buttons are native for the second or so that setup takes after wake.

Not yet confirmed across a real Mac sleep.
