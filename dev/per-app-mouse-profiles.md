# Per-app mouse, gamepad, and remote profiles

An MX mouse, DualSense, or Apple TV Remote can use a different mapping in Safari than in Xcode without picking it from the sidebar.

MX Master 3 / 3S / 4, DualSense / DualSense Edge, and Apple TV Remote. MX Mechanical has no Control mappings.

## Product

Every MX Master, DualSense, and Apple TV Remote device page. Each device has **Default** plus optional **per-app** copies. There is no Browsers / Editors category chip.

Add App copies Default, then applies a **preset** if the bundle is a known browser or editor (Safari, Chrome, VS Code, Cursor, …). Finder and unknown apps stay on Default until you add them.

The **profile tiles** choose which mapping the card is editing (Default plus one tile per added app, with Add App as the final tile). Tiles wrap to more rows when needed. The device uses the exact app copy if one exists, otherwise Default. Caption: `Mouse is using Safari` / `Gamepad is using Default`.

Resolver (`MouseAppCatalog.liveProfile`): exact bundle, else Default. Control Box (`com.whitesticker.controlbox`) keeps the last live mapping unless the user added a Control Box row.

Storage is a full `MappingProfile` copy per app. Watcher is `NSWorkspace.didActivateApplicationNotification`, not a 1 s poll.

### What switches

Button bindings, DualSense touchpad gestures, haptic / gesture sets, and the MX thumb-wheel **mode**. `ControlEngine` and `MXWheelActionEngine` reset when the live mapping id changes.

### What does not

DualSense and Remote Analog, Pointer & Scroll, and Calibration. DualSense Tab repeat lives on Calibration. These are one setting per device and are copied across stored app profiles. Mac Pointer & Scroll, Window Management, and HID++ divert / attach also do not switch. MX DPI is on Calibration (Default profile) and is written to the mouse.

## UI

MX device page. Profiles card: wrapping **profile tiles** (Default, added apps, Add App) on top, mappings below (Gesture button, Buttons, Other buttons, Thumb wheel). DPI is on Calibration. Main-wheel and left/right-click mappings are not exposed. One tile’s mapping is on screen at a time.

DualSense and Apple TV Remote device pages. The Profiles card contains the same **profile tiles** plus button and gesture mappings. Analog, Pointer & Scroll, and Calibration are separate device-level sections; their values do not change with the frontmost app. DualSense Tab repeat is on Calibration.

Add App is a sheet: search, Recent, running regular apps, Other… (`NSOpenPanel`). Name / Description is not shown on app-scoped profiles.

## Presets (starting point)

Applied when you add that app, not as a shared category:

- Known browsers: thumb wheel = Navigate Between Tabs; haptic left / right = Previous / Next tab.
- Known editors: Back / Forward = Previous / Next tab.
- DualSense known browsers and editors: L2 / R2 = Previous / Next tab.
- Apple TV Remote app profiles copy Default without an additional preset.

## Watcher

Event-driven `NSWorkspace.didActivateApplicationNotification` on the main queue, plus `frontmostApplication` on start. Lives on `DualSenseMonitor`. Do not poll. Do not use Accessibility for bundle ID.

See [polling-loops.md](polling-loops.md). DualSense and Apple TV Remote use the same watcher.
