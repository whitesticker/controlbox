# Night Shift take-over beachballs on launch

## Symptom

Control Box launches and immediately shows the spinning wait cursor. Activity Monitor lists it as not responding. A sample sits in `NightShiftCatalog.handleSystemNightShiftChanged` → `CBBlueLightClient getBlueLightStatus` waiting on XPC.

## Cause

The Night Shift pane toggle stays on across launches. `beginControl` registers a System Settings / Control Center status handler, then applies the curve. That apply posts a CoreBrightness status notification. The handler applied again with `force: true`, which posted another notification. The main actor queued apply → notify → apply forever. Each turn does a synchronous `getBlueLightStatus` XPC, so the app never paints.

## What we changed

Ignore status callbacks that fire as an echo of our own `NightShift.apply`. Real System Settings / Control Center changes still put the curve back.

## Do not

Call `apply(force: true)` from the status handler without an echo guard.
