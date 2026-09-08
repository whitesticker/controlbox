# Main wheel fired the thumb mapping

Investigated 2026-09-07. Firefox (or any app) with thumb left/right bound to Previous/Next tab also changed tabs when the **main** scroll wheel moved.

## What happened

`MXClickProbe` treats every `scrollWheel` CGEvent as both axes at once: axis 1 → wheel up/down, axis 2 → thumb left/right. MX high-res / smooth notches often carry a leftover horizontal delta on a vertical tick. Control Engine then pulses the thumb action on top of native vertical scroll.

Thumb already arrives on HID++ `0x2150` while Accessibility is on (`applyThumbRouting`). Native pan on the same report as the main wheel is not that roller.

## Fix

- When the thumb feature is diverted, ignore CG / native pan for thumb pulses. HID++ `handleThumbWheel` is the source.
- Otherwise take **one** dominant axis (line, point, and fixed fields) so a vertical notch cannot also be a thumb tick.
