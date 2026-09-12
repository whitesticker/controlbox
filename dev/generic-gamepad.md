# Generic gamepad: `GamepadSession` base, DualSense as a subclass

Status: shipped in 0.1.46 (2026-09-11). `GamepadFamilySession` owns a pool of `GamepadSession`s; `DualSenseSession` subclasses the reader for Sony touchpad + HID battery. Generic pads are `DeviceKind.gamepad` on Add Device → Bluetooth. Several DualSenses and several Xbox pads can each be a **sidebar** row. Calibration is the same three-column **window** with touchpad / motion panels gated on capabilities.

## What we found

- DualSense is **not** a raw HID packet parser. `ControlBox/Devices/DualSense/DualSenseSession.swift` attaches a `GCController` from Apple's GameController framework and, once per host poll (120 Hz, `DualSenseMonitor.capture()`), copies `GCDualSenseGamepad` values into `DualSenseSnapshot`. Raw IOHID (`DualSenseHIDBatteryReader`) is only the battery nibble (report `0x01` USB / `0x31` BT). `DualSenseHaptics` is `CHHapticEngine` on `controller.haptics`.
- The pipeline after the snapshot is already device-agnostic: `ControlFrameBuilder.make(from:)` → `ControlFrame` (`[DeviceButton: Bool]` + `[AnalogSource: AnalogSample]` + `leftTrigger`/`rightTrigger`) → `ControlEngine.process` → `MappingProfile.bindings`. Per-app Profiles, Analog, Pointer & Scroll, and L2/R2 tab travel all key on `record.isGamepad`, not on Sony.
- `GCExtendedGamepad` is Apple's generic profile and is exactly the requested minimum: `buttonA/B/X/Y` (positional: A bottom, B right, X left, Y top), `leftThumbstick`/`rightThumbstick` + `leftThumbstickButton`/`rightThumbstickButton` (L3/R3), `dpad`, `leftShoulder`/`rightShoulder` (digital), `leftTrigger`/`rightTrigger` (analog `Float`), `buttonMenu` (Start/Options), `buttonOptions?` (Select/Create/View), `buttonHome?` (PS/Xbox/Home). Every controller macOS recognises gets it, including unknown HID pads (`GCProductCategoryHID`). No HID descriptor parsing needed.
- Capabilities that are **not** universal, confirmed from the macOS SDK headers:

| Capability | Where it lives | Who has it |
|---|---|---|
| Touchpad (click + 2 fingers) | `GCDualSenseGamepad`, `GCDualShockGamepad` only | Sony only |
| Motion (gravity / accel / gyro) | `GCController.motion` (optional) | DualSense, DualShock 4, Switch Pro / Joy-Con; **not** Xbox |
| Haptics | `GCController.haptics` (optional) | DualSense, DualShock 4, Xbox One/Series; many generic pads nil |
| Battery | `GCController.battery` (optional) + DualSense HID nibble | most wireless pads; wired pads nil |
| Light bar | `GCController.light` (optional) | Sony |
| Paddles P1–P4, Share | `GCXboxGamepad` (Elite / Series) | Xbox only |
| Adaptive triggers | `GCDualSenseGamepad.leftTrigger as GCDualSenseAdaptiveTrigger` | DualSense only |

- Persisted names are Sony-flavoured and must stay stable: `DeviceButton` raw values (`cross`, `circle`, `square`, `triangle`, `create`, `options`, `ps`, `touchpadClick`, `touchpadOneFinger`, `touchpadTwoFinger`), `AnalogSource` raw values (`dualSenseLeftStick` …), `MappingProfile.dualSenseTouchpad` / `dualSenseTabRepeatInterval`. Rename Swift identifiers only with an explicit `rawValue` so saved `controlbox.deviceRecords.v1` still decodes.

## Target shape

