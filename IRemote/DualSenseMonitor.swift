import AppKit
import Foundation
import GameController
import IRemoteControl
import Observation

struct Vec3: Equatable, Sendable {
    var x: Double
    var y: Double
    var z: Double

    static let zero = Vec3(x: 0, y: 0, z: 0)

    var magnitude: Double {
        sqrt(x * x + y * y + z * z)
    }
}

struct TouchFinger: Equatable, Sendable {
    var x: Float
    var y: Float
    var active: Bool
}

struct InputLogEvent: Identifiable, Equatable, Sendable {
    let id: UUID
    let date: Date
    let label: String
    let pressed: Bool
}

struct DualSenseSnapshot: Equatable, Sendable {
    var connected = false
    var name = "No controller"
    var product = ""
    var isDualSense = false
    var playerIndex = -1

    var cross = false
    var circle = false
    var square = false
    var triangle = false
    var dpadUp = false
    var dpadDown = false
    var dpadLeft = false
    var dpadRight = false
    var l1 = false
    var r1 = false
    var l3 = false
    var r3 = false
    var create = false
    var options = false
    var ps = false
    var touchpadClick = false

    var l2: Float = 0
    var r2: Float = 0
    var leftStick = SIMD2<Float>(repeating: 0)
    var rightStick = SIMD2<Float>(repeating: 0)

    var touch1 = TouchFinger(x: 0, y: 0, active: false)
    var touch2 = TouchFinger(x: 0, y: 0, active: false)

    var gravity = Vec3.zero
    var userAcceleration = Vec3.zero
    var rotationRate = Vec3.zero
    var hasMotion = false

    var batteryPercent: Int?
    var batteryCharging = false
    var batteryFull = false
    var batteryAvailable = false
    var batteryStateDescription = "Unknown"

    var events: [InputLogEvent] = []

    func hadButtonDown(from previous: DualSenseSnapshot) -> Bool {
        func rose(_ now: Bool, _ was: Bool) -> Bool { now && !was }
        if rose(cross, previous.cross) { return true }
        if rose(circle, previous.circle) { return true }
        if rose(square, previous.square) { return true }
        if rose(triangle, previous.triangle) { return true }
        if rose(dpadUp, previous.dpadUp) { return true }
        if rose(dpadDown, previous.dpadDown) { return true }
        if rose(dpadLeft, previous.dpadLeft) { return true }
        if rose(dpadRight, previous.dpadRight) { return true }
        if rose(l1, previous.l1) { return true }
        if rose(r1, previous.r1) { return true }
        if rose(l3, previous.l3) { return true }
        if rose(r3, previous.r3) { return true }
        if rose(create, previous.create) { return true }
        if rose(options, previous.options) { return true }
        if rose(ps, previous.ps) { return true }
        if rose(touchpadClick, previous.touchpadClick) { return true }
        if previous.l2 <= 0.2 && l2 > 0.2 { return true }
        if previous.r2 <= 0.2 && r2 > 0.2 { return true }
        return false
    }
}

@Observable
@MainActor
final class DualSenseMonitor {
    var snapshot = DualSenseSnapshot()
    var audioInputs: [String] = []
    var dualSenseAudioPresent = false
    var connectedDevices: [ConnectedBluetoothDevice] = []
    var selectedDeviceID: String?
    var appleTVSnapshot = AppleTVRemoteSnapshot()
    var deviceRecords: [DeviceRecord] = []
    var accessibilityTrusted = false
    let controlEngine = ControlEngine()
    private var suppressedDeviceKeys: Set<String> = []

    var selectedDevice: ConnectedBluetoothDevice? {
        if let selectedDeviceID, let match = connectedDevices.first(where: { $0.id == selectedDeviceID }) {
            return match
        }
        guard let record = selectedRecord else { return nil }
        return connectedDevices.first { recordsMatch(record, $0) }
    }

    var selectedKind: DeviceKind {
        if let selectedDevice { return selectedDevice.deviceKind }
        return selectedRecord?.kind ?? .unsupported
    }

    var selectedRecord: DeviceRecord? {
        guard let selectedDeviceID else { return nil }
        return deviceRecords.first { $0.id == selectedDeviceID }
    }

