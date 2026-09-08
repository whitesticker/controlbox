# Per-app mouse profiles

An MX mouse can use a different mapping in Safari than in Xcode without picking it from the sidebar.

Mice only. DualSense / DualSense Edge stay gamepads with today’s named Profile picker. Siri Remote and MX Mechanical also keep it.

## Product

Every MX Master device page (3, 3S, 4 — not a product-ID gate). Each mouse has **Default** plus optional **per-app** copies. There is no Browsers / Editors category chip.

Add App copies Default, then applies a **preset** if the bundle is a known browser or editor (Safari, Chrome, VS Code, Cursor, …). Finder and unknown apps stay on Default until you add them.

The **profile tiles** choose which mapping the card is editing (Default plus one tile per added app, with Add App as the final tile). Tiles wrap to more rows when needed. The mouse uses the exact app copy if one exists, otherwise Default. Caption: `Mouse is using Safari` / `Mouse is using Default`.

Resolver (`MouseAppCatalog.liveProfile`): exact bundle, else Default. Control Box (`com.whitesticker.controlbox`) keeps the last live mapping unless the user added a Control Box row.

Storage is a full `MappingProfile` copy per app. Watcher is `NSWorkspace.didActivateApplicationNotification`, not a 1 s poll.

### What switches

Button bindings, haptic / gesture sets, and the thumb-wheel **mode**. `ControlEngine` and `MXWheelActionEngine` reset when the live mapping id changes.

### What does not

Mac Pointer & Scroll, Window Management, HID++ divert / attach. DPI is on Calibration (Default profile) and is written to the mouse.

## UI

MX device page. Profiles card: wrapping **profile tiles** (Default, added apps, Add App) on top, mappings below (Gesture button, Buttons, Other buttons, Thumb wheel). DPI is on Calibration. Main-wheel and left/right-click mappings are not exposed. One tile’s mapping is on screen at a time.

Add App is a sheet: search, Recent, running regular apps, Other… (`NSOpenPanel`). Name / Description dropped on MX.

## Presets (starting point)

Applied when you add that app, not as a shared category:

- Known browsers: thumb wheel = Navigate Between Tabs; haptic left / right = Previous / Next tab.
- Known editors: Back / Forward = Previous / Next tab.

## Watcher

Event-driven `NSWorkspace.didActivateApplicationNotification` on the main queue, plus `frontmostApplication` on start. Lives on `DualSenseMonitor`. Do not poll. Do not use Accessibility for bundle ID.

See [polling-loops.md](polling-loops.md).