```
ControlBox/Devices/Gamepad/                   (new folder; project uses a synchronized root group, no pbxproj edit)
  GamepadSnapshot.swift                       moved + renamed from DualSense/DualSenseSnapshot.swift
  GamepadSession.swift                        open @MainActor class, generic GCExtendedGamepad reader (DeviceFamilySession)
  GamepadHaptics.swift                        moved + renamed from DualSense/DualSenseHaptics.swift (GCDeviceHaptics is generic)
  GamepadLayout+GameController.swift          GCController → GamepadLayout / GamepadCapabilities
ControlBox/Devices/DualSense/
  DualSenseSession.swift                      final class DualSenseSession: GamepadSession (touchpad, HID battery, Sony filter)
  DualSenseHIDBatteryReader.swift             unchanged
Packages/ControlBoxCore/.../Models/
  GamepadLayout.swift                         enum sony / xbox / nintendo / generic + per-button labels + colours
  GamepadCapabilities.swift                   Codable { touchpad, motion, haptics, battery }
```

Swift has class inheritance, so "DualSense extends generic" is literal: `GamepadSession` is a non-final class with a handful of overridable hooks; `DualSenseSession` overrides them. `GamepadFamilySession` is the `DeviceFamilySession` the host starts: it opens one shared DualSense HID battery manager, starts GameController discovery, and keeps one attached session per `GCController`. DualSense vs generic is still the `accepts` filter on the session type. Same-name pads get ordinal catalog ids (`gc:Name`, `gc:Name#2`). HID Bluetooth address is used only when exactly one HID pad and one GC pad of that kind are present; otherwise the address is `slot:<catalogID>` so two Xbox pads are not both `Game Controller`. Player 1–4 is `GCController.playerIndex` (LED) persisted on `DeviceRecord.gamepadPlayerIndex`; Apple says it does not survive unplug as a serial. Add Device and `recordsMatch` do not collapse gamepads by vendor name.

### `GamepadSnapshot` (rename of `DualSenseSnapshot`)

Keep every existing field name so ContentView / ControllerDiagramView / ProfilesPane edits stay mechanical. Add:

```swift
struct GamepadTouchpadState: Equatable, Sendable {
    var click = false
    var finger1 = TouchFinger(x: 0, y: 0, active: false)
    var finger2 = TouchFinger(x: 0, y: 0, active: false)
}

struct GamepadSnapshot: Equatable, Sendable {
    // existing: connected, name, product, playerIndex,
    //   cross circle square triangle (GC buttonA / B / X / Y = bottom / right / left / top),
    //   dpadUp/Down/Left/Right, l1 r1 l3 r3, create (buttonOptions) options (buttonMenu) ps (buttonHome),
    //   l2 r2 Float, leftStick rightStick SIMD2<Float>,
    //   battery*, events
    var layout: GamepadLayout = .generic
    var capabilities = GamepadCapabilities()
    var touchpad: GamepadTouchpadState? = nil        // nil = controller has no touchpad
    // motion fields stay (gravity, userAcceleration, rotationRate, hasMotion); hasMotion == capabilities.motion
}
```

Replace `isDualSense` with `layout == .sony && touchpad != nil` where needed, or keep it as a computed `var isDualSense: Bool { touchpad != nil }` during migration. `touchpadClick`, `touch1`, `touch2` become computed accessors over `touchpad` so `ControlFrameBuilder`, `ControllerDiagramView`, and Calibration compile with minimal edits. `matchesSettings`, `matchesIgnoringMotion`, and `hadButtonDown` stay.

### `GamepadLayout` (ControlBoxCore, Codable, `String` raw values)

