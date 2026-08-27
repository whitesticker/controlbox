# System Monitor ↑/↓ arrows slide when speed digits change

## Symptom

The menu bar extra’s upload/download arrows move left and right as the speed text grows or shrinks (`12 K/s` vs `999.9 K/s`).

## Cause

`NetworkIconRenderer` used a fixed-width canvas (good) but **right-aligned** both lines, so the arrows sat at the right edge of the digits.

## What we changed

Keep the fixed canvas. Each line is **arrow left, speed right**, with padding between so both edges stay filled when the digits change length (`↑    12 K/s` vs `↑ 999.9 K/s`).

## Do not

Shrink the status item to the current digit width. That shoves neighboring extras around. Right-align the whole line (arrows would slide). Left-align the whole line (speed would slide off the right edge).
