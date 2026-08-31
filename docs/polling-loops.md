# Loops that keep calling the system

Idle bugs and beachballs usually live here. A timer or poll that is fine at 1 Hz will peg a core at 120 Hz if it walks IOKit, Accessibility, Core Audio, or publishes `@Observable` state every tick.

When something is “always on” and the Mac feels busy, start with this list. Do not add a new repeating timer without writing it down here.

## Always on while Control Box is running

| Loop | Rate | What it calls | When it runs | Do not |
|---|---|---|---|---|
| Device poll | 120 Hz | HID DualSense / Apple TV / MX gesture pointer, `ControlEngine.process`, window-grab configure, scroll-tap apply | `DualSenseMonitor` timer from `start()` | IORegistry walks, AX prompts, snapshot assigns when nothing changed. See [poll-timer-cpu.md](poll-timer-cpu.md), [apple-tv-battery-registry-cpu.md](apple-tv-battery-registry-cpu.md). |
| Window Grab tick | 120 Hz | Reads the last `CGEvent` point; AX / `SLSMoveWindow` only while a grab or throw is active | While any Window Grab move/resize/throw toggle is on | AX inside the event-tap callback. See [window-grab-only-own-app.md](window-grab-only-own-app.md). |

HID **reports** themselves are event-driven (`IOHID` callbacks). The 120 Hz timer is what turns analog sticks and hold-to-swipe into pointer / DockSwipe.

## On only when that pane or extra is on

| Loop | Rate | What it calls | When it runs | Do not |
|---|---|---|---|---|
| Night Shift curve | 20 s | `CBBlueLightClient` apply; optional external brightness | Night Shift toggle on | Re-apply on every CoreBrightness status ping (beachball). See [night-shift-hijack-hang.md](night-shift-hijack-hang.md). |
| System Monitor | 1 s (sensors 3 s, battery 5 s) | CPU / GPU / memory / net / disk / SMC | System Monitor menu extra on | Sample process list on this tick (`ProcessMonitor` is on demand). |
| Sound menu extra | 1.5 s | `SystemAudio` outputs + `AppVolumeMixer.apps()` | Only while the Sound extra menu is **open** | Rebuild process taps on an empty `!obj` list. See [macbook-app-volume-system-lag.md](macbook-app-volume-system-lag.md). |
| App volume taps | HAL IOProc / tap clock | Per-app gain while a tap is installed | Sound mixer is live | Two mixers on the same app. See [process-tap-exclusive.md](process-tap-exclusive.md). |

## Event-driven (no idle poll)

These react to HID, `CGEvent`, `NSWorkspace`, or screen-change notifications. They are still easy to get wrong if the handler does heavy work on every event.

| Path | Trigger | System API | Notes |
|---|---|---|---|
| MX HID++ / clicks | HID report, one shared click tap | `IOHID`, `CGEvent` tap | Do not open the standard mouse collection. |
| Scroll speed / invert | Wheel `CGEvent` tap | `CGEvent` | Input Monitoring. |
| Window Grab / Organize / Arrangement hotkeys | Listen-only `CGEvent` tap | `CGEvent`, then AX on a timer | Stash in the tap; AX on the tick. |
| Shake to focus | Listen-only left-mouse tap; Window Grab move feeds points | Coalesced main-queue AX hit / minimize | **No idle timer.** Keep down and drag in the same flush. See [shake-to-focus.md](shake-to-focus.md). |
| Minimize on Dock click | Listen-only left-mouse tap | Dock AX tile + window list on mouse up | One-shot per click. Do not swallow the native click. |
| Dock Previews | Listen-only mouse tap + local `NSEvent` + Dock selected-child `AXObserver` | Coalesced `CGEvent` moves, cached Dock AX tiles, ScreenCaptureKit stills (≤6, cached) | **No pointer sampling.** One resolve per run-loop turn. AX tile walk at most ~8 Hz; hit-test the cache otherwise. Do not observe Dock layout (magnification). See [dock-window-preview.md](dock-window-preview.md). |
| Display Brightness / Arrangement | Screen connect, pane appear | CoreDisplay / DDC / `NSScreen` | DDC is queued, not polled. Brightness extra does not poll while the menu is open. |
| Permissions / device list | Launch, wake, HID attach | TCC, `SMAppService`, IOHID | Not on the 120 Hz path. |
| Apple TV battery | Cached; not on 120 Hz | IORegistry | See [apple-tv-battery-registry-cpu.md](apple-tv-battery-registry-cpu.md). |

## One-shot or user-driven (not loops)

Display Arrangement apply, Window Organize, Night Shift take-over, Screen Recording request, Dock Preview thumbnail stills (only while the hover panel is up).

## Rules for a new loop

1. Prefer a notification, HID callback, or listen-only `CGEvent` tap over a timer.
2. If you need a timer, gate it on the pane toggle and stop it when the toggle is off.
3. Never do AX, IORegistry, or Core Audio graph rebuilds on the 120 Hz device poll.
4. Add a row to this file in the same change.