```swift
public enum GamepadLayout: String, Codable, Sendable, CaseIterable {
    case sony, xbox, nintendo, generic

    public var title: String            // "DualSense", "Xbox layout", "Nintendo layout", "Generic layout"
    public var brand: String            // "Sony", "Microsoft", "Nintendo", "Other"
    public func label(for button: DeviceButton) -> String
    // .cross → Cross / A / B / A     .circle → Circle / B / A / B
    // .square → Square / X / Y / X   .triangle → Triangle / Y / X / Y
    // .create → Create / View / − / Select    .options → Options / Menu / + / Start
    // .ps → PS / Xbox / Home / Home           .l1 .r1 → L1 R1 / LB RB / L R / L1 R1
    // .l2 .r2 → L2 R2 / LT RT / ZL ZR / L2 R2  .l3 .r3 → "Left stick click" everywhere
    public var homeButtonName: String   // for "Press the PS button if the controller is paired but idle"
}
```

Face-button colours per layout for the Calibration diagram: Sony keeps `Palette.cross/circle/square/triangle`; Xbox A green / B red / X blue / Y yellow; Nintendo and generic use one neutral tint. Put the colour switch in `ControllerDiagramView`, not in Core.

Layout detection (`GamepadLayout+GameController.swift`):

- `productCategory == GCProductCategoryDualSense || GCProductCategoryDualShock4` → `.sony`
- `GCProductCategoryXboxOne` → `.xbox`
- `vendorName` contains `nintendo`, `joy-con`, `pro controller`, `switch` → `.nintendo`
- else `.generic`

Refinement for a later step: `GCControllerElement.localizedName` / `sfSymbolsName` (macOS 11+) can label a live button for any pad the OS knows; use it in Calibration if the layout table is wrong for a specific controller.

### `GamepadCapabilities` (ControlBoxCore, Codable)

```swift
public struct GamepadCapabilities: Codable, Equatable, Sendable {
    public var touchpad = false
    public var motion = false
    public var haptics = false
    public var battery = false
}
```

Derived from a `GCController` once at attach: `touchpad = extendedGamepad is GCDualSenseGamepad || is GCDualShockGamepad`, `motion = controller.motion != nil`, `haptics = controller.haptics != nil`, `battery = controller.battery != nil`. Persist on `DeviceRecord` (`gamepadLayout: GamepadLayout?`, `gamepadCapabilities: GamepadCapabilities?`, both optional so old records decode). Refresh both on every connect. For existing DualSense records the nil fallback is `.sony` / all four true.

### `GamepadSession` base class

```swift
@MainActor
class GamepadSession: DeviceFamilySession {
    let familyID: String
    let kinds: Set<DeviceKind>
    private(set) var snapshot = GamepadSnapshot()
    private(set) var controller: GCController?
    private let haptics = GamepadHaptics()
    private var previousButtons: [String: Bool] = [:]

    init(familyID: String = "gamepad", kinds: Set<DeviceKind> = [.gamepad])

    var vendorName: String? { controller?.vendorName }
    var isAttached: Bool { controller != nil }

    // DeviceFamilySession
    func start()      // GCController.shouldMonitorBackgroundEvents = true; startWirelessControllerDiscovery
    func stop()

    // Host entry points (same names DualSenseMonitor already calls)
    func attachPreferred(named: String?)     // GCController.controllers().filter(accepts) → prefer name match
    func handleDisconnect(_ controller: GCController)
    func detach()
    func poll(hapticEnabled: Bool, wantMotion: Bool)
    func pulse()

    // Overridable hooks
    func accepts(_ controller: GCController) -> Bool
        // base: controller.extendedGamepad != nil && !(controller.extendedGamepad is GCDualSenseGamepad)
    func readExtras(controller: GCController, pad: GCExtendedGamepad, into next: inout GamepadSnapshot, wantMotion: Bool)
        // base: no-op (motion handled in base poll because it is generic)
    func applyBattery(to next: inout GamepadSnapshot, controller: GCController)
        // base: controller.battery only (today's else-branch of DualSenseSession.applyBattery)
    func extraEventRows(_ next: GamepadSnapshot) -> [(String, Bool)]
        // base: [] ; labels for click history beyond the 15 core rows
    func didAttach(_ controller: GCController)   // base: haptics.attach, motion.sensorsActive = false
    func didDetach()                             // base: haptics.detach
}
```

