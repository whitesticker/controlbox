# Display Arrangement: same monitors listed as two groups

Hit 2026-08-26 with two Lenovo P32p-20 panels plus a Philips 329P9. Display Arrangement showed two sections with the same names. The live group was Current; the other said those monitors were disconnected and Apply was disabled.

## Symptom

- One desk, one set of externals.
- Two combo headers with the same title (`LEN P32p-20 (1) + LEN P32p-20 (2) + PHL 329P9`).
- Only the Current group can Apply.

## Cause

Combos are keyed by the raw identity strings of the externals, not by the on-screen names. Identity format changed (and twins can fall back to UUID vs serial), so the same three panels were stored under two `comboID`s. Apply compared those strings exactly, so the older group never matched live hardware.

Do not merge by title alone. Two different desks can share model names.

## Fix

On refresh, map each stored preset onto the live panels (exact key, then serial, then UUID, then unique name / unique vendor+model). Rewrite screen identities and `comboID` to the live keys, then drop duplicate combo records.

Code: `DisplayArrangement.reconcile`, `aligned`, `ArrangementCatalog.refresh`.
