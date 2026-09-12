# Loops that keep calling the system

Idle bugs and beachballs usually live here. A timer or poll that is fine at 1 Hz will peg a core at 120 Hz if it walks IOKit, Accessibility, Core Audio, or publishes `@Observable` state every tick.

When something is “always on” and the Mac feels busy, start with this list. Do not add a new repeating timer without writing it down here.

## Always on while Control Box is running

| Loop | Rate | What it calls | When it runs | Do not |
|---|---|---|---|---|
| Device poll | 120 Hz | HID DualSense battery / GameController gamepads / Apple TV / MX gesture pointer, `ControlEngine.process`, MX thumb interpolator tick (`MXThumbSmoother` ~8 ms frames while a 100 ms ease is live), window-grab configure, scroll-tap apply | `DualSenseMonitor` timer from `start()` | IORegistry walks, AX prompts, snapshot assigns when nothing changed. IMU and live clicks only while Calibration is open. See [poll-timer-cpu.md](poll-timer-cpu.md), [apple-tv-battery-registry-cpu.md](apple-tv-battery-registry-cpu.md), [device-settings-scroll-lag.md](device-settings-scroll-lag.md). Do not add a second timer for thumb easing. |
| Window Grab tick | 120 Hz | Reads the last `CGEvent` point; AX / `SLSMoveWindow` only while a grab or throw is active | While any Window Grab move/resize/throw toggle is on | AX inside the event-tap callback. See [window-grab-only-own-app.md](window-grab-only-own-app.md). |

HID **reports** themselves are event-driven (`IOHID` callbacks). The 120 Hz timer is what turns analog sticks and hold-to-swipe into pointer / DockSwipe.

## On only when that pane or extra is on

| Loop | Rate | What it calls | When it runs | Do not |
|---|---|---|---|---|
| Night Shift curve | 20 s | `CBBlueLightClient` apply; optional extra gamma past 2700 K; optional external brightness; Light/Dark schedule | Night Shift toggle on | Re-apply on every CoreBrightness status ping (beachball). Do not add a second appearance timer. See [night-shift-hijack-hang.md](night-shift-hijack-hang.md), [night-shift-flips-dark-mode.md](night-shift-flips-dark-mode.md), [night-shift-beyond-apple-yellow.md](night-shift-beyond-apple-yellow.md). |
| System Monitor | 1 s (sensors 3 s, battery 5 s) | CPU / GPU / memory / net / disk / SMC | System Monitor menu extra on | Sample process list on this tick (`ProcessMonitor` is on demand). |
| Sound menu extra | 1.5 s | `SystemAudio` outputs + `AppVolumeMixer.apps()` | Only while the Sound extra menu is **open** | Rebuild process taps on an empty `!obj` list. See [macbook-app-volume-system-lag.md](macbook-app-volume-system-lag.md). |
| Caffeinate countdown | 1 s | Menu item title from `endDate` | Only while the Caffeinate extra menu is **open** and a timed session is on | Do not tick while the menu is closed. Expire with a one-shot timer, not this poll. |
| App volume taps | HAL IOProc / tap clock | Per-app gain while a tap is installed | Sound mixer is live | Two mixers on the same app. See [process-tap-exclusive.md](process-tap-exclusive.md). |
| MX Mechanical battery | 5 min | HID++ `UNIFIED_BATTERY` | Keyboard HID++ ready | Do not put on the 120 Hz path. Do not divert keys. Do not `SetReport` on the main thread from a SwiftUI toggle. |
| MX Master battery | 5 min | HID++ `UNIFIED_BATTERY` | Mouse HID++ ready | Do not put on the 120 Hz path. |

## Event-driven (no idle poll)

These react to HID, `CGEvent`, `NSWorkspace`, or screen-change notifications. They are still easy to get wrong if the handler does heavy work on every event.