`poll` in the base does everything `DualSenseSession.poll` does today for the plain `GCExtendedGamepad` branch, plus `buttonHome` via `pad.buttonHome?.isPressed ?? physicalInputProfile.buttons[GCInputButtonHome]?.isPressed`, plus layout/capabilities, plus motion when `wantMotion`, then calls `readExtras`, then the events / haptic-pulse tail. Core event labels come from `snapshot.layout.label(for:)` so click history says "A" on an Xbox pad and "Cross" on Sony.

Trigger digital threshold stays `> 0.15` for events and `ControlFrame.buttons`; analog `l2` / `r2` still ride `leftTrigger` / `rightTrigger` so tab travel works on any analog trigger. Digital-only triggers (0 / 1) just look like full pulls.

### `DualSenseSession: GamepadSession`

```swift
@MainActor
final class DualSenseSession: GamepadSession {
    private let hidBattery = DualSenseHIDBatteryReader()
    init() { super.init(familyID: "dualsense", kinds: [.dualSense, .dualSenseEdge]) }
    override func start() { hidBattery.start(); super.start() }
    override func stop()  { hidBattery.stop(); super.stop() }
    override func accepts(_ c: GCController) -> Bool { c.extendedGamepad is GCDualSenseGamepad }
    override func readExtras(...) {
        guard let pad = pad as? GCDualSenseGamepad else { return }
        next.touchpad = GamepadTouchpadState(click: pad.touchpadButton.isPressed,
                                             finger1: finger(from: pad.touchpadPrimary),
                                             finger2: finger(from: pad.touchpadSecondary))
    }
    override func applyBattery(...)  { HID nibble first (today's code), else super }
    override func extraEventRows(_ s: GamepadSnapshot) -> [(String, Bool)] {
        [("Touchpad click", s.touchpadClick), ("Touch 1", s.touch1.active), ("Touch 2", s.touch2.active)]
    }
}
```

Behaviour for the DualSense must be byte-for-byte what it is today: same fields, same thresholds, same haptic pulse, same IMU gating on Calibration.

## Implementation steps

### Step 0 — Probe the unknown controller (10 minutes, no app change)

Before touching code, confirm macOS hands the controller to GameController and see what it exposes. Save this as `/tmp/gcprobe.swift`, pair/plug the controller, then run `swift /tmp/gcprobe.swift` and press a button within 15 s:

```swift
import Foundation
import GameController

GCController.shouldMonitorBackgroundEvents = true
GCController.startWirelessControllerDiscovery(completionHandler: nil)

func dump() {
    for c in GCController.controllers() {
        print("vendorName:", c.vendorName ?? "nil")
        print("productCategory:", c.productCategory)
        print("extendedGamepad:", c.extendedGamepad.map { String(describing: type(of: $0)) } ?? "nil")
        print("motion:", c.motion != nil, " haptics:", c.haptics != nil,
              " battery:", c.battery?.batteryLevel ?? -1, " light:", c.light != nil)
        if let pad = c.extendedGamepad {
            for (key, element) in pad.elements.sorted(by: { $0.key < $1.key }) {
                print("   ", key, "→", element.localizedName ?? "-", element.sfSymbolsName ?? "-")
            }
        }
        print("---")
    }
}

NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { _ in dump() }
dump()
RunLoop.main.run(until: Date().addingTimeInterval(15))
```

Done check: the controller prints with a non-nil `extendedGamepad`. Record `productCategory`, `vendorName`, and the motion / haptics / battery booleans in this file under a new "Controllers seen" heading. If it never appears, the OS does not classify it as a gamepad and this plan needs a raw-HID reader (see Later); stop and report instead of guessing.

### Step 1 — Core models: `GamepadLayout`, `GamepadCapabilities`, `isGamepad` rename

