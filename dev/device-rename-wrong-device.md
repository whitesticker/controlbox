# Device rename can land on the wrong device or be dropped

Found 2026-10-05 while reviewing how the Name field reaches HID++ `0x0007`.

## Symptom

- Typing a name and switching to another device within about half a second could write the name to the newly selected device.
- Renaming a mouse or keyboard while it was disconnected, or before HID++ was ready, changed the Control Box nickname only. Nothing ever reached the device, and nothing said so.
- Every keystroke rewrote the device name (debounced 0.45 s), so a pause mid-word stored a partial name.

## Cause

- `renameSelectedDevice` scheduled a `DispatchWorkItem` that called `writeSelectedFriendlyName`, which read `selectedRecord` when it fired rather than the record that was edited.
- The reader `setFriendlyName` methods returned early when not ready and discarded the `MXFriendlyNameHIDPP.set` result.

## Fix

- `DeviceNameField` keeps local text and commits on Return or focus loss (also on disappear). Escape reverts. The byte counter and clipping stay.
- `DualSenseMonitor.renameDevice(_:to:)` takes the record ID. It stores the nickname and queues `pendingFriendlyNames[id]`.
- `writePendingFriendlyName` writes only once that record's own reader (or the matching live keyboard) has published `friendlyNameMaxLength`, which means `0x0007` was probed. Otherwise the status is `.waiting`.
- The poll tick calls `retryWaitingFriendlyNames()`, which does nothing when no write is queued. This means a reconnect or wake flushes the name without a new timer.
- `setFriendlyName(_:completion:)` reports success. `friendlyNameWrites[id]` drives the Name subtitle: "Saves to the mouse when connected.", "Saving…", "Saved." (clears after 3 s), or "Couldn’t save… Press Return to retry."

## Open

- A Logitech mouse without `0x0007` shows "Saves to the mouse when connected." forever after a rename, because "not probed yet" and "not supported" look the same from the snapshot.
