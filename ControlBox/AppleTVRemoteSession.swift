import Foundation

/// Apple TV remote family. HID + Multitouch + battery.
/// Swap `generation` when a later Siri Remote needs a different map.
@MainActor
final class AppleTVRemoteSession: DeviceFamilySession {
    let familyID = "apple-tv-remote"
    let kinds: Set<DeviceKind> = [.appleTVRemote]
    var generation: AppleTVRemoteGeneration

    private(set) var snapshot = AppleTVRemoteSnapshot()
    private let reader = AppleTVRemoteHIDReader()
    private let touch = AppleTVTouchReader()
    private let battery = AppleTVBatteryReader()
    private var previousButtons: [String: Bool] = [:]
    private var hidWasLive = false
    private var lastTouchRescan = Date.distantPast

    var hidConnected: Bool { reader.snapshot.connected }

    init(generation: AppleTVRemoteGeneration = AppleTVA2540()) {
        self.generation = generation
    }

    func start() {
        reader.start()
        if generation.usesMultitouchClickpad {
            touch.start()
        }
        battery.start()
    }

    func stop() {
        reader.stop()
        touch.stop()
        battery.stop()
        snapshot = AppleTVRemoteSnapshot()
        previousButtons = [:]
        hidWasLive = false
    }

    func poll(catalogDevice: ConnectedBluetoothDevice?, selected: Bool) {
        let hidLive = reader.snapshot.connected
        if generation.usesMultitouchClickpad {
            if hidLive && !hidWasLive {
                touch.restart()
                lastTouchRescan = Date()
            } else if hidLive, !touch.snapshot.available,
                      Date().timeIntervalSince(lastTouchRescan) > 2 {
                touch.restart()
                lastTouchRescan = Date()
            }
        }
        hidWasLive = hidLive

        guard hidLive || catalogDevice != nil || selected else {
            if snapshot.connected {
                snapshot = AppleTVRemoteSnapshot()
            }
            return
        }

        reader.applyTouch(touch.snapshot)
        var next = reader.snapshot
        next.connected = hidLive || catalogDevice?.isConnected == true
        next.name = catalogDevice?.name ?? next.name
        next.product = generation.productTitle
        if let percent = battery.percent(
            serial: catalogDevice?.name ?? next.name,
            address: catalogDevice?.address ?? ""
        ) {
            reader.applyBatteryPercent(percent)
            next.batteryAvailable = true
            next.batteryPercent = percent
            next.batteryFull = percent >= 95
            next.batteryStateDescription = next.batteryFull ? "Full" : "Discharging"
        }
        next.events = updatedEvents(from: next)
        snapshot = next
    }

    func clearIfIdle() {
        if snapshot.connected {
            snapshot = AppleTVRemoteSnapshot()
        }
        hidWasLive = false
    }

    private func updatedEvents(from next: AppleTVRemoteSnapshot) -> [InputLogEvent] {
        let current: [(String, Bool)] = [
            ("Back", next.back),
            ("TV", next.tv),
            ("Siri", next.siri),
            ("Mute", next.mute),
            ("Play/Pause", next.playPause),
            ("Power", next.power),
            ("Volume Up", next.volumeUp),
            ("Volume Down", next.volumeDown),
            ("Select", next.select),
            ("Clickpad Up", next.clickUp),
            ("Clickpad Down", next.clickDown),
            ("Clickpad Left", next.clickLeft),
            ("Clickpad Right", next.clickRight)
        ]

        var events = snapshot.events
        if next.touchActive != snapshot.touchActive {
            events.insert(
                InputLogEvent(id: UUID(), date: Date(), label: "Clickpad finger", pressed: next.touchActive),
                at: 0
            )
        }
        if next.wheelActive != snapshot.wheelActive {
            events.insert(
                InputLogEvent(id: UUID(), date: Date(), label: "Click wheel", pressed: next.wheelActive),
                at: 0
            )
        }
        if next.micActive != snapshot.micActive {
            events.insert(
                InputLogEvent(id: UUID(), date: Date(), label: "Siri mic HID", pressed: next.micActive),
                at: 0
            )
        }
        if next.lastHIDSignal != "Press a button",
           next.lastHIDSignal != snapshot.lastHIDSignal {
            events.insert(
                InputLogEvent(
                    id: UUID(),
                    date: Date(),
                    label: "\(next.lastHIDMappedName) · \(next.lastHIDSignal)",
                    pressed: true
                ),
                at: 0
            )
        }
        for (label, pressed) in current {
            previousButtons[label] = pressed
        }
        if events.count > 40 {
            events = Array(events.prefix(40))
        }
        return events
    }
}