Files: `Packages/ControlBoxCore/Sources/ControlBoxCore/Models/GamepadLayout.swift` (new), `GamepadCapabilities.swift` (new), `Models/DeviceButton.swift`, `Actions/ControlEngine.swift`, `Devices/DualSense/DualSenseTriggerTravel.swift`, `ControlBox/DualSenseMonitor.swift`.

- Add the two types above with tests in `Packages/ControlBoxCore/Tests/ControlBoxCoreTests/` (label table per layout; Codable round trip; defaults all false).
- `DeviceButton`: add `public static func gamepadGroups(hasTouchpad: Bool) -> [DeviceButtonGroup]` (same five groups; System is `[.create, .options, .ps]` plus `.touchpadClick` only when `hasTouchpad`). Make `dualSenseGroups = gamepadGroups(hasTouchpad: true)`. Add `public static func gamepadButtons(hasTouchpad:)` likewise (plus the two finger rows only when `hasTouchpad`).
- `ControlEngine.isDualSense` → `isGamepad` (mechanical rename; 8 uses in ControlEngine, 2 in DualSenseMonitor). It gates analog scroll gain, trigger tab travel, and scroll acceleration — all generic gamepad behaviour. Touchpad handling is already gated on the frame containing `.dualSenseTouchpad`, so a generic frame without it is a no-op.
- Optional in this step: `DualSenseTriggerTravel` → `GamepadTriggerTravel` (file move + rename; it is plain analog travel).

Done check: Core tests pass (`swift test` in `Packages/ControlBoxCore`), app builds, DualSense behaves as before.

### Step 2 — `GamepadSnapshot` + `GamepadSession` base, DualSense subclass

Files: move `ControlBox/Devices/DualSense/DualSenseSnapshot.swift` → `ControlBox/Devices/Gamepad/GamepadSnapshot.swift`; move `DualSenseHaptics.swift` → `Gamepad/GamepadHaptics.swift`; new `Gamepad/GamepadSession.swift`, `Gamepad/GamepadLayout+GameController.swift`; rewrite `DualSense/DualSenseSession.swift` as the subclass.

- Rename `DualSenseSnapshot` → `GamepadSnapshot`, `DualSenseHaptics` → `GamepadHaptics`. Keep a `typealias DualSenseSnapshot = GamepadSnapshot` for one step so ContentView / ProfilesPane / ControllerDiagramView / ControlFrameBuilder compile; remove the alias in Step 5.
- Add `layout`, `capabilities`, `touchpad: GamepadTouchpadState?`; make `touchpadClick`, `touch1`, `touch2`, `isDualSense` computed over `touchpad`.
- `ControlFrameBuilder.make(from: GamepadSnapshot)`: only emit `.touchpadClick`, `.touchpadOneFinger`, `.touchpadTwoFinger`, `.dualSenseTouchpad`, `.dualSenseTouchpadSecondary` when `snapshot.touchpad != nil`. Everything else unchanged.
- Write `GamepadSession` per the sketch; port today's `DualSenseSession` body into it (generic branch + home + motion + events + haptic pulse). `DualSenseSession` becomes the subclass with only Sony-specific overrides.

Done check: builds; DualSense Calibration, Profiles, touchpad gestures, L2/R2 tab travel, haptic pulse, battery all unchanged (test each on the real DualSense). `rg -n "GCDualSenseGamepad" ControlBox/` should hit only `DualSenseSession.swift`, `GamepadLayout+GameController.swift`, and `BluetoothDeviceCatalog.swift`.

### Step 3 — Device kind, records, catalog, Add Device

Files: `ControlBox/Devices/Shared/BluetoothDeviceCatalog.swift`, `Shared/DeviceRecord.swift`, `ControlBox/Devices/UI/DevicesPane.swift`, `Packages/.../Models/MappingProfile.swift`.