    var selectedProfile: MappingProfile {
        selectedRecord?.selectedProfile
            ?? MappingProfile.makeDefault(isAppleTVRemote: selectedKind == .appleTVRemote)
    }

    var sidebarDevices: [SidebarDevice] {
        var seen = Set<String>()
        var items: [SidebarDevice] = []
        for device in connectedDevices where device.isSupported && device.isConnected {
            seen.insert(device.id)
            let record = matchingRecord(for: device)
            items.append(
                SidebarDevice(
                    id: record?.id ?? device.id,
                    name: record?.name ?? device.name,
                    address: record?.address ?? device.address,
                    kind: record?.kind ?? device.deviceKind,
                    isConnected: true,
                    controlEnabled: record?.controlEnabled ?? false,
                    remembered: record?.remembered ?? false
                )
            )
        }
        for record in deviceRecords where record.remembered && !seen.contains(record.id) {
            items.append(
                SidebarDevice(
                    id: record.id,
                    name: record.name,
                    address: record.address,
                    kind: record.kind,
                    isConnected: false,
                    controlEnabled: record.controlEnabled,
                    remembered: true
                )
            )
        }
        return items
    }

    var addableDevices: [ConnectedBluetoothDevice] {
        connectedDevices.filter { device in
            device.isSupported && !sidebarDevices.contains { $0.id == device.id || namesMatch($0.name, device.name) }
        }
    }

    var unsupportedDevices: [ConnectedBluetoothDevice] {
        connectedDevices.filter { !$0.isSupported && $0.isConnected }
    }

    private var controller: GCController?
    private var pollTimer: Timer?
    private var controlActivity: NSObjectProtocol?
    private var previousButtons: [String: Bool] = [:]
    private var observers: [NSObjectProtocol] = []
    private var lastAudioProbe = Date.distantPast
    private var lastBatteryProbe = Date.distantPast
    private var lastTrustProbe = Date.distantPast
    private var didStart = false
    private var engines: [String: ControlEngine] = [:]
    private let haptics = DualSenseHaptics()
    private let hidBattery = DualSenseHIDBatteryReader()
    private let appleTVReader = AppleTVRemoteHIDReader()
    private let appleTVTouch = AppleTVTouchReader()
    private let appleTVBattery = AppleTVBatteryReader()

