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
    var calibrationWindowFocused = false
    var openCalibrationDeviceIDs: Set<String> = []
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
    var frontmostBundleID: String?
    var recentFrontmostApps: [RecentFrontmostApp] = []
    let controlEngine = ControlEngine()

    var allPermissionsGranted: Bool {
        accessibilityTrusted && inputMonitoringTrusted
    }

    var needsRelaunchForPermissions: Bool {
        !accessibilityTrusted || !inputMonitoringTrusted
    }
    private var suppressedDeviceKeys: Set<String> = []
    private var friendlyNameWriteWork: DispatchWorkItem?

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

    func deviceRecord(for id: String) -> DeviceRecord? {
        deviceRecords.first { $0.id == id }
    }

    func registerCalibrationWindow(for deviceID: String) {
        openCalibrationDeviceIDs.insert(deviceID)
    }

    func unregisterCalibrationWindow(for deviceID: String) {
        openCalibrationDeviceIDs.remove(deviceID)
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
        var items: [SidebarDevice] = []
        for record in deviceRecords where record.remembered {
            if items.contains(where: { DeviceIdentity.sameLogitech($0.logitechKey, record.logitechKey) }) {
                continue
            }
            let live = connectedDevices.first { recordsMatch(record, $0) && $0.isConnected }
            items.append(
                SidebarDevice(
                    id: record.id,
                    name: record.displayName,
                    address: live?.address ?? record.address,
                    kind: record.kind,
                    isConnected: live != nil,
                    controlEnabled: record.controlEnabled,
                    remembered: true,
                    connection: live?.connection ?? record.logitechKey.connection,
                    unitID: record.unitID ?? live?.unitID,
                    wirelessProductID: record.wirelessProductID ?? live?.wirelessProductID
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
                if DeviceIdentity.sameLogitech(row.logitechKey, device.logitechKey) { return true }
                if device.deviceKind.isMXMaster || device.deviceKind.isMXKeyboard { return false }
                return namesMatch(row.name, device.name)
            }
        }
    }

    var unsupportedDevices: [ConnectedBluetoothDevice] {
        connectedDevices.filter { !$0.isSupported && $0.isConnected }
    }

    var bluetoothConnectedDevices: [ConnectedBluetoothDevice] {
        connectedDevices.filter { $0.isConnected && $0.connection != .bolt }.sorted(by: Self.bluetoothSort)
    }

    var bluetoothDisconnectedDevices: [ConnectedBluetoothDevice] {
        let live = bluetoothConnectedDevices
        return deviceRecords.compactMap { record -> ConnectedBluetoothDevice? in
            guard record.remembered else { return nil }
            if record.logitechKey.connection == .bolt { return nil }
            if live.contains(where: { recordsMatch(record, $0) }) { return nil }
            return ConnectedBluetoothDevice(
                id: record.id,
                name: record.name,
                address: record.address,
                deviceKind: record.kind,
                detail: record.kind.title,
                isConnected: false,
                unitID: record.unitID,
                wirelessProductID: record.wirelessProductID,
                connection: record.logitechKey.connection
            )
        }
        .sorted(by: Self.bluetoothSort)
    }

    private static func bluetoothSort(_ lhs: ConnectedBluetoothDevice, _ rhs: ConnectedBluetoothDevice) -> Bool {
        if lhs.isSupported != rhs.isSupported { return lhs.isSupported }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    private var pollTimer: Timer?
    private var controlActivity: NSObjectProtocol?
    private var observers: [NSObjectProtocol] = []
    private var workspaceObserver: NSObjectProtocol?
    private var lastAudioProbe = Date.distantPast
    private var lastTrustProbe = Date.distantPast
    private var lastDeviceProbe = Date.distantPast
    private var lastMotionPublish = Date.distantPast
    private var lastScrollTapSignature = ""
    private var lastWindowGrabSignature = ""
    private var lastAppliedSystemPointerSpeed = -1.0
    private var didStart = false
    private var engines: [String: ControlEngine] = [:]
    private var mxWheelEngines: [String: MXWheelActionEngine] = [:]
    private var lastLiveAppProfileID: [String: String] = [:]
    private let dualSense = DualSenseSession()
    private let appleTV = AppleTVRemoteSession()
    private let keyboard = MXKeyboardSession()
    private let mx3Reader = LogitechMXMasterReader(model: MXMaster3Support.model)
    private let mx4Reader = LogitechMXMasterReader(model: MXMaster4Support.model)
    private let mouseScrollTap = MouseScrollTap()
    private var boltCatalog: LogiBoltCatalog?

    private var mxReaders: [LogitechMXMasterReader] { [mx3Reader, mx4Reader] }
    private var familySessions: [any DeviceFamilySession] { [dualSense, appleTV, keyboard] }

    func start() {
        guard !didStart else { return }
        didStart = true
        familySessions.forEach { $0.start() }
        mx3Reader.start()
        mx4Reader.start()
        if let catalog = boltCatalog {
            catalog.keepAlive = true
            catalog.startWatching()
        }
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
            self?.syncBoltTalk()
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

        startFrontmostAppWatcher()

        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.capture()
            }
        }
        timer.tolerance = 1.0 / 600.0
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func startFrontmostAppWatcher() {
        if workspaceObserver != nil { return }
        handleFrontmostApp(NSWorkspace.shared.frontmostApplication)
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor in
                self?.handleFrontmostApp(app)
            }
        }
    }

    private func handleFrontmostApp(_ app: NSRunningApplication?) {
        let bundle = app?.bundleIdentifier
        if bundle == frontmostBundleID { return }
        frontmostBundleID = bundle
        if let bundle, let app, bundle != MouseAppCatalog.controlBoxBundleID {
            let name = app.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = (name?.isEmpty == false) ? name! : bundle
            recentFrontmostApps.removeAll { $0.bundleID == bundle }
            recentFrontmostApps.insert(RecentFrontmostApp(bundleID: bundle, name: title), at: 0)
            if recentFrontmostApps.count > 24 {
                recentFrontmostApps = Array(recentFrontmostApps.prefix(24))
            }
        }
        applyLiveAppProfiles()
    }

    func liveAppProfile(for record: DeviceRecord) -> MappingProfile {
        MouseAppCatalog.liveProfile(
            profiles: record.profiles,
            defaultProfile: record.mxDefaultProfile,
            frontmostBundleID: frontmostBundleID,
            lastLiveID: lastLiveAppProfileID[record.id]
        )
    }

    func liveMXProfile(for record: DeviceRecord) -> MappingProfile {
        liveAppProfile(for: record)
    }

    func liveAppCaption(for record: DeviceRecord) -> String {
        let noun: String
        if record.isMXMaster {
            noun = "Mouse"
        } else if record.isAppleTVRemote {
            noun = "Remote"
        } else {
            noun = "Gamepad"
        }
        return "\(noun) is using \(liveAppProfile(for: record).mxScopeTitle)"
    }

    func liveMXCaption(for record: DeviceRecord) -> String {
        liveAppCaption(for: record)
    }

    private func applyLiveAppProfiles() {
        var nextIDs = lastLiveAppProfileID
        for record in deviceRecords where record.usesAppProfiles {
            let live = liveAppProfile(for: record)
            let previous = lastLiveAppProfileID[record.id]
            if previous != live.id {
                engine(for: record.id).reset()
                if record.isMXMaster {
                    mxWheelEngine(for: record.id).reset()
                    lastScrollTapSignature = ""
                }
            }
            let bundle = frontmostBundleID ?? ""
            if bundle != MouseAppCatalog.controlBoxBundleID
                || record.profiles.contains(where: { $0.frontmostAppBundleID == bundle }) {
                nextIDs[record.id] = live.id
            } else if previous == nil {
                nextIDs[record.id] = live.id
            }
        }
        if nextIDs != lastLiveAppProfileID {
            lastLiveAppProfileID = nextIDs
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        endControlActivity()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
            self.workspaceObserver = nil
        }
        familySessions.forEach { $0.stop() }
        mx3Reader.stop()
        mx4Reader.stop()
        keyboard.detachBolt()
        mouseScrollTap.stop()
        mxWheelEngines.values.forEach { $0.reset() }
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

    func attachBoltCatalog(_ catalog: LogiBoltCatalog) {
        boltCatalog = catalog
        catalog.keepAlive = true
        catalog.onReceiversChanged = { [weak self] in
            self?.handleBoltCatalogChanged()
        }
        if didStart {
            catalog.startWatching()
            handleBoltCatalogChanged()
        }
    }

    private func handleBoltCatalogChanged() {
        refreshDevices()
        syncBoltTalk()
    }

    private func syncBoltTalk() {
        guard let catalog = boltCatalog else { return }
        if catalog.isTalkSuspended {
            mx3Reader.detachBolt()
            mx4Reader.detachBolt()
            keyboard.detachBolt()
            return
        }
        let online = catalog.receivers.flatMap(\.devices).filter { $0.online && $0.deviceKind.isSupported }
        syncBoltMouse(mx3Reader, online.filter(\.deviceKind.isMXMaster3Family), catalog)
        syncBoltMouse(mx4Reader, online.filter {
            $0.deviceKind == .logitechMXMaster4 || $0.deviceKind == .logitechMXMaster
        }, catalog)
        syncBoltKeyboard(online.filter(\.deviceKind.isMXKeyboard), catalog)
    }

    private func syncBoltMouse(
        _ reader: LogitechMXMasterReader,
        _ candidates: [LogiBoltPairedDevice],
        _ catalog: LogiBoltCatalog
    ) {
        if reader.usesBluetoothHIDPP {
            reader.detachBolt()
            return
        }
        guard let device = preferredBoltDevice(candidates, currentID: reader.boltSlotID) else {
            reader.detachBolt()
            return
        }
        let slotID = "\(device.receiverID)-\(device.slot)"
        if reader.boltSlotID == slotID, reader.current.connected { return }
        guard let link = catalog.talkLink(receiverID: device.receiverID, slot: device.slot) else {
            reader.detachBolt()
            return
        }
        if !reader.attachBolt(
            link,
            name: device.displayName,
            kind: device.deviceKind,
            address: device.identityAddress,
            unitID: device.unitID,
            wpid: device.wpid
        ) {
            catalog.releaseTalkLink(link)
        }
    }

    private func syncBoltKeyboard(_ candidates: [LogiBoltPairedDevice], _ catalog: LogiBoltCatalog) {
        if keyboard.usesBluetoothHIDPP {
            keyboard.detachBolt()
            return
        }
        guard let device = preferredBoltDevice(candidates, currentID: keyboard.boltSlotID) else {
            keyboard.detachBolt()
            return
        }
        let slotID = "\(device.receiverID)-\(device.slot)"
        if keyboard.boltSlotID == slotID, keyboard.snapshot.connected { return }
        guard let link = catalog.talkLink(receiverID: device.receiverID, slot: device.slot) else {
            keyboard.detachBolt()
            return
        }
        if !keyboard.attachBolt(
            link,
            name: device.displayName,
            kind: device.deviceKind,
            address: device.identityAddress,
            unitID: device.unitID,
            wpid: device.wpid
        ) {
            catalog.releaseTalkLink(link)
        }
    }

    private func preferredBoltDevice(
        _ candidates: [LogiBoltPairedDevice],
        currentID: String?
    ) -> LogiBoltPairedDevice? {
        if let currentID, let current = candidates.first(where: { "\($0.receiverID)-\($0.slot)" == currentID }) {
            return current
        }
        return candidates.sorted { lhs, rhs in
            if lhs.receiverID != rhs.receiverID { return lhs.receiverID < rhs.receiverID }
            return lhs.slot < rhs.slot
        }.first
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
        if selectedRecord?.isGamepad == true || selectedRecord?.isAppleTVRemote == true {
            updateControllerDeviceSettings { $0.setMode(mode, for: source) }
            return
        }
        updateSelectedRecord { record in
            guard var profile = record.profiles.first(where: { $0.id == record.selectedProfileID }) else { return }
            profile.setMode(mode, for: source)
            if let index = record.profiles.firstIndex(where: { $0.id == profile.id }) {
                record.profiles[index] = profile
            }
        }
    }

    func setPointerAccelerationAmount(_ amount: Double) {
        let clamped = min(max(amount, 0), 1)
        if selectedRecord?.isGamepad == true || selectedRecord?.isAppleTVRemote == true {
            updateControllerDeviceSettings { $0.pointerAccelerationAmount = clamped }
            return
        }
        updateSelectedRecord { record in
            guard var profile = record.profiles.first(where: { $0.id == record.selectedProfileID }) else { return }
            profile.pointerAccelerationAmount = clamped
            if let index = record.profiles.firstIndex(where: { $0.id == profile.id }) {
                record.profiles[index] = profile
            }
        }
    }

    func setScrollAccelerationAmount(_ amount: Double) {
        let clamped = min(max(amount, 0), 1)
        if selectedRecord?.isGamepad == true || selectedRecord?.isAppleTVRemote == true {
            updateControllerDeviceSettings { $0.scrollAccelerationAmount = clamped }
            return
        }
        updateSelectedRecord { record in
            guard var profile = record.profiles.first(where: { $0.id == record.selectedProfileID }) else { return }
            profile.scrollAccelerationAmount = clamped
            if let index = record.profiles.firstIndex(where: { $0.id == profile.id }) {
                record.profiles[index] = profile
            }
        }
    }

    func setScrollAcceleration(_ enabled: Bool) {
        if selectedRecord?.isGamepad == true || selectedRecord?.isAppleTVRemote == true {
            updateControllerDeviceSettings { $0.scrollAcceleration = enabled }
            return
        }
        updateSelectedRecord { record in
            guard var profile = record.profiles.first(where: { $0.id == record.selectedProfileID }) else { return }
            profile.scrollAcceleration = enabled
            if let index = record.profiles.firstIndex(where: { $0.id == profile.id }) {
                record.profiles[index] = profile
            }
        }
    }

    func setPointerAcceleration(_ enabled: Bool) {
        if selectedRecord?.isGamepad == true || selectedRecord?.isAppleTVRemote == true {
            updateControllerDeviceSettings { $0.pointerAcceleration = enabled }
            return
        }
        updateSelectedRecord { record in
            guard var profile = record.profiles.first(where: { $0.id == record.selectedProfileID }) else { return }
            profile.pointerAcceleration = enabled
            if let index = record.profiles.firstIndex(where: { $0.id == profile.id }) {
                record.profiles[index] = profile
            }
        }
    }

    func setTabRepeatInterval(_ interval: Double) {
        let clamped = min(max(interval, 0.10), 0.55)
        if selectedRecord?.isGamepad == true {
            updateControllerDeviceSettings { $0.dualSenseTabRepeatInterval = clamped }
            return
        }
        updateSelectedProfile { $0.dualSenseTabRepeatInterval = clamped }
    }

    func setTabRepeatInterval(_ interval: Double, for deviceID: String) {
        let clamped = min(max(interval, 0.10), 0.55)
        updateRecord(deviceID) { record in
            guard record.isGamepad else { return }
            for index in record.profiles.indices {
                record.profiles[index].dualSenseTabRepeatInterval = clamped
            }
        }
    }

    func setStickyTargeting(_ enabled: Bool) {
        if selectedRecord?.isGamepad == true || selectedRecord?.isAppleTVRemote == true {
            updateControllerDeviceSettings { $0.stickyTargeting = enabled }
            if !enabled {
                StickyTargeting.hide()
            }
            return
        }
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
        let clamped = min(max(speed, 0), 1)
        if selectedRecord?.isGamepad == true || selectedRecord?.isAppleTVRemote == true {
            updateControllerDeviceSettings { $0.pointerSpeed = clamped }
            return
        }
        updateSharedMouseScroll { $0.pointerSpeed = clamped }
    }

    func setWheelScrollSpeed(_ speed: Double) {
        let clamped = min(max(speed, 0), 1)
        if selectedRecord?.isGamepad == true || selectedRecord?.isAppleTVRemote == true {
            updateControllerDeviceSettings {
                $0.wheelScrollSpeed = clamped
                $0.thumbScrollSpeed = clamped
            }
            return
        }
        updateSharedMouseScroll {
            $0.wheelScrollSpeed = clamped
            $0.thumbScrollSpeed = clamped
        }
    }

    func setNaturalScrolling(_ enabled: Bool) {
        if selectedRecord?.isGamepad == true || selectedRecord?.isAppleTVRemote == true {
            updateControllerDeviceSettings { $0.naturalScrolling = enabled }
            return
        }
        updateSharedMouseScroll { $0.naturalScrolling = enabled }
    }

    func setSensorDPI(_ dpi: Int) {
        updateMXDeviceLevelProfile { $0.sensorDPI = MappingProfile.clampDisplayedDPI(dpi) }
    }

    func setMXThumbWheelSensitivity(_ speed: Double) {
        updateMXDeviceLevelProfile { $0.mxThumbWheelSensitivity = min(max(speed, 0), 1) }
    }

    func setMXThumbWheelInvert(_ inverted: Bool) {
        updateMXDeviceLevelProfile { $0.mxThumbWheelInvert = inverted }
    }

    func setMXRatchetMode(_ mode: MXRatchetMode) {
        updateMXDeviceLevelProfile { $0.mxRatchetMode = mode }
    }

    func setMXSmartShiftSensitivity(_ value: Int) {
        updateMXDeviceLevelProfile { $0.mxSmartShiftSensitivity = MappingProfile.clampSmartShiftSensitivity(value) }
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
            live: live,
            unitID: record.unitID,
            wpid: record.wirelessProductID,
            connection: record.logitechKey.connection
        )
    }

    func setGesturePreset(_ preset: GesturePreset, for button: DeviceButton) {
        updateSelectedProfile { $0.selectGesturePreset(preset, for: button) }
    }

    func addNamedCustomGestureSet(for button: DeviceButton) {
        updateSelectedProfile { _ = $0.addNamedCustomGestureSet(for: button) }
    }

    func selectNamedCustomGestureSet(_ id: String, for button: DeviceButton) {
        updateSelectedProfile { $0.selectNamedCustomGestureSet(id, for: button) }
    }

    func deleteNamedCustomGestureSet(_ id: String, for button: DeviceButton) {
        updateSelectedProfile { $0.deleteNamedCustomGestureSet(id, for: button) }
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

    private func updateMXDeviceLevelProfile(_ mutate: (inout MappingProfile) -> Void) {
        updateSelectedRecord { record in
            guard record.isMXMaster else { return }
            let defaultID = record.mxDefaultProfile.id
            guard var profile = record.profiles.first(where: { $0.id == defaultID }) else { return }
            mutate(&profile)
            if let index = record.profiles.firstIndex(where: { $0.id == profile.id }) {
                record.profiles[index] = profile
            }
        }
    }

    private func updateControllerDeviceSettings(_ mutate: (inout MappingProfile) -> Void) {
        updateSelectedRecord { record in
            guard record.isGamepad || record.isAppleTVRemote else { return }
            for index in record.profiles.indices {
                mutate(&record.profiles[index])
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
        let clamped = min(max(speed, 0), 1)
        updateMacMouse {
            $0.wheelScrollSpeed = clamped
            $0.thumbScrollSpeed = clamped
        }
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
            let defaultID = deviceRecords[index].mxDefaultProfile.id
            guard let profileIndex = deviceRecords[index].profiles.firstIndex(where: { $0.id == defaultID }) else {
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
            let defaultID = deviceRecords[index].mxDefaultProfile.id
            guard let profileIndex = deviceRecords[index].profiles.firstIndex(where: { $0.id == defaultID }) else {
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

    func setMXThumbWheelMode(_ mode: MXWheelMode) {
        updateSelectedProfile { profile in
            profile.mxThumbWheelMode = mode
            profile.bindings[.mxThumbLeft] = nil
            profile.bindings[.mxThumbRight] = nil
        }
        if let id = selectedDeviceID {
            mxWheelEngine(for: id).reset()
        }
        lastScrollTapSignature = ""
    }

    func selectProfile(_ id: String) {
        let usesAppProfiles = selectedRecord?.usesAppProfiles == true
        updateSelectedRecord { record in
            guard record.profiles.contains(where: { $0.id == id }) else { return }
            record.selectedProfileID = id
        }
        if !usesAppProfiles, let deviceID = selectedDeviceID {
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

    func addMXApp(bundleID: String, name: String) {
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateSelectedRecord { record in
            guard record.usesAppProfiles else { return }
            if let existing = record.profiles.first(where: { $0.frontmostAppBundleID == trimmed }) {
                record.selectedProfileID = existing.id
                return
            }
            let copy = MouseAppCatalog.profileForAddedApp(
                from: record.mxDefaultProfile,
                bundleID: trimmed,
                name: name,
                family: record.isMXMaster ? .mouse : (record.isAppleTVRemote ? .remote : .gamepad)
            )
            record.profiles.append(copy)
            record.selectedProfileID = copy.id
        }
    }

    func removeMXProfile(_ id: String) {
        updateSelectedRecord { record in
            guard record.usesAppProfiles else { return }
            guard let profile = record.profiles.first(where: { $0.id == id }) else { return }
            guard !profile.treatsAsMXDefault else { return }
            record.profiles.removeAll { $0.id == id }
            if record.selectedProfileID == id {
                record.selectedProfileID = record.mxDefaultProfile.id
            }
        }
        applyLiveAppProfiles()
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

    func renameSelectedDevice(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updateSelectedRecord { record in
            record.customName = trimmed.isEmpty ? nil : trimmed
        }
        friendlyNameWriteWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.writeSelectedFriendlyName(trimmed)
        }
        friendlyNameWriteWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    func reloadEasySwitch(isKeyboard: Bool) {
        if isKeyboard {
            keyboard.reloadEasySwitchHosts()
            return
        }
        guard let record = selectedRecord, let reader = reader(for: record.kind) else { return }
        reader.reloadEasySwitchHosts()
    }

    private func writeSelectedFriendlyName(_ name: String) {
        guard let record = selectedRecord else { return }
        if record.isMXKeyboard {
            keyboard.setFriendlyName(name)
            return
        }
        if record.isMXMaster, let reader = reader(for: record.kind) {
            reader.setFriendlyName(name)
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

    func hasRememberedSettings(for device: ConnectedBluetoothDevice) -> Bool {
        matchingRecord(for: device)?.remembered == true
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
        mxWheelEngines[id] = nil
        lastLiveAppProfileID[id] = nil
        persistDeviceRecords()
        selectedDeviceID = sidebarDevices.first?.id
        dualSense.detach()
        snapshot = DualSenseSnapshot()
        appleTVSnapshot = AppleTVRemoteSnapshot()
        attachPreferredController()
    }

    private func attachPreferredController() {
        let preferredName = deviceRecords.first {
            $0.remembered && $0.isGamepad
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
        let wantMotion = selectedKind == .dualSense
            || selectedKind == .dualSenseEdge
            || openCalibrationDeviceIDs.contains(where: {
                deviceRecord(for: $0)?.isGamepad == true
            })
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
            let calibrationOpen = openCalibrationDeviceIDs.contains(where: {
                deviceRecord(for: $0)?.isAppleTVRemote == true
            })
            appleTV.poll(
                catalogDevice: device,
                selected: selectedKind == .appleTVRemote || calibrationOpen
            )
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
            } else {
                reader.injectEnabled = false
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

    func mxSnapshot(for deviceID: String) -> MXMasterSnapshot {
        guard let record = deviceRecord(for: deviceID), record.isMXMaster else {
            return MXMasterSnapshot()
        }
        if let live = reader(for: record.kind)?.current {
            return live
        }
        var unavailable = MXMasterSnapshot()
        unavailable.kind = record.kind
        unavailable.name = record.displayName
        unavailable.address = record.address
        unavailable.status = "Not connected"
        return unavailable
    }

    private func displayMXSnapshot() -> MXMasterSnapshot {
        if selectedKind.isMXMaster, let reader = reader(for: selectedKind) {
            return reader.current
        }
        return mxReaders.map(\.current).first(where: \.connected) ?? MXMasterSnapshot()
    }

    private func ingestMX(_ reader: LogitechMXMasterReader, _ record: DeviceRecord, _ frame: ControlFrame) {
        let engine = engine(for: record.id)
        let live = liveMXProfile(for: record)
        let deviceLevel = record.mxDefaultProfile
        engine.profile = live
        engine.enabled = record.controlEnabled && !calibrationWindowFocused
        engine.postsWhenHostIsActive = record.controlWhileFocused
        engine.isDualSense = false
        reader.injectEnabled = record.controlEnabled
            && !ShortcutCapture.isActive
            && !calibrationWindowFocused
        reader.wheelsEnabled = accessibilityTrusted
        reader.setGestureOwners(live.mxGestureOwners)
        reader.applySensorDPI(deviceLevel.resolvedSensorDPI)
        reader.applyPointerSpeed(deviceLevel.resolvedPointerSpeed)
        reader.applySmartShift(
            mode: deviceLevel.resolvedMXRatchetMode,
            sensitivity: deviceLevel.resolvedMXSmartShiftSensitivity
        )
        reader.applyThumbWheelInvert(deviceLevel.resolvedMXThumbWheelInvert)
        let canInject = record.controlEnabled
            && !ShortcutCapture.isActive
            && !calibrationWindowFocused
            && (!NSApp.isActive || record.controlWhileFocused)
        let wheelEngine = mxWheelEngine(for: record.id)
        if canInject, frame.scrollX != 0 {
            wheelEngine.process(
                delta: frame.scrollX,
                mode: live.resolvedMXThumbWheelMode,
                naturalScrolling: macMouseProfile.resolvedNaturalScrolling,
                scrollSpeed: deviceLevel.resolvedMXThumbWheelSensitivity,
                nativeResolution: reader.current.thumbNativeResolution,
                divertedResolution: reader.current.thumbDivertedResolution,
                smoothScrolling: macMouseProfile.resolvedSmoothScrolling
            )
        } else {
            wheelEngine.idle(force: !canInject)
        }
        var buttonFrame = frame
        buttonFrame.scrollX = 0
        buttonFrame.scrollY = 0
        engine.process(buttonFrame, hostIsActive: NSApp.isActive)
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
        guard accessibilityTrusted else {
            if lastScrollTapSignature != "off" {
                mouseScrollTap.setActive(false)
                lastScrollTapSignature = "off"
            }
            return
        }
        let natural = profile.resolvedNaturalScrolling
        let smooth = profile.resolvedSmoothScrolling
        let scale = 0.05 + profile.appliedWheelScrollSpeed * 0.55
        let signature = "mac|\(natural)|\(smooth)|\(scale)|\(mxConnected)"
        guard signature != lastScrollTapSignature else { return }
        lastScrollTapSignature = signature
        mouseScrollTap.wantNatural = natural
        mouseScrollTap.smoothScrolling = smooth
        mouseScrollTap.verticalScale = scale
        mouseScrollTap.horizontalScale = scale
        mouseScrollTap.passVerticalPositive = true
        mouseScrollTap.passVerticalNegative = true
        mouseScrollTap.passHorizontalPositive = true
        mouseScrollTap.passHorizontalNegative = true
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
        engine.profile = record.usesAppProfiles ? liveAppProfile(for: record) : record.selectedProfile
        engine.enabled = record.controlEnabled && !calibrationWindowFocused
        engine.postsWhenHostIsActive = record.controlWhileFocused
        engine.isDualSense = record.kind.isGamepad
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

    private func mxWheelEngine(for deviceID: String) -> MXWheelActionEngine {
        if let existing = mxWheelEngines[deviceID] { return existing }
        let created = MXWheelActionEngine()
        mxWheelEngines[deviceID] = created
        return created
    }

    private func ensureRecord(for id: String, remembered: Bool = false) {
        if let index = deviceRecords.firstIndex(where: { $0.id == id }) {
            if remembered {
                deviceRecords[index].remembered = true
            }
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
        if DeviceIdentity.sameLogitech(record.logitechKey, device.logitechKey) { return true }
        if DeviceIdentity.same(record.address, device.address) { return true }
        guard record.kind == device.deviceKind else { return false }
        if record.kind.isMXMaster || record.kind.isMXKeyboard {
            if DeviceIdentity.looksLikeHardwareAddress(record.address),
               DeviceIdentity.looksLikeHardwareAddress(device.address) {
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
            live: live ?? mxMasterSnapshot,
            unitID: record.unitID,
            wpid: record.wirelessProductID,
            connection: record.logitechKey.connection
        )
    }

    private var appleTVShouldCapture: Bool {
        appleTV.hidConnected
            || selectedKind == .appleTVRemote
            || openCalibrationDeviceIDs.contains(where: {
                deviceRecord(for: $0)?.isAppleTVRemote == true
            })
            || connectedDevices.contains { $0.deviceKind == .appleTVRemote && $0.isConnected }
    }

    private func liveAppleTVRecord() -> DeviceRecord? {
        deviceRecords.first { $0.remembered && $0.isAppleTVRemote }
    }

    private func liveDualSenseRecord() -> DeviceRecord? {
        if let name = dualSense.vendorName,
           let match = deviceRecords.first(where: {
               $0.remembered && $0.isGamepad && namesMatch($0.name, name)
           }) {
            return match
        }
        return deviceRecords.first { $0.remembered && $0.isGamepad }
    }

    private func liveMXRecord(for live: MXMasterSnapshot) -> DeviceRecord? {
        guard live.connected else { return nil }
        if let match = deviceRecords.first(where: {
            $0.remembered && isLiveMXDevice(
                kind: $0.kind,
                address: $0.address,
                name: $0.name,
                live: live,
                unitID: $0.unitID,
                wpid: $0.wirelessProductID,
                connection: $0.logitechKey.connection
            )
        }) {
            return match
        }
        return nil
    }

    private func isLiveMXDevice(
        kind: DeviceKind,
        address: String,
        name: String,
        live: MXMasterSnapshot,
        unitID: UInt32? = nil,
        wpid: Int? = nil,
        connection: DeviceConnection = .bluetooth
    ) -> Bool {
        guard live.connected else { return false }
        return DeviceIdentity.sameLogitech(
            LogitechDeviceKey(
                name: name,
                kind: kind,
                address: address,
                unitID: unitID,
                wirelessProductID: wpid,
                connection: connection
            ),
            live.logitechKey
        )
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
        guard let index = matchingRecordIndex(for: device) else { return }
        deviceRecords[index].name = device.name
        if DeviceIdentity.looksLikeHardwareAddress(device.address)
            || !DeviceIdentity.looksLikeHardwareAddress(deviceRecords[index].address) {
            if DeviceIdentity.isConcrete(device.address) {
                deviceRecords[index].address = device.address
            }
        }
        deviceRecords[index].kind = device.deviceKind
        if deviceRecords[index].unitID == nil { deviceRecords[index].unitID = device.unitID }
        if deviceRecords[index].wirelessProductID == nil {
            deviceRecords[index].wirelessProductID = device.wirelessProductID
        }
    }

    private func collapseDuplicateLogitechRecords() {
        var kept: [DeviceRecord] = []
        var remapped: [String: String] = [:]
        for record in deviceRecords {
            if let index = kept.firstIndex(where: {
                DeviceIdentity.sameLogitech($0.logitechKey, record.logitechKey)
            }) {
                remapped[record.id] = kept[index].id
                kept[index] = mergeLogitechRecords(kept[index], record)
            } else {
                kept.append(record)
            }
        }
        guard kept.map(\.id) != deviceRecords.map(\.id) else { return }
        deviceRecords = kept
        if let selectedDeviceID, let mapped = remapped[selectedDeviceID] {
            self.selectedDeviceID = mapped
        }
    }

    private func mergeLogitechRecords(_ lhs: DeviceRecord, _ rhs: DeviceRecord) -> DeviceRecord {
        var keep = lhs.profiles.count >= rhs.profiles.count ? lhs : rhs
        let other = keep.id == lhs.id ? rhs : lhs
        keep.remembered = keep.remembered || other.remembered
        keep.controlEnabled = keep.controlEnabled || other.controlEnabled
        if keep.unitID == nil { keep.unitID = other.unitID }
        if keep.wirelessProductID == nil { keep.wirelessProductID = other.wirelessProductID }
        keep.name = DeviceIdentity.preferredLogitechName(keep.name, other.name)
        if DeviceIdentity.looksLikeHardwareAddress(other.address),
           !DeviceIdentity.looksLikeHardwareAddress(keep.address) {
            keep.address = other.address
        }
        return keep
    }

    private func updateSelectedRecord(_ mutate: (inout DeviceRecord) -> Void) {
        guard let id = selectedDeviceID else { return }
        ensureRecord(for: id)
        guard let index = deviceRecords.firstIndex(where: { $0.id == id }) else { return }
        mutate(&deviceRecords[index])
        persistDeviceRecords()
    }

    private func updateRecord(_ id: String, mutate: (inout DeviceRecord) -> Void) {
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
                if next.usesAppProfiles {
                    if next.isMXMaster {
                        for index in next.profiles.indices {
                            next.profiles[index].restrictGesturesToHapticPad()
                            if !next.kind.isMXMaster3Family {
                                next.profiles[index].ensureMX4SideButton()
                            }
                        }
                    }
                    next.ensureAppProfiles()
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
                next.ensureControllerDeviceSettings()
                return next
            }
        }
        if let id = UserDefaults.standard.string(forKey: Self.selectedDeviceDefaultsKey) {
            selectedDeviceID = id
        }
        collapseDuplicateLogitechRecords()
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
        mergeBoltDevices(into: &devices)
        for reader in mxReaders {
            mergeLiveMX(reader.current, into: &devices)
        }
        mergeLiveKeyboard(keyboard.snapshot, into: &devices)
        collapseConnectedLogitech(&devices)
        for index in devices.indices {
            if let record = matchingRecord(for: devices[index]) {
                devices[index].id = record.id
            }
        }
        connectedDevices = devices

        for device in devices where device.isSupported && device.isConnected {
            rememberConnectedDevice(device)
        }
        collapseDuplicateLogitechRecords()

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
            isLiveKeyboardDevice(
                kind: $0.deviceKind,
                address: $0.address,
                name: $0.name,
                live: live,
                unitID: $0.unitID,
                wpid: $0.wirelessProductID,
                connection: $0.connection
            )
        }) {
            devices[index].deviceKind = live.kind
            devices[index].isConnected = true
            devices[index].name = live.name
            devices[index].connection = live.connection
            devices[index].unitID = live.unitID == 0 ? devices[index].unitID : live.unitID
            devices[index].wirelessProductID = live.wirelessProductID == 0 ? devices[index].wirelessProductID : live.wirelessProductID
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
                isConnected: true,
                unitID: live.unitID == 0 ? nil : live.unitID,
                wirelessProductID: live.wirelessProductID == 0 ? nil : live.wirelessProductID,
                connection: live.connection
            )
        )
    }

    private func isLiveKeyboardDevice(
        kind: DeviceKind,
        address: String,
        name: String,
        live: MXKeyboardSnapshot,
        unitID: UInt32? = nil,
        wpid: Int? = nil,
        connection: DeviceConnection = .bluetooth
    ) -> Bool {
        guard live.connected else { return false }
        return DeviceIdentity.sameLogitech(
            LogitechDeviceKey(
                name: name,
                kind: kind,
                address: address,
                unitID: unitID,
                wirelessProductID: wpid,
                connection: connection
            ),
            live.logitechKey
        )
    }

    private func mergeLiveMX(_ live: MXMasterSnapshot, into devices: inout [ConnectedBluetoothDevice]) {
        guard live.connected else { return }
        if let index = devices.firstIndex(where: {
            isLiveMXDevice(
                kind: $0.deviceKind,
                address: $0.address,
                name: $0.name,
                live: live,
                unitID: $0.unitID,
                wpid: $0.wirelessProductID,
                connection: $0.connection
            )
        }) {
            devices[index].deviceKind = live.kind
            devices[index].isConnected = true
            devices[index].name = live.name
            devices[index].connection = live.connection
            devices[index].unitID = live.unitID == 0 ? devices[index].unitID : live.unitID
            devices[index].wirelessProductID = live.wirelessProductID == 0 ? devices[index].wirelessProductID : live.wirelessProductID
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
                isConnected: true,
                unitID: live.unitID == 0 ? nil : live.unitID,
                wirelessProductID: live.wirelessProductID == 0 ? nil : live.wirelessProductID,
                connection: live.connection
            )
        )
    }

    private func mergeBoltDevices(into devices: inout [ConnectedBluetoothDevice]) {
        guard let catalog = boltCatalog else { return }
        for receiver in catalog.receivers {
            for slot in receiver.devices where slot.deviceKind.isSupported {
                let bolt = slot.asConnectedDevice()
                if let index = devices.firstIndex(where: { DeviceIdentity.sameLogitech($0.logitechKey, bolt.logitechKey) }) {
                    devices[index].unitID = devices[index].unitID ?? bolt.unitID
                    devices[index].wirelessProductID = devices[index].wirelessProductID ?? bolt.wirelessProductID
                    if !devices[index].isConnected {
                        devices[index].isConnected = bolt.isConnected
                        devices[index].connection = bolt.connection
                        devices[index].address = bolt.address
                    }
                } else {
                    devices.append(bolt)
                }
            }
        }
    }

    private func collapseConnectedLogitech(_ devices: inout [ConnectedBluetoothDevice]) {
        var kept: [ConnectedBluetoothDevice] = []
        for device in devices {
            if let index = kept.firstIndex(where: { DeviceIdentity.sameLogitech($0.logitechKey, device.logitechKey) }) {
                kept[index] = preferLogitechConnection(kept[index], device)
            } else {
                kept.append(device)
            }
        }
        devices = kept
    }

    private func preferLogitechConnection(
        _ lhs: ConnectedBluetoothDevice,
        _ rhs: ConnectedBluetoothDevice
    ) -> ConnectedBluetoothDevice {
        let keep: ConnectedBluetoothDevice
        let other: ConnectedBluetoothDevice
        if lhs.connection == .bluetooth, lhs.isConnected {
            keep = lhs
            other = rhs
        } else if rhs.connection == .bluetooth, rhs.isConnected {
            keep = rhs
            other = lhs
        } else if lhs.isConnected {
            keep = lhs
            other = rhs
        } else {
            keep = rhs
            other = lhs
        }
        var next = keep
        next.unitID = keep.unitID ?? other.unitID
        next.wirelessProductID = keep.wirelessProductID ?? other.wirelessProductID
        next.isConnected = keep.isConnected || other.isConnected
        next.name = DeviceIdentity.preferredLogitechName(keep.name, other.name)
        if DeviceIdentity.looksLikeHardwareAddress(other.address),
           !DeviceIdentity.looksLikeHardwareAddress(keep.address) {
            next.address = other.address
        }
        return next
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

struct RecentFrontmostApp: Identifiable, Equatable, Sendable {
    var bundleID: String
    var name: String
    var id: String { bundleID }
}