- `DeviceKind`: add `case gamepad` (title "Game Controller", `isGamepad` true, `sidebarType .gamepad`, `brand "Other"`, `supportBlurb` "Face buttons, D-pad, bumpers, analog triggers, and both sticks map to pointer, keys, and gestures.", `paneGlyph` reuse `device-dualsense-filled` until a generic asset exists).
- `DeviceRecord`: add `var gamepadLayout: GamepadLayout? = nil`, `var gamepadCapabilities: GamepadCapabilities? = nil`; computed `resolvedGamepadLayout` (nil → `.sony` for DualSense kinds, `.generic` otherwise) and `resolvedGamepadCapabilities` (nil → all true for DualSense kinds, all false otherwise). `hapticFeedbackEnabled` default → `resolvedGamepadCapabilities.haptics`. `brand` for the sidebar caption: use `gamepadLayout?.brand` when `kind == .gamepad` (add `DeviceRecord.brandTitle` and use it in `SidebarDevice.rowCaption`; `SidebarDevice` needs the layout too).
- `ConnectedBluetoothDevice`: add `gamepadLayout: GamepadLayout? = nil`, `gamepadCapabilities: GamepadCapabilities? = nil` so Add Device can seed the record. `DeviceRecord.make(from:)` copies them.
- `BluetoothDeviceCatalog.connectedDevices()`: replace the `GCDualSenseGamepad`-only loop with every `GCController` that has `extendedGamepad`; kind is `.dualSense` / `.dualSenseEdge` when `GCDualSenseGamepad` (keep the Edge name check), else `.gamepad`; `detail` is `layout.title`; `address` stays "Game Controller"; id stays `"gc:\(name)"`. Run this loop **before** the HID loop and skip HID rows whose lowercased product name is already in `seen`, so the OS-recognised controller is not shadowed by a "Not supported yet" HID row (usage page 1 / usage 5).
- `DeviceSupport.classify`: unchanged (HID pads stay `.unsupported`; GameController is the source of truth for gamepads).
- `MappingProfile.makeDefault(isAppleTVRemote:isMXMaster:isMXKeyboard:)` → add `gamepadHasTouchpad: Bool = true`. Generic branch = today's DualSense defaults minus `.touchpadClick` / `.touchpadOneFinger` bindings, `dualSenseTouchpad: .off`, no `gestureSets`, summary "L1/R1 desktops, L2/R2 tabs. D-pad Mission Control, Desktop, and app switch. Left stick pointer, right stick scroll." Callers: `DeviceRecord.make`, `DeviceRecord.selectedProfile`, and any others `rg -n "makeDefault\(" ControlBox Packages` finds; pass `record.resolvedGamepadCapabilities.touchpad`.
- `SupportedDevicesGuide.brands` in `DevicesPane.swift`: add `("Other", [.gamepad])` with copy "Any controller macOS recognises: Xbox, Switch Pro, 8BitDo, generic HID pads."
- `DualSenseMonitor.suppressionKey`: `.gamepad` uses the same name-based key form (`"gamepad:\(name.lowercased())"`) because GameController has no address.

Done check: with the mystery controller paired, Add Device → Bluetooth lists it under its vendor name with detail "Xbox layout" / "Generic layout" etc.; Add puts one row under the **Gamepad** section header in the sidebar; Delete Device removes it; relaunch keeps it.

### Step 4 — Host wiring in `DualSenseMonitor`

Files: `ControlBox/DualSenseMonitor.swift`.

