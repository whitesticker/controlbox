import AppKit
import CoreGraphics
import Foundation
import GameController
import IOKit.hid
import ControlBoxCore
import Observation
import ServiceManagement

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
    var mxKeyboardSnapshot = MXKeyboardSnapshot()
    var deviceRecords: [DeviceRecord] = []
    var accessibilityTrusted = false
    var inputMonitoringTrusted = false
    var backgroundAllowed = false
    var launchAtLoginOn = false
    var backgroundNeedsApproval = false
    var screenCaptureTrusted = false
    var screenRecordingTrusted = false
    let controlEngine = ControlEngine()

    var allPermissionsGranted: Bool {
        accessibilityTrusted && inputMonitoringTrusted
    }

    var needsRelaunchForPermissions: Bool {
        !accessibilityTrusted || !inputMonitoringTrusted
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
                isMXMaster: selectedKind.isMXMaster,
                isMXKeyboard: selectedKind.isMXKeyboard
            )
    }

    var hasMXMaster: Bool {
        deviceRecords.contains(where: \.isMXMaster)
    }

    var macMouseSettings = MacMouseSettings.load(seedingFrom: nil)

    var macMouseProfile: MappingProfile {
        macMouseSettings.asProfile
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

    private var pollTimer: Timer?
    private var controlActivity: NSObjectProtocol?
    private var observers: [NSObjectProtocol] = []
    private var lastAudioProbe = Date.distantPast
    private var lastTrustProbe = Date.distantPast
    private var lastDeviceProbe = Date.distantPast
    private var lastMotionPublish = Date.distantPast
    private var lastScrollTapSignature = ""
    private var lastWindowGrabSignature = ""
    private var lastAppliedSystemPointerSpeed = -1.0
    private var didStart = false
    private var engines: [String: ControlEngine] = [:]
    private let dualSense = DualSenseSession()
    private let appleTV = AppleTVRemoteSession()
    private let keyboard = MXKeyboardSession()
    private let mx3Reader = LogitechMXMasterReader(model: MXMaster3Support.model)
    private let mx4Reader = LogitechMXMasterReader(model: MXMaster4Support.model)
    private let mouseScrollTap = MouseScrollTap()

    private var mxReaders: [LogitechMXMasterReader] { [mx3Reader, mx4Reader] }
    private var familySessions: [any DeviceFamilySession] { [dualSense, appleTV, keyboard] }

    func start() {
        guard !didStart else { return }
        didStart = true
        familySessions.forEach { $0.start() }
        mx3Reader.start()
        mx4Reader.start()
        loadDeviceRecords()
        macMouseSettings = MacMouseSettings.load(
            seedingFrom: deviceRecords.first(where: \.isMXMaster)?.selectedProfile
        )
        if UserDefaults.standard.data(forKey: MacMouseSettings.defaultsKey) == nil {
            macMouseSettings.persist()
        }
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
                    self?.snapshot = self?.dualSense.snapshot ?? DualSenseSnapshot()
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
                    self?.dualSense.handleDisconnect(controller)
                    self?.attachPreferredController()
                    self?.snapshot = self?.dualSense.snapshot ?? DualSenseSnapshot()
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

        attachPreferredController()

        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.capture()
            }
        }
        timer.tolerance = 1.0 / 600.0
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        endControlActivity()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        familySessions.forEach { $0.stop() }
        mx3Reader.stop()
        mx4Reader.stop()
        mouseScrollTap.stop()
        WindowGrab.stop()
        WindowOrganizeHotkey.stop()
        WindowShake.stop()
        DockClickMinimize.stop()
    }

    func selectDevice(_ device: ConnectedBluetoothDevice) {
        selectDevice(id: device.id)
    }

    func selectDevice(id: String?) {
        guard selectedDeviceID != id else { return }
        selectedDeviceID = id
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
            dualSense.pulse()
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

    func setScrollAccelerationAmount(_ amount: Double) {
        updateSelectedRecord { record in
            guard var profile = record.profiles.first(where: { $0.id == record.selectedProfileID }) else { return }
            profile.scrollAccelerationAmount = min(max(amount, 0), 1)
            if let index = record.profiles.firstIndex(where: { $0.id == profile.id }) {
                record.profiles[index] = profile
            }
        }
    }

    func setScrollAcceleration(_ enabled: Bool) {
        updateSelectedRecord { record in
            guard var profile = record.profiles.first(where: { $0.id == record.selectedProfileID }) else { return }
            profile.scrollAcceleration = enabled
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

    func setTabRepeatInterval(_ interval: Double) {
        updateSelectedProfile { $0.dualSenseTabRepeatInterval = min(max(interval, 0.10), 0.55) }
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
        updateSharedMouseScroll { $0.pointerSpeed = min(max(speed, 0), 1) }
    }

    func setHapticGestureSpeed(_ speed: Double) {
        updateSelectedProfile { $0.hapticGestureSpeed = min(max(speed, 0), 1) }
    }

    func setWheelScrollSpeed(_ speed: Double) {
        updateSharedMouseScroll { $0.wheelScrollSpeed = min(max(speed, 0), 1) }
    }

    func setThumbScrollSpeed(_ speed: Double) {
        updateSharedMouseScroll { $0.thumbScrollSpeed = min(max(speed, 0), 1) }
    }

    func setNaturalScrolling(_ enabled: Bool) {
        updateSharedMouseScroll { $0.naturalScrolling = enabled }
    }

    func setSensorDPI(_ dpi: Int) {
        updateSelectedProfile { $0.sensorDPI = MappingProfile.clampDisplayedDPI(dpi) }
    }

    func setSmoothScrolling(_ enabled: Bool) {
        updateSharedMouseScroll { $0.smoothScrolling = enabled }
    }

    func setKeyboardBacklightEnabled(_ enabled: Bool) {
        keyboard.setBacklightEnabled(enabled)
        mxKeyboardSnapshot = keyboard.snapshot
    }

    func setKeyboardBacklightEffect(_ effect: MXKeyboardBacklightEffect) {
        keyboard.setBacklightEffect(effect)
        mxKeyboardSnapshot = keyboard.snapshot
    }

    func setKeyboardBatterySaving(_ enabled: Bool) {
        keyboard.setBatterySaving(enabled)
        mxKeyboardSnapshot = keyboard.snapshot
    }

    func isLiveKeyboardSelection(_ live: MXKeyboardSnapshot? = nil) -> Bool {
        guard let record = selectedRecord, record.isMXKeyboard else { return false }
        let live = live ?? mxKeyboardSnapshot
        return isLiveKeyboardDevice(
            kind: record.kind,
            address: record.address,
            name: record.name,
            live: live
        )
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

    /// Scroll invert / wheel speed / pointer speed for every system mouse
    /// (MX now; generic mouse later). Gamepads stay on their own profile.
    private func updateSharedMouseScroll(_ mutate: (inout MappingProfile) -> Void) {
        updateSelectedProfile(mutate)
        guard selectedRecord?.isMXMaster == true, let source = selectedRecord?.selectedProfile else { return }
        propagateSharedMouseScroll(from: source)
    }

    func setMacPointerSpeed(_ speed: Double) {
        updateMacMouse { $0.pointerSpeed = min(max(speed, 0), 1) }
    }

    func setMacWheelScrollSpeed(_ speed: Double) {
        updateMacMouse { $0.wheelScrollSpeed = min(max(speed, 0), 1) }
    }

    func setMacThumbScrollSpeed(_ speed: Double) {
        updateMacMouse { $0.thumbScrollSpeed = min(max(speed, 0), 1) }
    }

    func setMacNaturalScrolling(_ enabled: Bool) {
        updateMacMouse { $0.naturalScrolling = enabled }
    }

    func setMacSmoothScrolling(_ enabled: Bool) {
        updateMacMouse { $0.smoothScrolling = enabled }
    }

    private func updateMacMouse(_ mutate: (inout MacMouseSettings) -> Void) {
        mutate(&macMouseSettings)
        macMouseSettings.persist()
        lastScrollTapSignature = ""
        lastWindowGrabSignature = ""
        lastAppliedSystemPointerSpeed = -1
        let settings = macMouseSettings
        updateAllMXProfiles { settings.apply(to: &$0) }
    }

    private func updateAllMXProfiles(_ mutate: (inout MappingProfile) -> Void) {
        var changed = false
        for index in deviceRecords.indices where deviceRecords[index].isMXMaster {
            let selectedID = deviceRecords[index].selectedProfileID
            guard let profileIndex = deviceRecords[index].profiles.firstIndex(where: { $0.id == selectedID }) else {
                continue
            }
            var profile = deviceRecords[index].profiles[profileIndex]
            mutate(&profile)
            deviceRecords[index].profiles[profileIndex] = profile
            changed = true
        }
        if changed {
            persistDeviceRecords()
        }
    }

    private func propagateSharedMouseScroll(from source: MappingProfile) {
        var changed = false
        for index in deviceRecords.indices where deviceRecords[index].isMXMaster {
            let selectedID = deviceRecords[index].selectedProfileID
            guard let profileIndex = deviceRecords[index].profiles.firstIndex(where: { $0.id == selectedID }) else {
                continue
            }
            var profile = deviceRecords[index].profiles[profileIndex]
            if Self.sharedMouseScrollMatches(profile, source) { continue }
            Self.applySharedMouseScroll(&profile, from: source)
            deviceRecords[index].profiles[profileIndex] = profile
            changed = true
        }
        if changed {
            persistDeviceRecords()
        }
    }

    private static func sharedMouseScrollMatches(_ profile: MappingProfile, _ source: MappingProfile) -> Bool {
        profile.pointerSpeed == source.pointerSpeed
            && profile.naturalScrolling == source.naturalScrolling
            && profile.smoothScrolling == source.smoothScrolling
            && profile.wheelScrollSpeed == source.wheelScrollSpeed
            && profile.thumbScrollSpeed == source.thumbScrollSpeed
    }

    private static func applySharedMouseScroll(_ profile: inout MappingProfile, from source: MappingProfile) {
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
                isMXMaster: record.isMXMaster,
                isMXKeyboard: record.isMXKeyboard
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

    func promptForScreenCapture() {
        AppVolumeMixer.requestCaptureAccess { [weak self] _ in
            self?.refreshPermissions()
        }
    }

    func openScreenCaptureSettings() {
        AppVolumeMixer.openCaptureSettings()
    }

    func promptForScreenRecording() {
        _ = DockPreview.requestScreenRecordingAccess()
        refreshPermissions()
    }

    func openScreenRecordingSettings() {
        DockPreview.openScreenRecordingSettings()
    }

    func promptForBackgroundActivity() {
        do {
            try SMAppService.mainApp.register()
        } catch {
            openBackgroundSettings()
        }
        refreshPermissions()
        if SMAppService.mainApp.status == .requiresApproval {
            openBackgroundSettings()
        }
    }

    func setLaunchAtLogin(_ on: Bool) {
        if on {
            promptForBackgroundActivity()
            return
        }
        do {
            try SMAppService.mainApp.unregister()
        } catch {
            openBackgroundSettings()
        }
        refreshPermissions()
    }

    func openBackgroundSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func relaunchApp() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async {
                AppQuit.quitNow()
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
        let background = SMAppService.mainApp.status == .enabled
        if backgroundAllowed != background {
            backgroundAllowed = background
        }
        let login = SMAppService.mainApp.status != .notRegistered
        if launchAtLoginOn != login {
            launchAtLoginOn = login
        }
        let needsApproval = SMAppService.mainApp.status == .requiresApproval
        if backgroundNeedsApproval != needsApproval {
            backgroundNeedsApproval = needsApproval
        }
        let screenCapture = AppVolumeMixer.hasCaptureAccess
        if screenCaptureTrusted != screenCapture {
            screenCaptureTrusted = screenCapture
        }
        let screenRecording = DockPreview.hasScreenRecordingAccess
        if screenRecordingTrusted != screenRecording {
            screenRecordingTrusted = screenRecording
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
            var record = DeviceRecord.make(from: device, remembered: true)
            applyMacMouseIfNeeded(&record)
            deviceRecords.append(record)
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
        dualSense.detach()
        snapshot = DualSenseSnapshot()
        appleTVSnapshot = AppleTVRemoteSnapshot()
        attachPreferredController()
    }

    private func attachPreferredController() {
        let preferredName = deviceRecords.first {
            $0.kind == .dualSense || $0.kind == .dualSenseEdge
        }?.name
        dualSense.attachPreferred(named: preferredName)
        snapshot = dualSense.snapshot
    }

    private func capture() {
        if Date().timeIntervalSince(lastAudioProbe) > 2 {
            refreshAudioInputs()
            mergeMXMasterStatus()
            mergeKeyboardStatus()
            lastAudioProbe = Date()
        }
        if Date().timeIntervalSince(lastDeviceProbe) > 15, !isMenuTracking {
            refreshDevices()
            lastDeviceProbe = Date()
        }
        if Date().timeIntervalSince(lastTrustProbe) > 2 {
            refreshPermissions()
        }

        let dualSenseRecord = liveDualSenseRecord()
        let wantMotion = selectedKind == .dualSense || selectedKind == .dualSenseEdge
        dualSense.poll(
            hapticEnabled: dualSenseRecord?.hapticFeedbackEnabled == true,
            wantMotion: wantMotion
        )
        let ds = dualSense.snapshot
        publishDualSense(ds, wantMotion: wantMotion)
        if let record = dualSenseRecord, ds.connected {
            ingestControl(ControlFrameBuilder.make(from: ds), record: record)
        }
        captureMXMasters()
        captureKeyboard()
        if appleTVShouldCapture {
            let device = connectedDevices.first(where: {
                $0.deviceKind == .appleTVRemote && $0.isConnected
            }) ?? connectedDevices.first(where: { $0.deviceKind == .appleTVRemote })
            appleTV.poll(catalogDevice: device, selected: selectedKind == .appleTVRemote)
            let nextAppleTV = appleTV.snapshot
            if appleTVSnapshot != nextAppleTV {
                appleTVSnapshot = nextAppleTV
            }
            if let record = liveAppleTVRecord(), nextAppleTV.connected {
                ingestControl(ControlFrameBuilder.make(from: nextAppleTV), record: record)
            }
        } else if appleTVSnapshot.connected {
            appleTV.clearIfIdle()
            appleTVSnapshot = appleTV.snapshot
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
        let nextMX = displayMXSnapshot()
        if mxMasterSnapshot != nextMX {
            mxMasterSnapshot = nextMX
        }
        applyMouseScrollTap()
        applyWindowGrab()
    }

    private func captureKeyboard() {
        let next = keyboard.snapshot
        if mxKeyboardSnapshot != next {
            mxKeyboardSnapshot = next
        }
    }

    private func publishDualSense(_ next: DualSenseSnapshot, wantMotion: Bool) {
        if snapshot.matchesIgnoringMotion(next) {
            if wantMotion, Date().timeIntervalSince(lastMotionPublish) >= 0.1 {
                snapshot = next
                lastMotionPublish = Date()
            }
            return
        }
        snapshot = next
        lastMotionPublish = Date()
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
        engine.isDualSense = false
        reader.injectEnabled = record.controlEnabled && !ShortcutCapture.isActive
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
        let profile = macMouseProfile
        if lastAppliedSystemPointerSpeed != profile.resolvedPointerSpeed {
            PointerHIDSettings.applySystem(pointerSpeed: profile.resolvedPointerSpeed)
            lastAppliedSystemPointerSpeed = profile.resolvedPointerSpeed
        }
        let mxConnected = mxReaders.contains { $0.current.connected }
        guard accessibilityTrusted, mxConnected else {
            if lastScrollTapSignature != "off" {
                mouseScrollTap.setActive(false)
                lastScrollTapSignature = "off"
            }
            return
        }
        let mx = sharedMXScrollRecord?.selectedProfile
        let natural = profile.resolvedNaturalScrolling
        let smooth = profile.resolvedSmoothScrolling
        let vertical = 0.05 + profile.appliedWheelScrollSpeed * 0.55
        let horizontal = 0.05 + profile.appliedThumbScrollSpeed * 0.55
        let passUp = mx?.keepsNativeScroll(for: .mxWheelUp) ?? true
        let passDown = mx?.keepsNativeScroll(for: .mxWheelDown) ?? true
        let passLeft = mx?.keepsNativeScroll(for: .mxThumbLeft) ?? true
        let passRight = mx?.keepsNativeScroll(for: .mxThumbRight) ?? true
        let signature = "mac|\(natural)|\(smooth)|\(vertical)|\(horizontal)|\(passUp)|\(passDown)|\(passLeft)|\(passRight)"
        guard signature != lastScrollTapSignature else { return }
        lastScrollTapSignature = signature
        mouseScrollTap.wantNatural = natural
        mouseScrollTap.smoothScrolling = smooth
        mouseScrollTap.verticalScale = vertical
        mouseScrollTap.horizontalScale = horizontal
        mouseScrollTap.passVerticalPositive = passUp
        mouseScrollTap.passVerticalNegative = passDown
        mouseScrollTap.passHorizontalPositive = passRight
        mouseScrollTap.passHorizontalNegative = passLeft
        mouseScrollTap.setActive(true)
        for reader in mxReaders where reader.current.connected {
            reader.applySmoothScrolling(smooth)
            reader.applyScrollDirection(natural)
        }
        propagateSharedMouseScroll(from: profile)
    }

    private func applyWindowGrab() {
        guard accessibilityTrusted else {
            if lastWindowGrabSignature != "off" {
                WindowGrab.stop()
                WindowOrganizeHotkey.stop()
                WindowShake.stop()
                DockClickMinimize.stop()
                lastWindowGrabSignature = "off"
            }
            return
        }
        let profile = macMouseProfile
        let signature = "mac|\(profile.resolvedWindowMoveEnabled)|\(profile.resolvedWindowResizeEnabled)|\(profile.resolvedWindowThrowEnabled)|\(profile.resolvedWindowOrganizeEnabled)|\(profile.resolvedWindowShakeEnabled)|\(profile.resolvedWindowShakeScope)|\(profile.resolvedWindowDockClickMinimizeEnabled)|\(profile.resolvedWindowMoveFlags)|\(profile.resolvedWindowResizeFlags)|\(profile.resolvedWindowThrowFlags)|\(profile.resolvedWindowOrganizeFlags)|\(profile.resolvedWindowOrganizeKey)"
        guard signature != lastWindowGrabSignature else { return }
        lastWindowGrabSignature = signature
        WindowGrab.configure(
            enabled: true,
            moveEnabled: profile.resolvedWindowMoveEnabled,
            resizeEnabled: profile.resolvedWindowResizeEnabled,
            throwEnabled: profile.resolvedWindowThrowEnabled,
            moveFlags: profile.resolvedWindowMoveFlags,
            resizeFlags: profile.resolvedWindowResizeFlags,
            throwFlags: profile.resolvedWindowThrowFlags
        )
        WindowOrganizeHotkey.configure(
            enabled: profile.resolvedWindowOrganizeEnabled,
            flags: profile.resolvedWindowOrganizeFlags,
            virtualKey: profile.resolvedWindowOrganizeKey
        ) {
            WindowGrab.organizeAtPointer()
        }
        WindowShake.configure(
            enabled: profile.resolvedWindowShakeEnabled,
            scope: profile.resolvedWindowShakeScope
        )
        DockClickMinimize.configure(
            enabled: profile.resolvedWindowDockClickMinimizeEnabled
        )
    }

    func setWindowMoveEnabled(_ enabled: Bool) {
        updateMacMouse { $0.windowMoveEnabled = enabled }
    }

    func setWindowResizeEnabled(_ enabled: Bool) {
        updateMacMouse { $0.windowResizeEnabled = enabled }
    }

    func setWindowMoveFlags(_ flags: UInt64) {
        updateMacMouse {
            $0.windowMoveFlags = flags == 0 ? MappingProfile.defaultWindowMoveFlags : flags
        }
    }

    func setWindowResizeFlags(_ flags: UInt64) {
        updateMacMouse {
            $0.windowResizeFlags = flags == 0 ? MappingProfile.defaultWindowResizeFlags : flags
        }
    }

    func setWindowThrowEnabled(_ enabled: Bool) {
        updateMacMouse { $0.windowThrowEnabled = enabled }
    }

    func setWindowOrganizeEnabled(_ enabled: Bool) {
        updateMacMouse { $0.windowOrganizeEnabled = enabled }
    }

    func setWindowThrowFlags(_ flags: UInt64) {
        updateMacMouse {
            $0.windowThrowFlags = flags == 0 ? MappingProfile.defaultWindowThrowFlags : flags
        }
    }

    func setWindowOrganizeFlags(_ flags: UInt64) {
        updateMacMouse {
            $0.windowOrganizeFlags = flags == 0 ? MappingProfile.defaultWindowOrganizeFlags : flags
        }
    }

    func setWindowOrganizeShortcut(virtualKey: UInt16, flags: UInt64) {
        updateMacMouse {
            $0.windowOrganizeKey = virtualKey
            $0.windowOrganizeFlags = ModifierChords.normalized(flags).rawValue
        }
    }

    func setWindowShakeEnabled(_ enabled: Bool) {
        updateMacMouse { $0.windowShakeEnabled = enabled }
    }

    func setWindowShakeScope(_ scope: WindowShakeScope) {
        updateMacMouse { $0.windowShakeScope = scope }
    }

    func setWindowDockClickMinimizeEnabled(_ enabled: Bool) {
        updateMacMouse { $0.windowDockClickMinimizeEnabled = enabled }
    }

    func macModifierOccupancy(
        arrangementEnabled: Bool,
        arrangementFlags: CGEventFlags
    ) -> MacModifierOccupancy {
        let profile = macMouseProfile
        return MacModifierOccupancy(
            moveEnabled: profile.resolvedWindowMoveEnabled,
            moveFlags: profile.resolvedWindowMoveFlags,
            resizeEnabled: profile.resolvedWindowResizeEnabled,
            resizeFlags: profile.resolvedWindowResizeFlags,
            throwEnabled: profile.resolvedWindowThrowEnabled,
            throwFlags: profile.resolvedWindowThrowFlags,
            arrangementEnabled: arrangementEnabled,
            arrangementFlags: arrangementFlags
        )
    }

    private func ingestControl(_ frame: ControlFrame, record: DeviceRecord) {
        let engine = engine(for: record.id)
        engine.profile = record.selectedProfile
        engine.enabled = record.controlEnabled
        engine.postsWhenHostIsActive = record.controlWhileFocused
        engine.isDualSense = record.kind == .dualSense || record.kind == .dualSenseEdge
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
        if let index = deviceRecords.firstIndex(where: { $0.id == device.id }) {
            applyMacMouseIfNeeded(&deviceRecords[index])
        }
    }

    private func applyMacMouseIfNeeded(_ record: inout DeviceRecord) {
        guard record.isMXMaster else { return }
        for index in record.profiles.indices {
            macMouseSettings.apply(to: &record.profiles[index])
        }
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
        if record.kind.isMXMaster || record.kind.isMXKeyboard {
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
        appleTV.hidConnected
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
        if let name = dualSense.vendorName,
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
        if let index = deviceRecords.firstIndex(where: { $0.id == device.id }) {
            applyMacMouseIfNeeded(&deviceRecords[index])
        }
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
                        isMXMaster: next.isMXMaster,
                        isMXKeyboard: next.isMXKeyboard
                    )
                    next.profiles = [profile]
                    next.selectedProfileID = profile.id
                }
                if next.isMXMaster {
                    for index in next.profiles.indices {
                        next.profiles[index].restrictGesturesToHapticPad()
                        if !next.kind.isMXMaster3Family {
                            next.profiles[index].ensureMX4SideButton()
                        }
                    }
                }
                if DeviceSupport.isMXMechanicalName(next.name), !next.kind.isMXKeyboard {
                    next.kind = MXMechanicalSupport.kind(from: next.name)
                }
                if next.kind == .dualSense || next.kind == .dualSenseEdge {
                    for index in next.profiles.indices {
                        next.profiles[index].ensureDualSenseTouchGestures()
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
                    reason: "Control Box is posting controller input"
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

    private static let deviceRecordsDefaultsKey = "controlbox.deviceRecords.v1"
    private static let selectedDeviceDefaultsKey = "controlbox.selectedDeviceID"
    private static let suppressedDevicesDefaultsKey = "controlbox.suppressedDevices.v1"

    private func refreshDevices() {
        var devices = BluetoothDeviceCatalog.availableDevices()
        for reader in mxReaders {
            mergeLiveMX(reader.current, into: &devices)
        }
        mergeLiveKeyboard(keyboard.snapshot, into: &devices)
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

    private func mergeKeyboardStatus() {
        mergeLiveKeyboard(keyboard.snapshot, into: &connectedDevices)
    }

    private func mergeLiveKeyboard(_ live: MXKeyboardSnapshot, into devices: inout [ConnectedBluetoothDevice]) {
        guard live.connected else { return }
        if let index = devices.firstIndex(where: {
            isLiveKeyboardDevice(kind: $0.deviceKind, address: $0.address, name: $0.name, live: live)
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
                id: "kb:\(DeviceIdentity.isConcrete(live.address) ? live.address : live.name)",
                name: live.name,
                address: DeviceIdentity.isConcrete(live.address) ? live.address : DeviceIdentity.hidFallback,
                deviceKind: live.kind,
                detail: live.status,
                isConnected: true
            )
        )
    }

    private func isLiveKeyboardDevice(
        kind: DeviceKind,
        address: String,
        name: String,
        live: MXKeyboardSnapshot
    ) -> Bool {
        guard live.connected else { return false }
        if DeviceIdentity.same(address, live.address) { return true }
        if DeviceIdentity.isConcrete(address), DeviceIdentity.isConcrete(live.address) {
            return false
        }
        return kind.isMXKeyboard && namesMatch(name, live.name)
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