| Path | Trigger | System API | Notes |
|---|---|---|---|
| MX HID++ / clicks | HID report, one shared click tap | `IOHID`, `CGEvent` tap | Do not open the standard mouse collection. |
| MX Mechanical HID++ | HID++ report `0x11` + 5 min battery read while attached | `IOHID` SetReport on a serial IO queue, no seize | Do not treat keyboard reports as HID++. Do not divert keys. Do not read-after-write on backlight toggle / effect. See [mx-mechanical-hid.md](mx-mechanical-hid.md). |
| Scroll speed / invert | Wheel `CGEvent` tap | `CGEvent` | Input Monitoring. |
| Window Grab / Organize / Arrangement hotkeys | Listen-only `CGEvent` tap | `CGEvent`, then AX on a timer | Stash in the tap; AX on the tick. |
| Shake to focus | Listen-only left-mouse tap; Window Grab move feeds points | Coalesced main-queue AX hit / minimize | **No idle timer.** Keep down and drag in the same flush. See [shake-to-focus.md](shake-to-focus.md). |
| Dock click | Listen-only left-mouse tap | Dock AX tile + window list on mouse up | One-shot per click, no double-click timer. Frontmost app is read at mouse-down. Do not swallow the native click. Move-all is a modifier chord. |
| Dock Previews | Listen-only mouse tap + local `NSEvent` + Dock selected-child `AXObserver` | Coalesced `CGEvent` moves, cached Dock AX tiles, ScreenCaptureKit stills (≤6, cached) | **No pointer sampling.** One resolve per run-loop turn. AX tile walk at most ~8 Hz; hit-test the cache otherwise. Do not observe Dock layout (magnification). See [dock-window-preview.md](dock-window-preview.md). |
| App switcher previews | Listen-only Command/Tab tap | Window list + stills for the highlighted app | Only while the switcher session is up. See [app-switcher-window-preview.md](app-switcher-window-preview.md). |
| Caps Lock modifier | `defaultTap` on Caps Lock + listen-only keyboard HID usage `0x39` | Swallow Caps Lock; track hold; mapped modifiers in `live()` | **No idle timer.** Do not seize the keyboard. See [caps-lock-modifier.md](caps-lock-modifier.md). |
| Display Brightness / Arrangement | Screen connect, pane appear | CoreDisplay / DDC / `NSScreen` | DDC is queued, not polled. Brightness extra does not poll while the menu is open. |
| Permissions / device list | Launch, wake, HID attach | TCC, `SMAppService`, IOHID | Not on the 120 Hz path. |
| Logi Bolt pair / list / talk | HID++ reports on `C548` vendor `0xFF00`; one-shot slot list + arrive/ping; HID++ 2.0 slot writes while a Bolt-only MX / keyboard is attached | `IOHID` SetReport, no seize | Always on while Control Box is running (catalog `keepAlive`). Pairing pauses slot talk on that receiver. Do not open the mouse/keyboard collections. Do not poll slots on the 120 Hz path. Do not apply pointer HID properties to `C548`. |
| Frontmost app → profile | `NSWorkspace.didActivateApplicationNotification` | `NSWorkspace` | Compare bundle ID; ignore Control Box unless an app row exists for it; no idle timer. MX, DualSense, and Apple TV Remote live mapping. See [per-app-mouse-profiles.md](per-app-mouse-profiles.md). |

## One-shot or user-driven (not loops)

Display Arrangement apply, Window Organize, Night Shift take-over, Screen Recording request, Dock Preview and app-switcher thumbnail stills (only while that panel is up). Caffeinate expire timer (one-shot at `endDate`). MX Easy-Switch host list (`0x1814` / `0x1815`) after HID++ attach, and again from the Easy-Switch **Refresh** button.

## Rules for a new loop

1. Prefer a notification, HID callback, or listen-only `CGEvent` tap over a timer.
2. If you need a timer, gate it on the pane toggle and stop it when the toggle is off.
3. Never do AX, IORegistry, or Core Audio graph rebuilds on the 120 Hz device poll.
4. Add a row to this file in the same change.