- `private let gamepad = GamepadSession()` next to `dualSense`; add to `familySessions`.
- `@Published`/observable `var gamepadSnapshot = GamepadSnapshot()` for the generic session (keep `snapshot` for DualSense). Add `func gamepadSnapshot(for deviceID: String) -> GamepadSnapshot` that returns `snapshot` for DualSense kinds and `gamepadSnapshot` for `.gamepad` — mirrors `mxSnapshot(for:)`. This is the seam every view uses from Step 5 on.
- `attachPreferredController()` → attach both sessions with their own preferred record name (`deviceRecords.first { $0.remembered && session.kinds.contains($0.kind) }?.name`).
- GC connect/disconnect observers: call `handleDisconnect` on both sessions, then re-attach both, then refresh both snapshots. On connect, also write `gamepadLayout` / `gamepadCapabilities` into the matching remembered record and persist (`rememberConnectedDevice` is the natural spot; catalog rows now carry them).
- `capture()`: after the DualSense block, poll `gamepad` with `hapticEnabled: record?.hapticFeedbackEnabled` and the same `wantMotion`; publish through a generalised `publishGamepad(_:into:wantMotion:)` (same settings-only / 10 Hz-motion throttle as `publishDualSense`, see `dev/device-settings-scroll-lag.md`); if `liveGamepadRecord(for: gamepad)` is remembered and `connected`, `ingestControl(ControlFrameBuilder.make(from:), record:)`.
- `liveDualSenseRecord()` → `liveGamepadRecord(for session: GamepadSession)`: remembered record whose `kind ∈ session.kinds` and `namesMatch(record.name, session.vendorName)`, else first remembered record of those kinds.
- `removeSelectedDevice`: detach whichever session owns that record kind and reset that snapshot.
- `setTabRepeatInterval`, the analog / pointer / scroll setters, and `ensureControllerDeviceSettings` already key on `isGamepad`; verify they still pass `record.isGamepad` for `.gamepad`.
- Add a row to `dev/polling-loops.md` only if you add a timer; polling stays inside the existing 120 Hz `capture()`.

Done check: Control this Mac on the generic record moves the pointer with the left stick, scrolls with the right, D-pad fires Mission Control / Desktop / app switch, L2/R2 tab travel works, Home button (`ps`) is remappable. A DualSense connected at the same time still works independently.

### Step 5 — Device page (`ProfilesPane`)

Files: `ControlBox/Devices/UI/ProfilesPane.swift`, `ControlBox/Devices/UI/DevicesPane.swift`.

- Battery card (`~line 408`): `monitor.gamepadSnapshot(for: record.id)` instead of `monitor.snapshot`.
- Analog card (`controllerAnalogBox`): show the **Touchpad analog** row only when `record.resolvedGamepadCapabilities.touchpad`; show **Haptic feedback** only when `.haptics`; drop the touchpad and haptic bullets from the footer when absent.
- Profiles (`controllerProfilesSections`): the **1-finger swipe** / **2-finger swipe** boxes and the footer bullets only when `.touchpad`. `buttonGroups(for:)` returns `DeviceButton.gamepadGroups(hasTouchpad:)` for gamepads.
- Labels: wherever a gamepad row label is built (`mxLabel(for:record:)` and `actionRow` titles), use `record.resolvedGamepadLayout.label(for: button)` so an Xbox pad reads A / B / X / Y / LB / RB / LT / RT / View / Menu / Xbox. Shoulders footer: "L2 / R2" → `layout.label(for: .l2)` / `.r2`.
- Remove the `typealias DualSenseSnapshot`.

Done check: generic record page has no Touchpad analog row, no finger swipe boxes, System group is three buttons, labels match the controller's brand. DualSense page unchanged.

### Step 6 — Calibration for the generic gamepad

Files: `ControlBox/ContentView.swift` (`CalibrationWindow`, `ControllerCalibrationLayout`, `HeaderBar`, `ControllerLiveClicksContent`), `ControlBox/Devices/UI/ControllerDiagramView.swift`.

Layout stays the same three columns as DualSense so the window keeps one size (**stable frame**, content changes):

| Column | DualSense | Generic |
|---|---|---|
| Button press mapping | `ControllerDiagramView` with touchpad | same view, touchpad hidden, face / shoulder / small-button labels + colours from `layout`, small-button row moves up into the touchpad's space |
| Middle | Gesture capture over Click history | Click history full height (the existing `else` branch) |
| Live clicks | Analog, Triggers (Tab repeat), Touchpad, Motion | Analog, Triggers (Tab repeat), Motion only if `capabilities.motion`, else a one-line "No IMU on this controller" panel; no Touchpad panel |

