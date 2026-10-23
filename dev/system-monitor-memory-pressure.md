# System Monitor memory "pressure" was RAM in use

## Symptom

Memory's **Pressure** read much higher than Activity Monitor's memory pressure, and its color went yellow or red on a Mac that was fine.

## Cause

`MemoryMonitor` computed pressure as `1 − (free + cached) / total`. That is the share of RAM holding app, wired, and compressed pages, which macOS keeps high on purpose. It is not pressure. Thresholds of 60% and 80% then colored it.

## Fix

- Pressure is `1 − kern.memorystatus_level / 100`. `kern.memorystatus_level` is the kernel's "system-wide memory free percentage", the figure `memory_pressure` prints. It counts memory the kernel can still get back by purging, compressing, and swapping. The old figure is kept only as a fallback if that sysctl fails.
- The color follows `kern.memorystatus_vm_pressure_level` (1 normal, 2 warning, 4 critical), the same three states Activity Monitor uses. `MemorySample.pressureColor` / `pressureTitle`.
- The Memory submenu shows where RAM goes as a ring (`MemoryRing`): App, Wired, and Compressed are "used" (center), Cached can be dropped any time, Free is unused.

## Do not

- Call "RAM in use" pressure, or color pressure from fixed percentages.