    func start() {
        guard !didStart else { return }
        didStart = true
        GCController.shouldMonitorBackgroundEvents = true
        hidBattery.start()
        appleTVReader.start()
        appleTVTouch.start()
        appleTVBattery.start()
        loadDeviceRecords()
        updateControlActivity()
        refreshAccessibilityTrust()
        refreshAudioInputs()
        refreshDevices()

        observers.append(
            NotificationCenter.default.addObserver(
                forName: .GCControllerDidConnect,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard notification.object is GCController else { return }
                Task { @MainActor in
                    self?.refreshDevices()
                    self?.attachPreferredController()
                }
            }
        )

        observers.append(
            NotificationCenter.default.addObserver(
                forName: .GCControllerDidDisconnect,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let controller = notification.object as? GCController else { return }
                Task { @MainActor in
                    self?.refreshDevices()
                    self?.handleDisconnect(controller)
                }
            }
        )

        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshAccessibilityTrust()
                }
            }
        )

        GCController.startWirelessControllerDiscovery(completionHandler: nil)
        attachPreferredController()

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.capture()
            }
        }
        timer.tolerance = 0
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        endControlActivity()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        hidBattery.stop()
        appleTVReader.stop()
        appleTVTouch.stop()
        appleTVBattery.stop()
        haptics.detach()
        GCController.stopWirelessControllerDiscovery()
    }

    func selectDevice(_ device: ConnectedBluetoothDevice) {
        selectDevice(id: device.id)
    }

    func selectDevice(id: String?) {
        guard selectedDeviceID != id else { return }
        selectedDeviceID = id
        controller = nil
        previousButtons = [:]
        snapshot = DualSenseSnapshot()
        appleTVSnapshot = AppleTVRemoteSnapshot()
        if let id {
            engines[id]?.reset()
            ensureRecord(for: id)
        }
        attachPreferredController()
        persistDeviceRecords()
    }

    func setControlEnabled(_ enabled: Bool) {
        updateSelectedRecord {
            $0.controlEnabled = enabled
            if enabled {
                $0.remembered = true
            }
        }
        if let id = selectedDeviceID {
            engine(for: id).reset()
        }
    }

    func setControlWhileFocused(_ enabled: Bool) {
        updateSelectedRecord { $0.controlWhileFocused = enabled }
    }

    func setHapticFeedback(_ enabled: Bool) {
        updateSelectedRecord { $0.hapticFeedback = enabled }
        if enabled {
            haptics.pulse()
        }
    }

    func setAnalogMode(_ mode: AnalogMode, for source: AnalogSource) {
        updateSelectedRecord { record in
            guard var profile = record.profiles.first(where: { $0.id == record.selectedProfileID }) else { return }
            profile.setMode(mode, for: source)
            if let index = record.profiles.firstIndex(where: { $0.id == profile.id }) {
                record.profiles[index] = profile
            }
        }
    }

    func setPointerAccelerationAmount(_ amount: Double) {
        updateSelectedRecord { record in
            guard var profile = record.profiles.first(where: { $0.id == record.selectedProfileID }) else { return }
            profile.pointerAccelerationAmount = min(max(amount, 0), 1)
            if let index = record.profiles.firstIndex(where: { $0.id == profile.id }) {
                record.profiles[index] = profile
            }
        }
    }

    func setPointerAcceleration(_ enabled: Bool) {
        updateSelectedRecord { record in
            guard var profile = record.profiles.first(where: { $0.id == record.selectedProfileID }) else { return }
            profile.pointerAcceleration = enabled
            if let index = record.profiles.firstIndex(where: { $0.id == profile.id }) {
                record.profiles[index] = profile
            }
        }
    }

    func setStickyTargeting(_ enabled: Bool) {
        updateSelectedRecord { record in
            guard var profile = record.profiles.first(where: { $0.id == record.selectedProfileID }) else { return }
            profile.stickyTargeting = enabled
            if let index = record.profiles.firstIndex(where: { $0.id == profile.id }) {
                record.profiles[index] = profile
            }
        }
        if !enabled {
            StickyTargeting.hide()
        }
    }

    func setButtonAction(_ action: ControlAction, for button: DeviceButton) {
        updateSelectedRecord { record in
            guard var profile = record.profiles.first(where: { $0.id == record.selectedProfileID }) else { return }
            profile.setBinding(action, for: button)
            if let index = record.profiles.firstIndex(where: { $0.id == profile.id }) {
                record.profiles[index] = profile
            }
        }
    }

    func selectProfile(_ id: String) {
        updateSelectedRecord { record in
            guard record.profiles.contains(where: { $0.id == id }) else { return }
            record.selectedProfileID = id
        }
        if let deviceID = selectedDeviceID {
            engine(for: deviceID).reset()
        }
    }

    func duplicateSelectedProfile() {
        updateSelectedRecord { record in
            let copy = record.selectedProfile.duplicated()
            record.profiles.append(copy)
            record.selectedProfileID = copy.id
        }
        if let deviceID = selectedDeviceID {
            engine(for: deviceID).reset()
        }
    }

    func addProfile() {
        updateSelectedRecord { record in
            let profile = MappingProfile.makeDefault(
                name: "Untitled",
                isAppleTVRemote: record.isAppleTVRemote
            )
            record.profiles.append(profile)
            record.selectedProfileID = profile.id
        }
        if let deviceID = selectedDeviceID {
            engine(for: deviceID).reset()
        }
    }

    func deleteSelectedProfile() {
        updateSelectedRecord { record in
            guard record.profiles.count > 1 else { return }
            record.profiles.removeAll { $0.id == record.selectedProfileID }
            record.selectedProfileID = record.profiles[0].id
        }
        if let deviceID = selectedDeviceID {
            engine(for: deviceID).reset()
        }
    }

    func renameSelectedProfile(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateSelectedRecord { record in
            guard var profile = record.profiles.first(where: { $0.id == record.selectedProfileID }) else { return }
            profile.name = trimmed
            if let index = record.profiles.firstIndex(where: { $0.id == profile.id }) {
                record.profiles[index] = profile
            }
        }
    }

    func updateSelectedSummary(_ summary: String) {
        updateSelectedRecord { record in
            guard var profile = record.profiles.first(where: { $0.id == record.selectedProfileID }) else { return }
            profile.summary = summary
            if let index = record.profiles.firstIndex(where: { $0.id == profile.id }) {
                record.profiles[index] = profile
            }
        }
    }

    func promptForAccessibility() {
        controlEngine.promptForAccessibility()
        refreshAccessibilityTrust()
    }

    func openAccessibilitySettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    func relaunchApp() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    func refreshAccessibilityTrust() {
        lastTrustProbe = Date()
        let trusted = controlEngine.isAccessibilityTrusted
        if accessibilityTrusted != trusted {
            accessibilityTrusted = trusted
        }
    }

    func addDevice(_ device: ConnectedBluetoothDevice) {
        suppressedDeviceKeys.remove(suppressionKey(for: device))
        persistSuppressedDevices()
        if let existing = matchingRecord(for: device) {
            selectDevice(id: existing.id)
            updateSelectedRecord { $0.remembered = true }
            return
        }
        if !deviceRecords.contains(where: { $0.id == device.id }) {
            deviceRecords.append(.make(from: device, remembered: true))
        } else if let index = deviceRecords.firstIndex(where: { $0.id == device.id }) {
            deviceRecords[index].remembered = true
            deviceRecords[index].name = device.name
            deviceRecords[index].address = device.address
            deviceRecords[index].kind = device.deviceKind
        }
        persistDeviceRecords()
        selectDevice(id: device.id)
    }

    func reloadDevices() {
        refreshDevices()
    }

    func removeSelectedDevice() {
        guard let id = selectedDeviceID else { return }
        if let record = selectedRecord {
            suppressedDeviceKeys.insert(suppressionKey(for: record))
            persistSuppressedDevices()
        }
        deviceRecords.removeAll { $0.id == id }
        engines[id] = nil
        persistDeviceRecords()
        if let connected = connectedDevices.first(where: { $0.id == id && $0.isSupported && $0.isConnected }) {
            selectedDeviceID = connected.id
            ensureRecord(for: connected.id, remembered: false)
        } else {
            selectedDeviceID = sidebarDevices.first?.id
            if let selectedDeviceID {
                ensureRecord(for: selectedDeviceID)
            }
        }
        controller = nil
        previousButtons = [:]
        snapshot = DualSenseSnapshot()
        appleTVSnapshot = AppleTVRemoteSnapshot()
        attachPreferredController()
    }

    private func attachPreferredController() {
        guard let selected = selectedDevice, selected.isSupported else {
            if controller != nil {
                controller = nil
                haptics.detach()
                snapshot = DualSenseSnapshot()
                previousButtons = [:]
            }
            return
        }

        if selected.deviceKind == .appleTVRemote {
            if controller != nil {
                controller = nil
                haptics.detach()
                snapshot = DualSenseSnapshot()
            }
            return
        }

        let dualSenses = GCController.controllers().filter { $0.extendedGamepad is GCDualSenseGamepad }
        let match = dualSenses.first { controller in
            (controller.vendorName ?? "") == selected.name
        } ?? dualSenses.first

        attachIfNeeded(match)
    }

    private func attachIfNeeded(_ incoming: GCController?) {
        guard let incoming, incoming.extendedGamepad is GCDualSenseGamepad else { return }
        if let current = controller, current == incoming { return }

        controller = incoming
        incoming.handlerQueue = .main
        incoming.motion?.sensorsActive = true
        previousButtons = [:]
        haptics.attach(incoming)
        capture()
    }

    private func handleDisconnect(_ disconnected: GCController) {
        if controller == disconnected {
            controller = nil
            haptics.detach()
            snapshot = DualSenseSnapshot()
            previousButtons = [:]
        }
        attachPreferredController()
    }

    private func capture() {
        if Date().timeIntervalSince(lastAudioProbe) > 2 {
            refreshAudioInputs()
            refreshDevices()
            lastAudioProbe = Date()
        }
        if Date().timeIntervalSince(lastTrustProbe) > 0.6 {
            refreshAccessibilityTrust()
        }

        if selectedKind == .appleTVRemote {
            captureAppleTV()
            return
        }

        guard let controller else {
            if snapshot.connected {
                snapshot = DualSenseSnapshot()
            }
            return
        }

        var next = DualSenseSnapshot()
        next.connected = true
        next.name = controller.vendorName ?? "Game Controller"
        next.product = controller.productCategory
        next.playerIndex = controller.playerIndex.rawValue
        next.hasMotion = controller.motion != nil

        applyBattery(to: &next, controller: controller)

        if let pad = controller.extendedGamepad as? GCDualSenseGamepad {
            next.isDualSense = true
            next.cross = pad.buttonA.isPressed
            next.circle = pad.buttonB.isPressed
            next.square = pad.buttonX.isPressed
            next.triangle = pad.buttonY.isPressed
            next.dpadUp = pad.dpad.up.isPressed
            next.dpadDown = pad.dpad.down.isPressed
            next.dpadLeft = pad.dpad.left.isPressed
            next.dpadRight = pad.dpad.right.isPressed
            next.l1 = pad.leftShoulder.isPressed
            next.r1 = pad.rightShoulder.isPressed
            next.l3 = isPressed(pad.leftThumbstickButton)
            next.r3 = isPressed(pad.rightThumbstickButton)
            next.create = isPressed(pad.buttonOptions)
            next.options = isPressed(pad.buttonMenu)
            next.touchpadClick = pad.touchpadButton.isPressed
            next.l2 = pad.leftTrigger.value
            next.r2 = pad.rightTrigger.value
            next.leftStick = SIMD2(pad.leftThumbstick.xAxis.value, pad.leftThumbstick.yAxis.value)
            next.rightStick = SIMD2(pad.rightThumbstick.xAxis.value, pad.rightThumbstick.yAxis.value)
            next.touch1 = finger(from: pad.touchpadPrimary)
            next.touch2 = finger(from: pad.touchpadSecondary)
        } else if let pad = controller.extendedGamepad {
            next.cross = pad.buttonA.isPressed
            next.circle = pad.buttonB.isPressed
            next.square = pad.buttonX.isPressed
            next.triangle = pad.buttonY.isPressed
            next.dpadUp = pad.dpad.up.isPressed
            next.dpadDown = pad.dpad.down.isPressed
            next.dpadLeft = pad.dpad.left.isPressed
            next.dpadRight = pad.dpad.right.isPressed
            next.l1 = pad.leftShoulder.isPressed
            next.r1 = pad.rightShoulder.isPressed
            next.l2 = pad.leftTrigger.value
            next.r2 = pad.rightTrigger.value
            next.leftStick = SIMD2(pad.leftThumbstick.xAxis.value, pad.leftThumbstick.yAxis.value)
            next.rightStick = SIMD2(pad.rightThumbstick.xAxis.value, pad.rightThumbstick.yAxis.value)
        }

        if let home = controller.physicalInputProfile.buttons[GCInputButtonHome] {
            next.ps = home.isPressed
        }

        if let motion = controller.motion {
            next.gravity = Vec3(x: motion.gravity.x, y: motion.gravity.y, z: motion.gravity.z)
            next.userAcceleration = Vec3(
                x: motion.userAcceleration.x,
                y: motion.userAcceleration.y,
                z: motion.userAcceleration.z
            )
            next.rotationRate = Vec3(
                x: motion.rotationRate.x,
                y: motion.rotationRate.y,
                z: motion.rotationRate.z
            )
        }

        next.events = updatedEvents(from: next)
        if selectedRecord?.hapticFeedbackEnabled == true, next.hadButtonDown(from: snapshot) {
            haptics.pulse()
        }
        snapshot = next
        ingestControl(ControlFrameBuilder.make(from: next))
    }

    private func captureAppleTV() {
        guard let selected = selectedDevice, selected.deviceKind == .appleTVRemote else {
            if appleTVSnapshot.connected {
                appleTVSnapshot = AppleTVRemoteSnapshot()
            }
            return
        }

        appleTVReader.applyTouch(appleTVTouch.snapshot)
        var next = appleTVReader.snapshot
        next.connected = true
        next.name = selected.name
        next.product = "Siri Remote A2540"
        if Date().timeIntervalSince(lastBatteryProbe) > 2 {
            lastBatteryProbe = Date()
            appleTVBattery.refresh()
        }
        if !next.batteryAvailable,
           let percent = appleTVBattery.percent(serial: selected.name, address: selected.address) {
            appleTVReader.applyBatteryPercent(percent)
            next.batteryAvailable = true
            next.batteryPercent = percent
            next.batteryFull = percent >= 95
            next.batteryStateDescription = next.batteryFull ? "Full" : "Discharging"
        }
        next.events = updatedAppleTVEvents(from: next)
        appleTVSnapshot = next
        ingestControl(ControlFrameBuilder.make(from: next))
    }

    private func ingestControl(_ frame: ControlFrame) {
        guard let deviceID = selectedDeviceID else { return }
        ensureRecord(for: deviceID)
        guard let record = deviceRecords.first(where: { $0.id == deviceID }) else { return }
        let engine = engine(for: deviceID)
        engine.profile = record.selectedProfile
        engine.enabled = record.controlEnabled
        engine.postsWhenHostIsActive = record.controlWhileFocused
        engine.process(frame, hostIsActive: NSApp.isActive)
    }

    private func engine(for deviceID: String) -> ControlEngine {
        if let existing = engines[deviceID] { return existing }
        let created = ControlEngine(profile: selectedProfile)
        engines[deviceID] = created
        return created
    }

    private func ensureRecord(for id: String, remembered: Bool = false) {
        if let index = deviceRecords.firstIndex(where: { $0.id == id }) {
            if remembered {
                deviceRecords[index].remembered = true
            }
            return
        }
        guard let device = connectedDevices.first(where: { $0.id == id && $0.isSupported }) else { return }
        deviceRecords.append(.make(from: device, remembered: remembered))
    }

    private func matchingRecord(for device: ConnectedBluetoothDevice) -> DeviceRecord? {
        if let exact = deviceRecords.first(where: { $0.id == device.id }) {
            return exact
        }
        return deviceRecords.first { recordsMatch($0, device) }
    }

    private func matchingRecordIndex(for device: ConnectedBluetoothDevice) -> Int? {
        if let index = deviceRecords.firstIndex(where: { $0.id == device.id }) {
            return index
        }
        return deviceRecords.firstIndex { recordsMatch($0, device) }
    }

    private func recordsMatch(_ record: DeviceRecord, _ device: ConnectedBluetoothDevice) -> Bool {
        if record.id == device.id { return true }
        guard record.kind == device.deviceKind else { return false }
        if namesMatch(record.name, device.name) { return true }
        return isConcreteAddress(record.address) && record.address == device.address
    }

    private func namesMatch(_ lhs: String, _ rhs: String) -> Bool {
        lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }

    private func isConcreteAddress(_ address: String) -> Bool {
        !(address.isEmpty
            || address == "Bluetooth"
            || address == "USB"
            || address == "Game Controller")
    }

    private func suppressionKey(for device: ConnectedBluetoothDevice) -> String {
        suppressionKey(kind: device.deviceKind, name: device.name, id: device.id)
    }

    private func suppressionKey(for record: DeviceRecord) -> String {
        suppressionKey(kind: record.kind, name: record.name, id: record.id)
    }

    private func suppressionKey(kind: DeviceKind, name: String, id: String) -> String {
        if kind == .dualSense || kind == .dualSenseEdge {
            return "dualsense:\(name.lowercased())"
        }
        return id
    }

    private func rememberConnectedDevice(_ device: ConnectedBluetoothDevice) {
        if suppressedDeviceKeys.contains(suppressionKey(for: device)) { return }
        if let index = matchingRecordIndex(for: device) {
            deviceRecords[index].name = device.name
            if isConcreteAddress(device.address) {
                deviceRecords[index].address = device.address
            }
            deviceRecords[index].kind = device.deviceKind
            deviceRecords[index].remembered = true
            return
        }
        deviceRecords.append(.make(from: device, remembered: true))
    }

    private func updateSelectedRecord(_ mutate: (inout DeviceRecord) -> Void) {
        guard let id = selectedDeviceID else { return }
        ensureRecord(for: id)
        guard let index = deviceRecords.firstIndex(where: { $0.id == id }) else { return }
        mutate(&deviceRecords[index])
        persistDeviceRecords()
    }

    private func loadDeviceRecords() {
        if let data = UserDefaults.standard.data(forKey: Self.deviceRecordsDefaultsKey),
           let decoded = try? JSONDecoder().decode([DeviceRecord].self, from: data) {
            deviceRecords = decoded.map { record in
                var next = record
                next.remembered = true
                if next.profiles.isEmpty {
                    let profile = MappingProfile.makeDefault(isAppleTVRemote: next.isAppleTVRemote)
                    next.profiles = [profile]
                    next.selectedProfileID = profile.id
                }
                if next.isAppleTVRemote {
                    for index in next.profiles.indices {
                        if next.profiles[index].appleTVClickpad != .off {
                            next.profiles[index].appleTVClickpad = .pointer
                        }
                        if next.profiles[index].appleTVWheel == .volume
                            || next.profiles[index].appleTVWheel == .pointer {
                            next.profiles[index].appleTVWheel = .scroll
                        }
                        if next.profiles[index].bindings[.clickSelect] == .returnKey {
                            next.profiles[index].bindings[.clickSelect] = .mouseLeft
                        }
                        if next.profiles[index].bindings[.clickSelectLong] == nil {
                            next.profiles[index].bindings[.clickSelectLong] = .mouseRight
                        }
                    }
                }
                return next
            }
        }
        if let id = UserDefaults.standard.string(forKey: Self.selectedDeviceDefaultsKey) {
            selectedDeviceID = id
        }
        if let suppressed = UserDefaults.standard.array(forKey: Self.suppressedDevicesDefaultsKey) as? [String] {
            suppressedDeviceKeys = Set(suppressed)
        }
    }

    private func persistDeviceRecords() {
        let saved = deviceRecords.filter(\.remembered)
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: Self.deviceRecordsDefaultsKey)
        }
        UserDefaults.standard.set(selectedDeviceID, forKey: Self.selectedDeviceDefaultsKey)
        updateControlActivity()
    }

    private func updateControlActivity() {
        let needsActivity = deviceRecords.contains { $0.controlEnabled }
        if needsActivity {
            if controlActivity == nil {
                controlActivity = ProcessInfo.processInfo.beginActivity(
                    options: [
                        .userInitiated,
                        .latencyCritical,
                        .idleSystemSleepDisabled,
                    ],
                    reason: "VibeRemote is posting controller input"
                )
            }
            return
        }
        endControlActivity()
    }

    private func endControlActivity() {
        if let controlActivity {
            ProcessInfo.processInfo.endActivity(controlActivity)
            self.controlActivity = nil
        }
    }

    private func persistSuppressedDevices() {
        UserDefaults.standard.set(Array(suppressedDeviceKeys), forKey: Self.suppressedDevicesDefaultsKey)
    }

    private static let deviceRecordsDefaultsKey = "iremote.deviceRecords.v1"
    private static let selectedDeviceDefaultsKey = "iremote.selectedDeviceID"
    private static let suppressedDevicesDefaultsKey = "iremote.suppressedDevices.v1"

    private func applyBattery(to next: inout DualSenseSnapshot, controller: GCController) {
        if let percent = hidBattery.percent {
            next.batteryAvailable = true
            next.batteryPercent = percent
            next.batteryCharging = hidBattery.isCharging
            next.batteryFull = hidBattery.isFull
            if hidBattery.isFull {
                next.batteryStateDescription = "Full"
            } else if hidBattery.isCharging {
                next.batteryStateDescription = "Charging"
            } else {
                next.batteryStateDescription = "Discharging"
            }
            return
        }

        guard let battery = controller.battery, battery.batteryState != .unknown else { return }
        next.batteryAvailable = true
        next.batteryPercent = Int((battery.batteryLevel * 100).rounded())
        switch battery.batteryState {
        case .charging:
            next.batteryCharging = true
            next.batteryStateDescription = "Charging"
        case .full:
            next.batteryFull = true
            next.batteryStateDescription = "Full"
        case .discharging:
            next.batteryStateDescription = "Discharging"
        default:
            next.batteryStateDescription = "Unknown"
        }
    }

    private func isPressed(_ button: GCControllerButtonInput?) -> Bool {
        button?.isPressed ?? false
    }

    private func finger(from pad: GCControllerDirectionPad) -> TouchFinger {
        let x = pad.xAxis.value
        let y = pad.yAxis.value
        let digital = pad.up.isPressed || pad.down.isPressed || pad.left.isPressed || pad.right.isPressed
        let analog = abs(x) > 0.001 || abs(y) > 0.001
        return TouchFinger(x: x, y: y, active: digital || analog)
    }

    private func updatedEvents(from next: DualSenseSnapshot) -> [InputLogEvent] {
        let current: [(String, Bool)] = [
            ("Cross", next.cross),
            ("Circle", next.circle),
            ("Square", next.square),
            ("Triangle", next.triangle),
            ("D-pad Up", next.dpadUp),
            ("D-pad Down", next.dpadDown),
            ("D-pad Left", next.dpadLeft),
            ("D-pad Right", next.dpadRight),
            ("L1", next.l1),
            ("R1", next.r1),
            ("L2", next.l2 > 0.15),
            ("R2", next.r2 > 0.15),
            ("L3", next.l3),
            ("R3", next.r3),
            ("Create", next.create),
            ("Options", next.options),
            ("PS", next.ps),
            ("Touchpad click", next.touchpadClick),
            ("Touch 1", next.touch1.active),
            ("Touch 2", next.touch2.active)
        ]

        var events = snapshot.events
        for (label, pressed) in current {
            if previousButtons[label] != pressed {
                events.insert(
                    InputLogEvent(id: UUID(), date: Date(), label: label, pressed: pressed),
                    at: 0
                )
            }
            previousButtons[label] = pressed
        }
        if events.count > 40 {
            events = Array(events.prefix(40))
        }
        return events
    }

    private func updatedAppleTVEvents(from next: AppleTVRemoteSnapshot) -> [InputLogEvent] {
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

        var events = appleTVSnapshot.events
        if next.touchActive != appleTVSnapshot.touchActive {
            events.insert(
                InputLogEvent(id: UUID(), date: Date(), label: "Clickpad finger", pressed: next.touchActive),
                at: 0
            )
        }
        if next.wheelActive != appleTVSnapshot.wheelActive {
            events.insert(
                InputLogEvent(id: UUID(), date: Date(), label: "Click wheel", pressed: next.wheelActive),
                at: 0
            )
        }
        if next.micActive != appleTVSnapshot.micActive {
            events.insert(
                InputLogEvent(id: UUID(), date: Date(), label: "Siri mic HID", pressed: next.micActive),
                at: 0
            )
        }
        if next.lastHIDSignal != "Press a button",
           next.lastHIDSignal != appleTVSnapshot.lastHIDSignal {
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

    private func refreshDevices() {
        var devices = BluetoothDeviceCatalog.availableDevices()
        for index in devices.indices {
            if let record = matchingRecord(for: devices[index]) {
                devices[index].id = record.id
            }
        }
        connectedDevices = devices

        for device in devices where device.isSupported && device.isConnected {
            rememberConnectedDevice(device)
        }

        if let selectedDeviceID, sidebarDevices.contains(where: { $0.id == selectedDeviceID }) {
            ensureRecord(for: selectedDeviceID)
            persistDeviceRecords()
            return
        }

        selectedDeviceID = sidebarDevices.first?.id
        if let selectedDeviceID {
            ensureRecord(for: selectedDeviceID)
        }
        persistDeviceRecords()
    }

    private func refreshAudioInputs() {
        let names = AudioInputProbe.inputDeviceNames()
        audioInputs = names
        dualSenseAudioPresent = names.contains { name in
            let lowered = name.lowercased()
            return lowered.contains("dualsense")
                || lowered.contains("wireless controller")
                || lowered.contains("sony")
        }
    }
}