- `CalibrationWindow`: the `else` branch and `isLive` read `monitor.gamepadSnapshot(for: deviceID)`. `HeaderBar` takes that snapshot; "Waiting for DualSense" → "Waiting for controller"; status line "Press the PS button…" → "Press the \(layout.homeButtonName) button…"; `StatusChip` shows `layout.title`; "No motion" chip stays.
- `ControllerDiagramView(snapshot:)` gains `layout`; `FaceButtons` takes four `(label, colour)` from the layout; `SmallButton` labels from `layout.label(for: .create / .ps / .options)`; `ShoulderButton` / `TriggerBar` labels likewise; `TouchpadView` only when `snapshot.touchpad != nil`.
- `ControllerLiveClicksContent`: `snapshot = monitor.gamepadSnapshot(for: deviceID)`; Touchpad panel conditional; Motion panel conditional; Tab repeat slider stays (analog triggers are in the base).
- `wantMotion` in the host already keys on `isGamepad`; a pad with `motion == nil` simply reports `hasMotion == false`.

Done check: open Calibration on the generic record: every face button, D-pad arm, bumper, trigger bar, stick, L3/R3, Select/Start/Home lights up live with the brand's labels; click history logs them; no touchpad anywhere; Motion panel matches the controller's actual capability. Open the DualSense Calibration side by side: unchanged.

### Step 7 — Docs and AGENTS.md

- Add a "Controllers seen" table to this file (vendor name, product category, layout, capabilities, anything odd).
- `AGENTS.md` Current status: one bullet — "Generic game controllers: `GamepadSession` (GameController `GCExtendedGamepad`) is the base; `DualSenseSession` subclasses it for touchpad + HID battery. Any pad macOS recognises is Add Device → Bluetooth with kind `.gamepad`; labels follow `GamepadLayout`. Touchpad / motion / haptics are capabilities, not the base." Update the Device rule table with a `Generic game controller` row and the `DeviceFamilySession` sentence to name `GamepadSession`.
- `dev/README.md` gets a row for this file (done); `dev/roadmap.md` "Generic mouse and gamepad mapper" bullet: split the gamepad half off as done once Step 6 ships.

## Later (not in this pass)

- **Xbox extras.** `GCXboxGamepad.paddleButton1–4` and `buttonShare` → new `DeviceButton` cases (`padPaddle1…4`, `padShare`) surfaced under Profiles as an "Extra" group when present, like MX Extra controls. Same `readExtras` hook, an `XboxSession: GamepadSession` subclass.
- **Sony extras beyond touchpad.** Light bar (`controller.light`), adaptive trigger effects, DualShock 4 as a second `GamepadSession` subclass sharing the touchpad override with DualSense.
- **Raw HID fallback.** Only if Step 0 shows a pad GameController does not list. Would be a `HIDGamepadReader` behind the same `GamepadSnapshot`, parsing usage page `0x01` usage `0x05` reports via `IOHIDValue` element usages (no product-specific byte offsets). Never seize; never open the collection just to watch buttons (see `AGENTS.md` hard constraints).
- **Identifier cleanup.** `AnalogSource.dualSenseLeftStick` → `gamepadLeftStick` etc. with explicit `rawValue`s to keep persistence; `MappingProfile.dualSenseTouchpad` / `dualSenseTabRepeatInterval` likewise; `DualSenseMonitor` is the host for every family and could become `DeviceHost`. Mechanical, but touches many files — do it as its own change.

## Controllers seen

| Vendor name | `productCategory` | Layout | Touchpad | Motion | Haptics | Battery | Notes |
|---|---|---|---|---|---|---|---|
| DualSense Wireless Controller | `DualSense` | sony | yes | yes | yes | yes (HID nibble) | baseline |
| _(plug the unknown pad, Add Device, fill this row)_ | | | | | | | |
