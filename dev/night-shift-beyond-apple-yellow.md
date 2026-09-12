# Night Shift top cannot go below 2700 K

## Symptom

System Settings **More Warm** is already at 2700 K. The Yellowness chart top should still look warmer than that.

## Cause

`CBBlueLightClient setCCTRange:` returns false below Apple’s `getCCTRange.min` (2700 K here). `setCCT` below that min clamps back to 2700 K. Night Shift itself cannot go yellower.

## What we changed

Keep Night Shift at Apple’s max, then stack per-display gamma (`CGSetDisplayTransferByTable`) toward ~1900 K, scaled by curve warmth. Restore ColorSync when the pane goes off, on quit, and when warmth is back at cool. Re-apply after display reconfigure and wake.

## Do not

Call `setCCT` / `setCCTRange` below `getCCTRange.min`. Do not leave gamma tables installed after quit. Do not add a second timer for gamma — use the Night Shift 20 s tick plus wake / screen-change.
