# Thumb wheel scroll does nothing with Smooth scrolling on

## Symptom

MX thumb wheel set to Horizontal or Vertical Scroll does not scroll anything while Pointer & Scroll **Smooth scrolling** is on. Calibration still lights Thumb wheel left / right, Navigate Between Tabs still works, and turning Smooth scrolling off makes scroll work again.

## Cause

`EventPoster.smoothScroll` set the point delta first and the line delta second. Setting a scroll event's line field makes macOS rewrite the point and fixed-point fields from it. The smoother emits small frames (under 10 px), so line = px / 10 = 0 and the rewrite zeroed the point delta: every posted event had no distance. The fixed-point field was also written with `setIntegerValueField`, which treats the value as whole lines (65536× too large).

Tabs never reach `smoothScroll`, and Smooth scrolling off posts line ticks through `scrollTicks`, so both kept working.

## Fix

Write line first, then point, then fixed with `setDoubleValueField(px / 10)` — the same order `MouseScrollTap` already uses when it rescales events.
