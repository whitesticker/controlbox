# External monitor brightness does nothing (monitor ignores DDC reads)

Seen 2026-10 on a Samsung LF32TU87.

## Symptom

The Display Brightness slider for the monitor did nothing, though the monitor accepts DDC writes.

## Cause

The old Display Brightness code read the current and max value over DDC before enabling the slider. The Samsung never answers reads, so max came back 0 and every write was skipped.

## Fix

Display Brightness now runs the vendored engine in `ControlBox/Mac/DisplayBrightness/Engine/` (credit in `THIRD_PARTY_NOTICES`). Default **Upon startup** is "assume last saved values": no DDC read, max assumed 100, writes deduplicated on the engine's DDC queue. Released in 0.1.50.

Do not add a read gate back. "Attempt to read" stays an opt-in under the engine settings.
