# Whole Mac gets laggy after Control Box runs for a day

Hit 2026-10-07 on 0.1.53 after about 25 hours up. Typing, pointer, and scrolling were sluggish everywhere; quitting Control Box fixed it at once.

## Why one app can lag every app

Several taps are **active** (`defaultTap`) and sit on the main run loop: Window Organize and Display Arrangement hotkeys (every key down/up), `MXClickProbe` (every click, drag, and mouse move), and `MouseScrollTap` (every scroll). An active tap holds each event until its callback returns. Anything that blocks the main thread delays input for the whole Mac.

## What was blocking or piling up

- **`SMAppService.mainApp.status` on the 120 Hz poll.** `refreshPermissions()` ran every 2 s from `capture()` and read the status three times. Each read is a synchronous XPC round trip to smd: ~50 ms for this signed app (under 1 ms for a bare CLI). That was ~160 ms of main-thread stall every 2 s, slower when the system is busy.
- **`IOHIDManagerOpen` / `Close` just to enumerate.** `HIDNameIndex.load()` (twice per 15 s device refresh) and `LogitechHIDPPDiscovery.connectedMouseProductIDs()` opened every matching mouse, keyboard, and HID++ collection. Each open/close leaked user-space Mach ports (~1000/hour, ~8 per call in an isolated test) and made GameController reconnect to `gamepolicyd`. Enumeration and `IOHIDDeviceGetProperty` work without opening.
- **System Monitor disk volumes every second.** `volumeAvailableCapacityForImportantUsageKey` is a CacheDelete query to `deleted`, which logs ~35 service lines per call. Together with the above, Control Box wrote ~186 log lines/s (16.6 M in 26 h).
- **One unexplained SwiftUI layout run.** `ControlBox_2026-10-06-150951_mac.cpu_resource.diag`: 95% CPU for 90 s, main thread in deep `StackLayout` / `ScrollView` sizing while the app was not frontmost. The stack is truncated before any Control Box frame, so the view is unknown. Footprint was 333 MB (fresh launch ~80 MB).

## Fix

Login-item status is read once, on a detached task, at launch, on `didBecomeActive`, and synchronously only after the Launch at Login toggle. The poll calls `refreshTrust()` (TCC preflights only). HID enumeration never opens devices. Disk volumes refresh every 30 s; throughput stays at 1 Hz.

After: main-thread poll time ~300 ms per 10 s instead of ~1040 ms; no `SMAppService` on the main thread; Mach ports flat; ~32 log lines/s.

## Do not

Put XPC-backed status reads (`SMAppService`, CacheDelete-backed volume keys) on the poll or the main thread. Open HID devices to read properties. If the SwiftUI layout spike comes back, take a `sample` while it is live; the CPU report alone cannot name the view.
