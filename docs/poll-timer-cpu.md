# 120 Hz poll does extra work while idle

Hit 2026-08-25 after the Apple TV registry walk was cached. Idle VibeRemote still sat at 10–20% CPU (Debug).

## Symptom

Activity Monitor shows a core’s worth of work with sticks centered and no gestures. A `sample` is the 120 Hz `DualSenseMonitor` timer: `ingestMX`, `MappingProfile.nearestDPI`, `DeviceIdentity.format`, `ControlEngine.process`, and SwiftUI observation from snapshot assigns.

## Cause

The poll has to run at 120 Hz for DualSense sticks and MX hold-to-swipe. It also re-did work that does not need that rate:

- `AXIsProcessTrustedWithOptions` on every `ControlEngine.process` (several times per tick)
- MX DPI / pointer scale / scroll tap / window-grab applied every tick
- DualSense IMU copied and published on an `@Observable` snapshot every tick, so SwiftUI redraws at 120 Hz
- `DeviceIdentity.same` reformatted addresses that were already colon-separated

## Fix

Cache Accessibility for 1 s. Skip MX HID++ / OS pointer writes when DPI and speed are unchanged. Publish DualSense / MX / Apple TV snapshots only when controls change; IMU at 10 Hz and only on the DualSense page; sensors off otherwise. Give the poll timer a small tolerance.

Keep analog `process` at 120 Hz. Do not put IOKit walks or AX prompts on that path.

Code: `DualSenseMonitor.swift`, `DualSenseSession.swift`, `LogitechMXMasterReader.swift`, `EventPoster.swift`. Related: [apple-tv-battery-registry-cpu.md](apple-tv-battery-registry-cpu.md).
