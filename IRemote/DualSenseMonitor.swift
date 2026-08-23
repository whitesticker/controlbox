import AppKit
import CoreGraphics
import Foundation
import GameController
import IOKit.hid
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
    var mxMasterSnapshot = MXMasterSnapshot()
    var deviceRecords: [DeviceRecord] = []
    var accessibilityTrusted = false
    var inputMonitoringTrusted = false
    let controlEngine = ControlEngine()

    var allPermissionsGranted: Bool {
        accessibilityTrusted && inputMonitoringTrusted
    }
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
            ?? MappingProfile.makeDefault(
                isAppleTVRemote: selectedKind == .appleTVRemote,
                isMXMaster: selectedKind.isMXMaster
            )
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
            device.isSupported && !sidebarDevices.contains { row in
                if row.id == device.id { return true }
                if DeviceIdentity.same(row.address, device.address) { return true }
                if device.deviceKind.isMXMaster { return false }
                return namesMatch(row.name, device.name)
            }
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
    private var lastDeviceProbe = Date.distantPast
    private var lastAppleTVTouchRescan = Date.distantPast
    private var appleTVHIDWasLive = false
    private var didStart = false
    private var engines: [String: ControlEngine] = [:]
    private let haptics = DualSenseHaptics()
    private let hidBattery = DualSenseHIDBatteryReader()
    private let appleTVReader = AppleTVRemoteHIDReader()
    private let appleTVTouch = AppleTVTouchReader()
    private let appleTVBattery = AppleTVBatteryReader()
    private let mx3Reader = LogitechMXMasterReader(model: MXMaster3Support.model)
    private let mx4Reader = LogitechMXMasterReader(model: MXMaster4Support.model)
    private let mouseScrollTap = MouseScrollTap()

    private var mxReaders: [LogitechMXMasterReader] { [mx3Reader, mx4Reader] }

    func start() {
        guard !didStart else { return }
        didStart = true
        GCController.shouldMonitorBackgroundEvents = true
        hidBattery.start()
        appleTVReader.start()
        appleTVTouch.start()
        appleTVBattery.start()
        mx3Reader.start()
        mx4Reader.start()
        loadDeviceRecords()
        updateControlActivity()
        refreshPermissions()
        refreshAudioInputs()
        DispatchQueue.main.async { [weak self] in
            self?.refreshDevices()
            self?.lastDeviceProbe = Date()
        }

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
                    self?.refreshPermissions()
                }
            }
        )

        GCController.startWirelessControllerDiscovery(completionHandler: nil)
        attachPreferredController()

        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
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
        mx3Reader.stop()
        mx4Reader.stop()
        mouseScrollTap.stop()
        haptics.detach()
        GCController.stopWirelessControllerDiscovery()
    }

    func selectDevice(_ device: ConnectedBluetoothDevice) {
        selectDevice(id: device.id)
    }

    func selectDevice(id: String?) {
        guard selectedDeviceID != id else { return }
        selectedDeviceID = id
        previousButtons = [:]
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

    func setPointerSpeed(_ speed: Double) {
        updateMXSharedOrSelected { $0.pointerSpeed = min(max(speed, 0), 1) }
    }

    func setHapticGestureSpeed(_ speed: Double) {
        updateSelectedProfile { $0.hapticGestureSpeed = min(max(speed, 0), 1) }
    }

    func setWheelScrollSpeed(_ speed: Double) {
        updateMXSharedOrSelected { $0.wheelScrollSpeed = min(max(speed, 0), 1) }
    }

    func setThumbScrollSpeed(_ speed: Double) {
        updateMXSharedOrSelected { $0.thumbScrollSpeed = min(max(speed, 0), 1) }
    }

    func setNaturalScrolling(_ enabled: Bool) {
        updateMXSharedOrSelected { $0.naturalScrolling = enabled }
    }

    func setSensorDPI(_ dpi: Int) {
        updateSelectedProfile { $0.sensorDPI = MappingProfile.clampDisplayedDPI(dpi) }
    }

    func setSmoothScrolling(_ enabled: Bool) {
        updateMXSharedOrSelected { $0.smoothScrolling = enabled }
    }

    func setGesturePreset(_ preset: GesturePreset, for button: DeviceButton) {
        updateSelectedProfile { $0.setGestureSet(.named(preset), for: button) }
    }

    func setGestureAction(_ action: ControlAction, slot: GestureSlot, for button: DeviceButton) {
        updateSelectedProfile { $0.setGestureAction(action, slot: slot, for: button) }
    }

    private func updateSelectedProfile(_ mutate: (inout MappingProfile) -> Void) {
        updateSelectedRecord { record in
            guard var profile = record.profiles.first(where: { $0.id == record.selectedProfileID }) else { return }
            mutate(&profile)
            if let index = record.profiles.firstIndex(where: { $0.id == profile.id }) {
                record.profiles[index] = profile
            }
        }
    }

    private func updateMXSharedOrSelected(_ mutate: (inout MappingProfile) -> Void) {
        updateSelectedProfile(mutate)
        guard selectedRecord?.isMXMaster == true, let source = selectedRecord?.selectedProfile else { return }
        propagateSharedMXPointerScroll(from: source)
    }

    private func propagateSharedMXPointerScroll(from source: MappingProfile) {
        var changed = false
        for index in deviceRecords.indices where deviceRecords[index].isMXMaster {
            let selectedID = deviceRecords[index].selectedProfileID
            guard let profileIndex = deviceRecords[index].profiles.firstIndex(where: { $0.id == selectedID }) else {
                continue
            }
            var profile = deviceRecords[index].profiles[profileIndex]
            if Self.sharedMXPointerScrollMatches(profile, source) { continue }
            Self.applySharedMXPointerScroll(&profile, from: source)
            deviceRecords[index].profiles[profileIndex] = profile
            changed = true
        }
        if changed {
            persistDeviceRecords()
        }
    }

    private static func sharedMXPointerScrollMatches(_ profile: MappingProfile, _ source: MappingProfile) -> Bool {
        profile.pointerSpeed == source.pointerSpeed
            && profile.naturalScrolling == source.naturalScrolling
            && profile.smoothScrolling == source.smoothScrolling
            && profile.wheelScrollSpeed == source.wheelScrollSpeed
            && profile.thumbScrollSpeed == source.thumbScrollSpeed
    }

    private static func applySharedMXPointerScroll(_ profile: inout MappingProfile, from source: MappingProfile) {
        profile.pointerSpeed = source.pointerSpeed
        profile.naturalScrolling = source.naturalScrolling
        profile.smoothScrolling = source.smoothScrolling
        profile.wheelScrollSpeed = source.wheelScrollSpeed
        profile.thumbScrollSpeed = source.thumbScrollSpeed
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
                isAppleTVRemote: record.isAppleTVRemote,
                isMXMaster: record.isMXMaster
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
        refreshPermissions()
    }

    func promptForInputMonitoring() {
        if IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) == false {
            _ = CGRequestListenEventAccess()
        }
        refreshPermissions()
    }

    func openAccessibilitySettings() {
        openPrivacySettings(anchors: [
            "Privacy_Accessibility"
        ])
    }

    func openInputMonitoringSettings() {
        openPrivacySettings(anchors: [
            "Privacy_ListenEvent"
        ])
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

    func refreshPermissions() {
        lastTrustProbe = Date()
        let accessibility = controlEngine.isAccessibilityTrusted
        if accessibilityTrusted != accessibility {
            accessibilityTrusted = accessibility
        }
        let inputMonitoring = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        if inputMonitoringTrusted != inputMonitoring {
            inputMonitoringTrusted = inputMonitoring
        }
    }

    func refreshAccessibilityTrust() {
        refreshPermissions()
    }

    private func openPrivacySettings(anchors: [String]) {
        let prefixes = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?",
            "x-apple.systempreferences:com.apple.preference.security?"
        ]
        for anchor in anchors {
            for prefix in prefixes {
                if let url = URL(string: prefix + anchor), NSWorkspace.shared.open(url) {
                    return
                }
            }
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
        let dualSenses = GCController.controllers().filter { $0.extendedGamepad is GCDualSenseGamepad }
        guard !dualSenses.isEmpty else {
            if controller != nil {
                controller = nil
                haptics.detach()
                snapshot = DualSenseSnapshot()
                previousButtons = [:]
            }
            return
        }
        let preferredName = deviceRecords.first {
            $0.kind == .dualSense || $0.kind == .dualSenseEdge
        }?.name
        let match = dualSenses.first { controller in
            (controller.vendorName ?? "") == preferredName
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
            mergeMXMasterStatus()
            lastAudioProbe = Date()
        }
        if Date().timeIntervalSince(lastDeviceProbe) > 15, !isMenuTracking {
            refreshDevices()
            lastDeviceProbe = Date()
        }
        if Date().timeIntervalSince(lastTrustProbe) > 0.6 {
            refreshPermissions()
        }

        captureDualSense()
        captureMXMasters()
        if appleTVShouldCapture {
            captureAppleTV()
        } else if appleTVSnapshot.connected {
            appleTVSnapshot = AppleTVRemoteSnapshot()
            appleTVHIDWasLive = false
        }
    }

    private func captureDualSense() {
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
        if liveDualSenseRecord()?.hapticFeedbackEnabled == true, next.hadButtonDown(from: snapshot) {
            haptics.pulse()
        }
        snapshot = next
        if let record = liveDualSenseRecord() {
            ingestControl(ControlFrameBuilder.make(from: next), record: record)
        }
    }

    private func captureAppleTV() {
        let hidLive = appleTVReader.snapshot.connected
        if hidLive && !appleTVHIDWasLive {
            appleTVTouch.restart()
            lastAppleTVTouchRescan = Date()
        } else if hidLive, !appleTVTouch.snapshot.available,
                  Date().timeIntervalSince(lastAppleTVTouchRescan) > 2 {
            appleTVTouch.restart()
            lastAppleTVTouchRescan = Date()
        }
        appleTVHIDWasLive = hidLive

        let device = connectedDevices.first(where: {
            $0.deviceKind == .appleTVRemote && $0.isConnected
        }) ?? connectedDevices.first(where: { $0.deviceKind == .appleTVRemote })
        guard hidLive || device != nil || selectedKind == .appleTVRemote else {
            if appleTVSnapshot.connected {
                appleTVSnapshot = AppleTVRemoteSnapshot()
            }
            return
        }

        appleTVReader.applyTouch(appleTVTouch.snapshot)
        var next = appleTVReader.snapshot
        next.connected = hidLive || device?.isConnected == true
        next.name = device?.name ?? next.name
        next.product = "Siri Remote A2540"
        if Date().timeIntervalSince(lastBatteryProbe) > 2 {
            lastBatteryProbe = Date()
            appleTVBattery.refresh()
        }
        if !next.batteryAvailable,
           let percent = appleTVBattery.percent(
               serial: device?.name ?? next.name,
               address: device?.address ?? ""
           ) {
            appleTVReader.applyBatteryPercent(percent)
            next.batteryAvailable = true
            next.batteryPercent = percent
            next.batteryFull = percent >= 95
            next.batteryStateDescription = next.batteryFull ? "Full" : "Discharging"
        }
        next.events = updatedAppleTVEvents(from: next)
        appleTVSnapshot = next
        if let record = liveAppleTVRecord() {
            ingestControl(ControlFrameBuilder.make(from: next), record: record)
        }
    }

    private func captureMXMasters() {
        for reader in mxReaders {
            reader.pollGesturePointer()
            let next = reader.current
            if let record = liveMXRecord(for: next) {
                ingestMX(reader, record, ControlFrameBuilder.make(from: next))
            }
            _ = reader.consumePendingGesture()
            reader.consumePendingScroll()
        }
        mxMasterSnapshot = displayMXSnapshot()
        applyMouseScrollTap()
    }

    private func reader(for kind: DeviceKind) -> LogitechMXMasterReader? {
        if kind.isMXMaster3Family { return mx3Reader }
        if kind == .logitechMXMaster4 || kind == .logitechMXMaster { return mx4Reader }
        return nil
    }

    private func displayMXSnapshot() -> MXMasterSnapshot {
        if selectedKind.isMXMaster, let reader = reader(for: selectedKind) {
            return reader.current
        }
        return mxReaders.map(\.current).first(where: \.connected) ?? MXMasterSnapshot()
    }

    private func ingestMX(_ reader: LogitechMXMasterReader, _ record: DeviceRecord, _ frame: ControlFrame) {
        let engine = engine(for: record.id)
        engine.profile = record.selectedProfile
        engine.enabled = record.controlEnabled
        engine.postsWhenHostIsActive = record.controlWhileFocused
        reader.injectEnabled = record.controlEnabled
        reader.wheelsEnabled = accessibilityTrusted
        reader.setGestureOwners(record.selectedProfile.mxGestureOwners)
        reader.applySensorDPI(record.selectedProfile.resolvedSensorDPI)
        reader.applyPointerSpeed(record.selectedProfile.resolvedPointerSpeed)
        reader.applyHapticGestureSpeed(record.selectedProfile.resolvedHapticGestureSpeed)
        engine.process(frame, hostIsActive: NSApp.isActive)
    }

    var controllingMXRecords: [DeviceRecord] {
        mxReaders.compactMap { liveMXRecord(for: $0.current) }.filter(\.controlEnabled)
    }

    var sharedMXScrollRecord: DeviceRecord? {
        if selectedKind.isMXMaster, let selected = selectedRecord, selected.controlEnabled {
            return selected
        }
        return controllingMXRecords.first
    }

    private func applyMouseScrollTap() {
        guard let record = sharedMXScrollRecord, accessibilityTrusted else {
            mouseScrollTap.setActive(false)
            return
        }
        let natural = record.selectedProfile.resolvedNaturalScrolling
        let smooth = record.selectedProfile.resolvedSmoothScrolling
        mouseScrollTap.wantNatural = natural
        mouseScrollTap.smoothScrolling = smooth
        mouseScrollTap.verticalScale = 0.05 + record.selectedProfile.appliedWheelScrollSpeed * 0.55
        mouseScrollTap.horizontalScale = 0.05 + record.selectedProfile.appliedThumbScrollSpeed * 0.55
        mouseScrollTap.setActive(true)
        for reader in mxReaders where reader.current.connected {
            reader.applySmoothScrolling(smooth)
            reader.applyScrollDirection(natural)
        }
        propagateSharedMXPointerScroll(from: record.selectedProfile)
    }

    private func ingestControl(_ frame: ControlFrame, record: DeviceRecord) {
        let engine = engine(for: record.id)
        engine.profile = record.selectedProfile
        engine.enabled = record.controlEnabled
        engine.postsWhenHostIsActive = record.controlWhileFocused
        if record.isMXMaster {
            return
        }
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
        if DeviceIdentity.same(record.address, device.address) { return true }
        guard record.kind == device.deviceKind else { return false }
        if record.kind.isMXMaster {
            if DeviceIdentity.isConcrete(record.address), DeviceIdentity.isConcrete(device.address) {
                return false
            }
            return namesMatch(record.name, device.name)
        }
        if namesMatch(record.name, device.name) { return true }
        return isConcreteAddress(record.address) && record.address == device.address
    }

    func isLiveMXSelection(_ live: MXMasterSnapshot? = nil) -> Bool {
        guard let record = selectedRecord else { return false }
        return isLiveMXDevice(
            kind: record.kind,
            address: record.address,
            name: record.name,
            live: live ?? mxMasterSnapshot
        )
    }

    private var appleTVShouldCapture: Bool {
        appleTVReader.snapshot.connected
            || selectedKind == .appleTVRemote
            || connectedDevices.contains { $0.deviceKind == .appleTVRemote && $0.isConnected }
    }

    private func liveAppleTVRecord() -> DeviceRecord? {
        if let match = deviceRecords.first(where: { $0.kind == .appleTVRemote }) {
            return match
        }
        if let device = connectedDevices.first(where: { $0.deviceKind == .appleTVRemote && $0.isConnected }) {
            ensureRecord(for: device.id)
            return matchingRecord(for: device) ?? deviceRecords.first { $0.id == device.id }
        }
        return nil
    }

    private func liveDualSenseRecord() -> DeviceRecord? {
        if let name = controller?.vendorName,
           let match = deviceRecords.first(where: {
               ($0.kind == .dualSense || $0.kind == .dualSenseEdge) && namesMatch($0.name, name)
           }) {
            return match
        }
        return deviceRecords.first { $0.kind == .dualSense || $0.kind == .dualSenseEdge }
    }

    private func liveMXRecord(for live: MXMasterSnapshot) -> DeviceRecord? {
        guard live.connected else { return nil }
        if let match = deviceRecords.first(where: {
            isLiveMXDevice(kind: $0.kind, address: $0.address, name: $0.name, live: live)
        }) {
            return match
        }
        if let device = connectedDevices.first(where: {
            isLiveMXDevice(kind: $0.deviceKind, address: $0.address, name: $0.name, live: live)
        }) {
            ensureRecord(for: device.id)
            return matchingRecord(for: device) ?? deviceRecords.first { $0.id == device.id }
        }
        return nil
    }

    private func isLiveMXDevice(kind: DeviceKind, address: String, name: String, live: MXMasterSnapshot) -> Bool {
        guard live.connected else { return false }
        if DeviceIdentity.same(address, live.address) { return true }
        if DeviceIdentity.isConcrete(address), DeviceIdentity.isConcrete(live.address) {
            return false
        }
        return kind == live.kind && namesMatch(name, live.name)
    }

    private func namesMatch(_ lhs: String, _ rhs: String) -> Bool {
        lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }

    private func isConcreteAddress(_ address: String) -> Bool {
        DeviceIdentity.isConcrete(address)
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
                    let profile = MappingProfile.makeDefault(
                        isAppleTVRemote: next.isAppleTVRemote,
                        isMXMaster: next.isMXMaster
                    )
                    next.profiles = [profile]
                    next.selectedProfileID = profile.id
                }
                if next.isMXMaster {
                    for index in next.profiles.indices {
                        next.profiles[index].restrictGesturesToHapticPad()
                    }
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
        for reader in mxReaders {
            mergeLiveMX(reader.current, into: &devices)
        }
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

    private var isMenuTracking: Bool {
        NSApp.windows.contains { window in
            let name = NSStringFromClass(type(of: window))
            return name.contains("NSMenu") || name.contains("Popup")
        }
    }

    private func mergeMXMasterStatus() {
        for reader in mxReaders {
            mergeLiveMX(reader.current, into: &connectedDevices)
        }
    }

    private func mergeLiveMX(_ live: MXMasterSnapshot, into devices: inout [ConnectedBluetoothDevice]) {
        guard live.connected else { return }
        if let index = devices.firstIndex(where: {
            isLiveMXDevice(kind: $0.deviceKind, address: $0.address, name: $0.name, live: live)
        }) {
            devices[index].deviceKind = live.kind
            devices[index].isConnected = true
            devices[index].name = live.name
            if DeviceIdentity.isConcrete(live.address) {
                devices[index].address = live.address
            }
            devices[index].detail = live.status
            return
        }
        devices.append(
            ConnectedBluetoothDevice(
                id: "mx:\(DeviceIdentity.isConcrete(live.address) ? live.address : live.name)",
                name: live.name,
                address: DeviceIdentity.isConcrete(live.address) ? live.address : DeviceIdentity.hidFallback,
                deviceKind: live.kind,
                detail: live.status,
                isConnected: true
            )
        )
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
