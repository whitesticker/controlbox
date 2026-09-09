import CoreGraphics
import Foundation
import ControlBoxCore
import IOKit.hid

struct MXMasterControl: Equatable, Sendable, Identifiable {
    var id: UInt16
    var title: String
    var down: Bool
}

struct MXMasterSnapshot: Equatable, Sendable {
    var connected = false
    var kind = DeviceKind.logitechMXMaster4
    var name = "MX Master"
    var product = "Logitech MX Master"
    var address = ""
    var status = "Looking for an MX Master…"
    var left = false
    var right = false
    var middle = false
    var back = false
    var forward = false
    var smartShift = false
    var modeShift = false
    var haptic = false
    var side = false
    var gestureDown = false
    var gestureHeld = false
    var wheelUp = false
    var wheelDown = false
    var thumbLeft = false
    var thumbRight = false
    var gestureDX: Double = 0
    var gestureDY: Double = 0
    var liveGesture: DeviceButton?
    var lastGesture: DeviceButton?
    var pendingGesture: DeviceButton?
    var pendingGestureOwner: DeviceButton?
    var liveGestureOwner: DeviceButton?
    var pendingScrollY: Double = 0
    var pendingScrollX: Double = 0
    /// HID++ `0x2150` `getThumbwheelInfo`: native ratchets and diverted increments per revolution.
    var thumbNativeResolution = 0
    var thumbDivertedResolution = 0
    var availableDPI: [Int] = []
    var appliedDPI = 0
    var smoothScrolling = true
    var smartShiftSupported = false
    var ratchetMode = MXRatchetMode.ratchet
    var smartShiftSensitivity = MappingProfile.smartShiftSensitivityDefault
    var extras: [MXMasterControl] = []
    var events: [InputLogEvent] = []
    var lastHIDEvent = "—"
    var batterySupported = false
    var batteryAvailable = false
    var batteryPercent: Int?
    var batteryCharging = false
    var batteryFull = false
    var batteryStateDescription = "Unknown"
    var hidppCapabilities = LogitechHIDPPCapabilities.none
    var availableButtons: Set<DeviceButton> = []
    var gestureCapableButtons: Set<DeviceButton> = []
    var dynamicButtons: [DeviceButton: Bool] = [:]
    var capturedButtonStates: [DeviceButton: Bool] = [:]
    var controlTitles: [DeviceButton: String] = [:]
    var connection = DeviceConnection.bluetooth
    var unitID: UInt32 = 0
    var wirelessProductID = 0
    var easySwitchHosts: [MXEasySwitchHost] = []

    var logitechKey: LogitechDeviceKey {
        LogitechDeviceKey(
            name: name,
            kind: kind,
            address: address,
            unitID: unitID == 0 ? nil : unitID,
            wirelessProductID: wirelessProductID == 0 ? nil : wirelessProductID,
            connection: connection
        )
    }

    /// Battery, identity, Easy-Switch, and firmware settings — the MX **device page**.
    /// Live clicks, gestures, and HID++ chatter stay off this compare so the
    /// settings Form is not invalidated at poll rate.
    func matchesSettings(_ other: MXMasterSnapshot) -> Bool {
        connected == other.connected
            && kind == other.kind
            && name == other.name
            && product == other.product
            && address == other.address
            && settingsStatus == other.settingsStatus
            && thumbNativeResolution == other.thumbNativeResolution
            && thumbDivertedResolution == other.thumbDivertedResolution
            && availableDPI == other.availableDPI
            && appliedDPI == other.appliedDPI
            && smoothScrolling == other.smoothScrolling
            && smartShiftSupported == other.smartShiftSupported
            && ratchetMode == other.ratchetMode
            && smartShiftSensitivity == other.smartShiftSensitivity
            && batterySupported == other.batterySupported
            && batteryAvailable == other.batteryAvailable
            && batteryPercent == other.batteryPercent
            && batteryCharging == other.batteryCharging
            && batteryFull == other.batteryFull
            && batteryStateDescription == other.batteryStateDescription
            && hidppCapabilities == other.hidppCapabilities
            && availableButtons == other.availableButtons
            && gestureCapableButtons == other.gestureCapableButtons
            && controlTitles == other.controlTitles
            && connection == other.connection
            && unitID == other.unitID
            && wirelessProductID == other.wirelessProductID
            && easySwitchHosts == other.easySwitchHosts
    }

    var settingsStatus: String {
        if status.localizedCaseInsensitiveContains("CID") { return "Connected" }
        return status
    }
}

final class LogitechMouseReader {
    private var model = LogitechMouseRegistry.generic
    private let discoveryClaimID = UUID()

    init() {
        snapshot.kind = model.kind
        snapshot.name = model.kind.title
        snapshot.product = model.kind.title
        snapshot.status = model.lookingStatus
        hapticCID = model.gestureCID
        gestureCID = model.gestureCID
        gestureCIDs = [model.gestureCID]
    }

    private var isGenericModel: Bool {
        model.kind == .logitechMouse
    }

    private var isHapticPanel: Bool {
        model.nativeHapticButtonBit != nil || model.gestureCID == 0x01A0
    }

    private struct DivertJob {
        var cid: UInt16
        var flags: UInt8
        var remap: UInt16
        var highFlags: UInt8
    }

    private var hidppManager: IOHIDManager?
    private var mouseManager: IOHIDManager?
    private var hidppDevice: IOHIDDevice?
    private var boltLink: LogiBoltHIDPPLink?
    private let lock = NSLock()
    private var snapshot = MXMasterSnapshot()
    private var reprogIndex: UInt8?
    private var nameIndex: UInt8?
    private var gestureCID: UInt16 = 0x01A0
    private var hapticCID: UInt16 = 0x01A0
    private var gestureCIDs: Set<UInt16> = [0x01A0]
    private var gestureOwnerButtons: Set<DeviceButton> = [.mxHaptic, .mxSide]
    private var holdSources: [DeviceButton: Set<String>] = [:]
    private var activeGestureCID: UInt16?
    private var lastHapticBit = false
    private var lastNativeButtons: UInt16 = 0
    private var ignoreNextRawXY = false
    private var pressed = Set<UInt16>()
    private var running = false
    private var recoverAttempts = 0
    private var recoverWork: DispatchWorkItem?
    private var hapticReleaseWork: DispatchWorkItem?
    private var hapticDownAt: Date?
    private var controls: [LogitechHIDPPControlDescriptor] = []
    private var extraCIDs: [UInt16: String] = [:]
    private var dynamicButtonByCID: [UInt16: DeviceButton] = [:]
    private var originalReportingByCID: [UInt16: LogitechHIDPPCIDReportingState] = [:]
    private var ownedReportingCIDs = Set<UInt16>()
    private var confirmedReportingCIDs = Set<UInt16>()
    private var routingGeneration = 0
    private var pendingRestoreRouteID: String?
    private var gestureOrigin = CGPoint.zero
    private var gestureDelta = CGSize.zero
    private var pointerOrigin = CGPoint.zero
    private var pointerDelta = CGSize.zero
    private var usingRawXY = false
    private var lastFirmwareXYAt = Date.distantPast
    private var cursorLocked = false
    private var cursorFrozen = false
    private var ready = false
    private var previousButtons: [String: Bool] = [:]
    private var wheelPulseUntil = Date.distantPast
    private var thumbPulseUntil = Date.distantPast
    private var lastGestureAt = Date.distantPast
    private var hidppBuffers: [ObjectIdentifier: UnsafeMutablePointer<UInt8>] = [:]
    private var featureCatalog = LogitechHIDPPFeatureCatalog()
    private var hiresWheelIndex: UInt8?
    private var originalHiresWheelMode: UInt8?
    private var ownsHiresWheelMode = false
    private var thumbWheelIndex: UInt8?
    private var didReadThumbWheelInfo = false
    private var originalThumbWheelRouting: (mode: UInt8, invert: UInt8)?
    private var ownsThumbWheelRouting = false
    private var wheelRoutingGeneration = 0
    private var forceSensingIndex: UInt8?
    private var pointerScaleIndex: UInt8?
    private var dpiIndex: UInt8?
    private var batteryIndex: UInt8?
    private var smartShiftEnhancedIndex: UInt8?
    private var smartShiftIndex: UInt8?
    private var hostsInfoIndex: UInt8?
    private var changeHostIndex: UInt8?
    private var batteryTimer: Timer?
    private var dpiValues: [Int] = []
    private var lastSentDPI = -1
    private var lastSentPointerScale = -1
    private var lastSentSmartShift: (mode: MXRatchetMode, sensitivity: Int)?
    private var lastAppliedOSDPI = -1
    private var lastAppliedOSPointerSpeed = -1.0
    private var desiredDPI = MappingProfile.defaultSensorDPI
    private var desiredPointerSpeed = 0.5
    private var desiredSmoothScrolling = true
    private var desiredThumbInvert = false
    private var desiredRatchetMode = MXRatchetMode.ratchet
    private var desiredSmartShiftSensitivity = MappingProfile.smartShiftSensitivityDefault
    private var lastWheelConfig: (divert: Bool, invert: Bool, highRes: Bool)?
    private var consecutiveTimeouts = 0
    private var easySwitchLoadAttempts = 0
    private var managed = false
    var naturalScrolling = true
    var onIdentityChanged: (() -> Void)?
    var injectEnabled = false {
        didSet {
            if injectEnabled != oldValue, isGenericModel {
                updateGenericControlRouting()
                lastWheelConfig = nil
                applyWheelRouting()
            }
        }
    }
    private var capturedButtons = Set<DeviceButton>()
    var wheelsEnabled = false {
        didSet {
            if wheelsEnabled != oldValue {
                lastWheelConfig = nil
                applyWheelRouting()
            }
        }
    }

    var current: MXMasterSnapshot {
        lock.lock()
        defer { lock.unlock() }
        var value = snapshot
        let now = Date()
        value.wheelUp = snapshot.wheelUp && now < wheelPulseUntil
        value.wheelDown = snapshot.wheelDown && now < wheelPulseUntil
        value.thumbLeft = snapshot.thumbLeft && now < thumbPulseUntil
        value.thumbRight = snapshot.thumbRight && now < thumbPulseUntil
        if now.timeIntervalSince(lastGestureAt) > 1.6 {
            value.lastGesture = nil
        }
        if value.gestureHeld || value.haptic || value.gestureDown {
            let live = LogitechGestureMotion.liveDelta(
                hid: gestureDelta,
                pointer: pointerDelta
            )
            value.liveGesture = Self.classify(delta: live, tapLimit: Self.pointerSwipeDistance)
            value.gestureDX = live.width
            value.gestureDY = live.height
            value.gestureDown = true
            value.gestureHeld = true
        }
        return value
    }

    func start() {
        running = true
        startHIDPP()
        startClickProbe()
    }

    func stop() {
        running = false
        recoverWork?.cancel()
        recoverWork = nil
        recoverAttempts = 0
        hapticReleaseWork?.cancel()
        hapticReleaseWork = nil
        hapticDownAt = nil
        lastHapticBit = false
        lastNativeButtons = 0
        clearGestureOwnership()
        hidppClient.cancelAll()
        unfreezeCursor()
        unlockCursor()
        restoreNativeReporting()
        stopClickProbe()
        stopBatteryTimer()
        if let hidppDevice {
            IOHIDDeviceUnscheduleFromRunLoop(hidppDevice, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        }
        if let hidppManager {
            IOHIDManagerUnscheduleFromRunLoop(hidppManager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(hidppManager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        if let mouseManager {
            IOHIDManagerUnscheduleFromRunLoop(mouseManager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(mouseManager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        hidppManager = nil
        mouseManager = nil
        if let hidppDevice {
            LogitechHIDPPDiscovery.release(hidppDevice, owner: discoveryClaimID)
        }
        hidppDevice = nil
        ready = false
        featureCatalog.removeAll()
        hiresWheelIndex = nil
        originalHiresWheelMode = nil
        ownsHiresWheelMode = false
        thumbWheelIndex = nil
        didReadThumbWheelInfo = false
        originalThumbWheelRouting = nil
        ownsThumbWheelRouting = false
        forceSensingIndex = nil
        pointerScaleIndex = nil
        dpiIndex = nil
        batteryIndex = nil
        smartShiftEnhancedIndex = nil
        smartShiftIndex = nil
        hostsInfoIndex = nil
        changeHostIndex = nil
        easySwitchLoadAttempts = 0
        dpiValues = []
        lastSentDPI = -1
        lastSentPointerScale = -1
        lastSentSmartShift = nil
        lastAppliedOSDPI = -1
        lastAppliedOSPointerSpeed = -1.0
        lastWheelConfig = nil
        consecutiveTimeouts = 0
        desiredDPI = MappingProfile.defaultSensorDPI
        desiredPointerSpeed = 0.5
        lastHapticBit = false
        desiredSmoothScrolling = true
        desiredThumbInvert = false
        desiredRatchetMode = .ratchet
        desiredSmartShiftSensitivity = MappingProfile.smartShiftSensitivityDefault
        naturalScrolling = true
        injectEnabled = false
        wheelsEnabled = false
        if let link = boltLink {
            link.onReport = nil
            boltLink = nil
        }
        for (id, buffer) in hidppBuffers {
            if let device = hidppDevice, ObjectIdentifier(device) == id {
                IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, nil, nil)
            }
            buffer.deallocate()
        }
        hidppBuffers.removeAll()
        lock.lock()
        snapshot = MXMasterSnapshot()
        snapshot.kind = model.kind
        snapshot.name = model.kind.title
        snapshot.product = model.kind.title
        snapshot.status = model.lookingStatus
        lock.unlock()
    }

    deinit {
        for buffer in hidppBuffers.values {
            buffer.deallocate()
        }
    }

    var usesBluetoothHIDPP: Bool { hidppDevice != nil && boltLink == nil }

    var usesBoltHIDPP: Bool { boltLink != nil }

    var boltSlotID: String? { boltLink.map { "\($0.receiverID)-\($0.slot)" } }

    var hidppCapabilities: LogitechHIDPPCapabilities { featureCatalog.capabilities }

    var hidppControls: [LogitechHIDPPControlDescriptor] { controls }

    private var canWriteHIDPP: Bool { hidppDevice != nil || boltLink != nil }

    private var currentRouteID: String? {
        if let boltLink {
            return "bolt:\(boltLink.id)"
        }
        if let hidppDevice {
            return "direct:\(LogitechHIDPPDiscovery.endpointKey(for: hidppDevice))"
        }
        return nil
    }

    private func clearDiscoveredControls(preservingRestore: Bool = false) {
        controls.removeAll()
        extraCIDs.removeAll()
        dynamicButtonByCID.removeAll()
        pressed.removeAll()
        confirmedReportingCIDs.removeAll()
        if !preservingRestore {
            originalReportingByCID.removeAll()
            ownedReportingCIDs.removeAll()
        }
        lock.lock()
        snapshot.left = false
        snapshot.right = false
        snapshot.middle = false
        snapshot.back = false
        snapshot.forward = false
        snapshot.smartShift = false
        snapshot.modeShift = false
        snapshot.haptic = false
        snapshot.side = false
        snapshot.availableButtons = []
        snapshot.gestureCapableButtons = []
        snapshot.dynamicButtons = [:]
        snapshot.capturedButtonStates = [:]
        snapshot.controlTitles = [:]
        snapshot.extras = []
        lock.unlock()
    }

    private func clearGestureOwnership() {
        routingGeneration += 1
        hapticCID = model.gestureCID
        gestureCID = model.gestureCID
        gestureOwnerButtons = [.mxHaptic]
        holdSources.removeAll()
        activeGestureCID = nil
        gestureCIDs = model.requiresGestureCID ? [model.gestureCID] : []
    }

    private lazy var hidppClient: LogitechHIDPP2Client = {
        let client = LogitechHIDPP2Client(
            initialSoftwareID: 0x0B,
            replyMatchPolicy: .softwareIDOnly,
            canWrite: { [weak self] in self?.canWriteHIDPP == true },
            shortReportsEnabled: { [weak self] in
                guard let self else { return false }
                return self.model.tryShortHIDPPReport && self.boltLink == nil
            },
            write: { [weak self] report in
                self?.writeHIDPPReport(report)
            }
        )
        client.onReply = { [weak self] in
            self?.consecutiveTimeouts = 0
        }
        client.onTimeout = { [weak self] metadata in
            guard let self, self.ready, metadata.options.countsTowardTimeouts else { return }
            self.consecutiveTimeouts += 1
            if self.consecutiveTimeouts >= 3 {
                self.notePipeDropped("HID++ timed out. Retrying…")
            }
        }
        client.onError = { [weak self] metadata in
            guard let self, self.ready, metadata?.options.dropsPipeOnError ?? true else { return }
            self.notePipeDropped("HID++ error. Retrying…")
        }
        return client
    }()

    @discardableResult
    func attachBolt(
        _ link: LogiBoltHIDPPLink,
        name: String,
        kind: DeviceKind,
        address: String,
        unitID: UInt32,
        wpid: Int
    ) -> Bool {
        guard running else { return false }
        let resolvedModel = LogitechMouseRegistry.model(
            productID: wpid,
            product: name,
            kind: kind
        )
        guard resolvedModel.acceptedKinds.contains(kind) || kind == resolvedModel.kind else {
            return false
        }
        let routeID = "bolt:\(link.id)"
        if let pendingRestoreRouteID, pendingRestoreRouteID != routeID {
            return false
        }
        if hidppDevice != nil { return false }
        if boltLink?.id == link.id, snapshot.connected { return true }
        detachBolt(restoreNative: boltLink != nil)
        model = resolvedModel
        clearGestureOwnership()
        boltLink = link
        link.onReport = { [weak self] report in
            guard let self else { return }
            if Thread.isMainThread {
                self.handleReport(report)
            } else {
                DispatchQueue.main.async {
                    self.handleReport(report)
                }
            }
        }
        hidppClient.cancelAll()
        featureCatalog.removeAll()
        let preservingRestore = pendingRestoreRouteID == routeID
        clearDiscoveredControls(preservingRestore: preservingRestore)
        reprogIndex = nil
        nameIndex = nil
        forceSensingIndex = nil
        hiresWheelIndex = nil
        thumbWheelIndex = nil
        didReadThumbWheelInfo = false
        if !preservingRestore {
            originalHiresWheelMode = nil
            ownsHiresWheelMode = false
            originalThumbWheelRouting = nil
            ownsThumbWheelRouting = false
        }
        pointerScaleIndex = nil
        dpiIndex = nil
        batteryIndex = nil
        smartShiftEnhancedIndex = nil
        smartShiftIndex = nil
        hostsInfoIndex = nil
        changeHostIndex = nil
        easySwitchLoadAttempts = 0
        stopBatteryTimer()
        ready = false
        lastAppliedOSDPI = -1
        lastAppliedOSPointerSpeed = -1.0
        consecutiveTimeouts = 0
        hidppClient.deviceIndex = UInt8(link.slot)
        lock.lock()
        snapshot.kind = model.acceptedKinds.contains(kind) ? kind : model.kind
        snapshot.name = name
        snapshot.product = name
        snapshot.address = address
        snapshot.connected = true
        snapshot.connection = .bolt
        snapshot.unitID = unitID
        snapshot.wirelessProductID = wpid
        snapshot.status = "Talking to \(name) over Logi Bolt…"
        snapshot.easySwitchHosts = []
        lock.unlock()
        probeDeviceIndices([UInt8(link.slot)])
        return true
    }

    func detachBolt() {
        detachBolt(restoreNative: true)
    }

    private func detachBolt(restoreNative: Bool) {
        guard boltLink != nil else { return }
        if restoreNative {
            restoreNativeReporting()
        }
        boltLink?.onReport = nil
        boltLink = nil
        hidppClient.cancelAll()
        featureCatalog.removeAll()
        ready = false
        stopBatteryTimer()
        unfreezeCursor()
        unlockCursor()
        clearGestureOwnership()
        lock.lock()
        snapshot = MXMasterSnapshot()
        snapshot.kind = model.kind
        snapshot.name = model.kind.title
        snapshot.product = model.kind.title
        snapshot.status = model.lookingStatus
        lock.unlock()
    }

    func consumePendingGesture() -> DeviceButton? {
        lock.lock()
        defer { lock.unlock() }
        let value = snapshot.pendingGesture
        snapshot.pendingGesture = nil
        snapshot.pendingGestureOwner = nil
        return value
    }

    func consumePendingScroll() {
        lock.lock()
        snapshot.pendingScrollY = 0
        snapshot.pendingScrollX = 0
        lock.unlock()
    }

    func setGestureOwners(_ buttons: Set<DeviceButton>) {
        var eligible: Set<DeviceButton> = [.mxHaptic, .mxSide, .mxSmartShift]
        eligible.formUnion(controls.compactMap { control in
            control.canOwnGestures ? button(for: control.cid) : nil
        })
        eligible.subtract([.mxLeft, .mxRight])
        let owners = buttons.intersection(eligible)
        if owners.isEmpty, buttons.contains(.mxHaptic) {
            gestureOwnerButtons = [.mxHaptic]
        } else if owners.isEmpty, buttons.contains(.mxSide) {
            gestureOwnerButtons = [.mxSide]
        } else {
            gestureOwnerButtons = owners
        }
        var cids = Set(gestureOwnerButtons.flatMap { self.cids(for: $0) })
        if model.requiresGestureCID {
            cids.insert(model.gestureCID)
        }
        if gestureOwnerButtons.contains(.mxSide) {
            cids.insert(0x00C3)
        }
        cids.subtract(Self.primaryClickCIDs)
        let previous = gestureCIDs
        guard cids != previous else { return }
        gestureCIDs = cids
        if cids.contains(model.gestureCID) {
            gestureCID = model.gestureCID
        } else if let haptic = cids.first(where: { $0 == hapticCID || $0 == 0x01A0 }) {
            gestureCID = haptic
        } else {
            gestureCID = cids.first ?? hapticCID
        }
        updateGestureReporting(previous: previous, current: cids)
    }

    func setCapturedButtons(_ buttons: Set<DeviceButton>) {
        guard buttons != capturedButtons else { return }
        capturedButtons = buttons
        if isGenericModel {
            updateGenericControlRouting()
        } else {
            updateKnownClickRouting()
        }
    }

    private func updateKnownClickRouting() {
        guard !isGenericModel,
              ready,
              let reprogIndex,
              let middle = controls.first(where: { $0.cid == 0x0052 && $0.isDivertable })
        else {
            return
        }
        routingGeneration += 1
        let generation = routingGeneration
        if capturedButtons.contains(.mxMiddle) {
            let job = DivertJob(
                cid: middle.cid,
                flags: gestureOwnerButtons.contains(.mxMiddle) && middle.canOwnGestures
                    ? Self.gestureReportingFlags
                    : Self.buttonReportingFlags,
                remap: 0,
                highFlags: 0
            )
            divert(jobs: [job], reprogIndex: reprogIndex, generation: generation) {}
        } else {
            restoreReporting([middle.cid], reprogIndex: reprogIndex) {}
        }
    }

    func setManaged(_ managed: Bool) {
        guard managed != self.managed else { return }
        self.managed = managed
        guard isGenericModel else { return }
        if managed {
            sendSensorSettingsIfNeeded()
            applyOSPointerSettingsIfNeeded()
            sendSmartShiftIfNeeded()
            updateGenericControlRouting()
            lastWheelConfig = nil
            applyWheelRouting()
        } else {
            updateGenericControlRouting()
            lastWheelConfig = nil
            applyWheelRouting()
        }
    }

    private func updateGestureReporting(previous: Set<UInt16>, current: Set<UInt16>) {
        guard ready, let reprogIndex else { return }
        if isGenericModel {
            updateGenericControlRouting()
            return
        }
        routingGeneration += 1
        let generation = routingGeneration
        var jobs = current.subtracting(previous).map { cid in
            DivertJob(
                cid: cid,
                flags: Self.gestureReportingFlags,
                remap: 0,
                highFlags: cid == model.gestureCID ? model.analyticsReportingFlags : 0
            )
        }
        let removed = previous.subtracting(current)
        let keepCaptured = removed.filter { cid in
            button(for: cid).map(capturedButtons.contains) == true
        }
        jobs.append(contentsOf: keepCaptured.map { cid in
            DivertJob(
                cid: cid,
                flags: Self.buttonReportingFlags,
                remap: 0,
                highFlags: 0
            )
        })
        let restore = removed.subtracting(keepCaptured)
        restoreReporting(Array(restore), reprogIndex: reprogIndex) { [weak self] in
            guard let self, self.routingGeneration == generation else { return }
            self.divert(
                jobs: jobs,
                reprogIndex: reprogIndex,
                generation: generation
            ) {}
        }
    }

    private func updateGenericControlRouting() {
        guard isGenericModel, ready, let reprogIndex else { return }
        routingGeneration += 1
        let generation = routingGeneration
        let routable = controls.filter {
            $0.isDivertable
                && !Self.primaryClickCIDs.contains($0.cid)
                && !Self.wheelCIDs.contains($0.cid)
                && button(for: $0.cid) != nil
        }
        let desired = routable.filter { control in
            injectEnabled
                && button(for: control.cid).map(capturedButtons.contains) == true
        }
        let desiredCIDs = Set(desired.map(\.cid))
        let jobs = desired.map { control -> DivertJob in
            let button = button(for: control.cid)
            return DivertJob(
                cid: control.cid,
                flags: button.map(gestureOwnerButtons.contains) == true && control.canOwnGestures
                    ? Self.gestureReportingFlags
                    : Self.buttonReportingFlags,
                remap: 0,
                highFlags: control.cid == model.gestureCID
                    ? model.analyticsReportingFlags
                    : 0
            )
        }
        let restore = ownedReportingCIDs.subtracting(desiredCIDs)
        restoreReporting(Array(restore), reprogIndex: reprogIndex) { [weak self] in
            guard let self, self.routingGeneration == generation else { return }
            self.divert(
                jobs: jobs,
                reprogIndex: reprogIndex,
                generation: generation
            ) {}
        }
    }

    func applyScrollDirection(_ natural: Bool) {
        guard naturalScrolling != natural else { return }
        naturalScrolling = natural
        lastWheelConfig = nil
        applyWheelRouting()
    }

    func applySensorDPI(_ dpi: Int) {
        let next = MappingProfile.nearestDPI(dpi, in: dpiValues)
        if next == desiredDPI, lastSentDPI == next, lastAppliedOSDPI == next { return }
        desiredDPI = next
        sendSensorSettingsIfNeeded()
        applyOSPointerSettingsIfNeeded()
    }

    func applyPointerSpeed(_ speed: Double) {
        let next = min(max(speed, 0), 1)
        if next == desiredPointerSpeed,
           lastAppliedOSPointerSpeed == next,
           lastSentPointerScale >= 0 || pointerScaleIndex == nil {
            return
        }
        desiredPointerSpeed = next
        sendSensorSettingsIfNeeded()
        applyOSPointerSettingsIfNeeded()
    }

    func applyThumbWheelInvert(_ inverted: Bool) {
        guard desiredThumbInvert != inverted else { return }
        desiredThumbInvert = inverted
        lastWheelConfig = nil
        applyWheelRouting()
    }

    func applySmoothScrolling(_ enabled: Bool) {
        guard desiredSmoothScrolling != enabled else { return }
        desiredSmoothScrolling = enabled
        lastWheelConfig = nil
        applyWheelRouting()
        publishMotionSettings()
    }

    func applySmartShift(mode: MXRatchetMode, sensitivity: Int) {
        let nextSensitivity = MappingProfile.clampSmartShiftSensitivity(sensitivity)
        if mode == desiredRatchetMode, nextSensitivity == desiredSmartShiftSensitivity {
            sendSmartShiftIfNeeded()
            return
        }
        desiredRatchetMode = mode
        desiredSmartShiftSensitivity = nextSensitivity
        sendSmartShiftIfNeeded()
        publishMotionSettings()
    }

    private func sendSensorSettingsIfNeeded() {
        guard ready else { return }
        if isGenericModel, !managed { return }
        let dpi = MappingProfile.nearestDPI(desiredDPI, in: dpiValues)
        var changed = false
        if let dpiIndex, dpi != lastSentDPI {
            request(featureIndex: dpiIndex, function: 3, params: [
                0,
                UInt8((dpi >> 8) & 0xFF),
                UInt8(dpi & 0xFF)
            ]) { _ in }
            lastSentDPI = dpi
            changed = true
        }
        if let pointerScaleIndex {
            let scaling = MappingProfile.pointerScale8_8(slider: desiredPointerSpeed, dpi: dpi)
            if scaling != lastSentPointerScale {
                request(featureIndex: pointerScaleIndex, function: 1, params: [
                    UInt8((scaling >> 8) & 0xFF),
                    UInt8(scaling & 0xFF)
                ]) { _ in }
                lastSentPointerScale = scaling
                changed = true
            }
        }
        applyOSPointerSettingsIfNeeded()
        if changed {
            publishMotionSettings()
        }
    }

    private func sendSmartShiftIfNeeded() {
        guard ready else { return }
        if isGenericModel, !managed { return }
        guard let featureIndex = smartShiftEnhancedIndex ?? smartShiftIndex else { return }
        let mode = desiredRatchetMode
        let sensitivity = MappingProfile.clampSmartShiftSensitivity(desiredSmartShiftSensitivity)
        if lastSentSmartShift?.mode == mode, lastSentSmartShift?.sensitivity == sensitivity {
            return
        }
        let function: UInt8 = smartShiftEnhancedIndex != nil ? 2 : 1
        request(
            featureIndex: featureIndex,
            function: function,
            params: [
                mode.hidppByte,
                UInt8(sensitivity),
                0
            ],
            countsTowardTimeouts: false,
            dropsPipeOnError: false
        ) { [weak self] _ in
            guard let self else { return }
            // MagSpeed writes can clear diverted reporting. Put the thumb
            // wheel and the dedicated gesture CID back without tearing the pipe down.
            self.lastWheelConfig = nil
            self.applyWheelRouting()
            self.restoreDedicatedGestureReporting()
        }
        lastSentSmartShift = (mode, sensitivity)
        publishMotionSettings()
    }

    private func applyOSPointerSettingsIfNeeded() {
        if isGenericModel, !managed { return }
        guard boltLink == nil, let hidppDevice else { return }
        let dpi = MappingProfile.nearestDPI(desiredDPI, in: dpiValues)
        guard dpi != lastAppliedOSDPI || desiredPointerSpeed != lastAppliedOSPointerSpeed else { return }
        PointerHIDSettings.apply(to: hidppDevice, dpi: dpi, pointerSpeed: desiredPointerSpeed)
        lastAppliedOSDPI = dpi
        lastAppliedOSPointerSpeed = desiredPointerSpeed
    }

    private func publishMotionSettings() {
        lock.lock()
        snapshot.availableDPI = dpiValues
        snapshot.appliedDPI = lastSentDPI > 0 ? lastSentDPI : desiredDPI
        snapshot.smoothScrolling = desiredSmoothScrolling
        snapshot.smartShiftSupported = smartShiftEnhancedIndex != nil || smartShiftIndex != nil
        snapshot.ratchetMode = desiredRatchetMode
        snapshot.smartShiftSensitivity = desiredSmartShiftSensitivity
        snapshot.hidppCapabilities = featureCatalog.capabilities
        lock.unlock()
    }

    func pollGesturePointer() {
        guard activeGestureCID != nil else {
            unfreezeCursor()
            unlockCursor()
            return
        }
        let owner = snapshot.liveGestureOwner ?? .mxHaptic
        if pinsPointer(for: owner) {
            pinCursor(forceWarp: false)
        } else if let live = snapshot.liveGestureOwner,
                  !cids(for: live).contains(where: pressed.contains) {
            finishHapticNow()
            return
        }
        lock.lock()
        snapshot.gestureDX = gestureDelta.width
        snapshot.gestureDY = gestureDelta.height
        snapshot.gestureHeld = true
        snapshot.gestureDown = true
        lock.unlock()
    }

    private func pinCursor(forceWarp: Bool) {
        if gestureOrigin == .zero {
            gestureOrigin = CGEvent(source: nil)?.location ?? .zero
        }
        CGAssociateMouseAndMouseCursorPosition(0)
        let now = CGEvent(source: nil)?.location ?? gestureOrigin
        if forceWarp || hypot(now.x - gestureOrigin.x, now.y - gestureOrigin.y) > 2 {
            CGWarpMouseCursorPosition(gestureOrigin)
        }
        cursorFrozen = true
        cursorLocked = true
    }

    private func lockCursor() {
        guard !cursorLocked else { return }
        gestureOrigin = CGEvent(source: nil)?.location ?? .zero
        CGAssociateMouseAndMouseCursorPosition(0)
        CGWarpMouseCursorPosition(gestureOrigin)
        cursorLocked = true
    }

    private func freezeCursor() {
        guard !cursorFrozen else { return }
        CGAssociateMouseAndMouseCursorPosition(0)
        cursorFrozen = true
    }

    private func unfreezeCursor() {
        guard cursorFrozen else { return }
        CGAssociateMouseAndMouseCursorPosition(1)
        cursorFrozen = false
    }

    private func unlockCursor() {
        guard cursorLocked else { return }
        if !cursorFrozen {
            CGWarpMouseCursorPosition(gestureOrigin)
            CGAssociateMouseAndMouseCursorPosition(1)
        }
        cursorLocked = false
    }

    private func startHIDPP() {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatchingMultiple(
            mgr,
            LogitechMouseRegistry.hidManagerMatches() as CFArray
        )
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(mgr, { context, _, _, device in
            guard let context else { return }
            let reader = Unmanaged<LogitechMouseReader>.fromOpaque(context)
            DispatchQueue.main.async {
                reader.takeUnretainedValue().attachHIDPP(device)
            }
        }, pointer)
        IOHIDManagerRegisterDeviceRemovalCallback(mgr, { context, _, _, device in
            guard let context else { return }
            let reader = Unmanaged<LogitechMouseReader>.fromOpaque(context)
            DispatchQueue.main.async {
                reader.takeUnretainedValue().detachHIDPP(device)
            }
        }, pointer)
        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        _ = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        hidppManager = mgr
        DispatchQueue.main.async { [weak self] in
            self?.scanHIDPP()
        }
    }

    private func scanHIDPP() {
        guard let hidppManager, hidppDevice == nil else { return }
        guard let copied = IOHIDManagerCopyDevices(hidppManager) else { return }
        var devices: [IOHIDDevice] = []
        for case let item as IOHIDDevice in (copied as NSSet) {
            devices.append(item)
        }
        devices.sort { lhs, rhs in
            let leftDesc = IOHIDDeviceGetProperty(lhs, kIOHIDReportDescriptorKey as CFString) != nil
            let rightDesc = IOHIDDeviceGetProperty(rhs, kIOHIDReportDescriptorKey as CFString) != nil
            if leftDesc != rightDesc { return leftDesc && !rightDesc }
            return false
        }
        for device in devices where LogitechMouseRegistry.matches(device) {
            attachHIDPP(device)
        }
    }

    private func startMouse() {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matches: [[String: Any]] = [
            [
                kIOHIDVendorIDKey as String: DeviceSupport.logitechVendorID,
                kIOHIDPrimaryUsagePageKey as String: 0x01,
                kIOHIDPrimaryUsageKey as String: 0x02
            ],
            [
                kIOHIDVendorIDKey as String: DeviceSupport.logitechVendorID,
                kIOHIDPrimaryUsagePageKey as String: 0x0C
            ]
        ]
        IOHIDManagerSetDeviceMatchingMultiple(mgr, matches as CFArray)
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(mgr, { context, _, _, value in
            guard let context else { return }
            Unmanaged<LogitechMouseReader>.fromOpaque(context).takeUnretainedValue().handleMouseValue(value)
        }, pointer)
        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        mouseManager = mgr
    }

    private func startClickProbe() {
        MXClickProbe.add(self)
    }

    private func stopClickProbe() {
        MXClickProbe.remove(self)
    }

    fileprivate func shouldSwallowPointerEvent(_ type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            if cursorFrozen { return true }
            return activeGestureCID != nil
                && Date().timeIntervalSince(lastFirmwareXYAt) < 0.08
        case .leftMouseDown, .leftMouseUp:
            return gestureOwnerButtons.contains(.mxLeft)
        case .rightMouseDown, .rightMouseUp:
            return gestureOwnerButtons.contains(.mxRight)
        case .otherMouseDown, .otherMouseUp:
            if let owner = gestureOwner(forOtherMouse: event) {
                return gestureOwnerButtons.contains(owner)
            }
            return false
        default:
            return false
        }
    }

    fileprivate func handleClickEvent(type: CGEventType, event: CGEvent) {
        let now = Date()
        var logs: [(String, Bool)] = []
        lock.lock()
        switch type {
        case .leftMouseDown, .leftMouseUp:
            let down = type == .leftMouseDown
            if snapshot.left != down {
                snapshot.left = down
                logs.append(("Left", down))
            }
        case .rightMouseDown, .rightMouseUp:
            let down = type == .rightMouseDown
            if snapshot.right != down {
                snapshot.right = down
                logs.append(("Right", down))
            }
        case .otherMouseDown, .otherMouseUp:
            let down = type == .otherMouseDown
            let button = event.getIntegerValueField(.mouseEventButtonNumber)
            if button == 2, snapshot.middle != down {
                snapshot.middle = down
                logs.append(("Middle", down))
            } else if button == 3, snapshot.back != down {
                snapshot.back = down
                logs.append(("Back", down))
            } else if button == 4, snapshot.forward != down {
                snapshot.forward = down
                logs.append(("Forward", down))
            } else if (button == 6 || button == 5), model.nativeHapticButtonBit != nil {
                if snapshot.haptic != down {
                    snapshot.haptic = down
                    logs.append((model.gestureControlTitle, down))
                }
            } else if button == 7 {
                if snapshot.side != down {
                    snapshot.side = down
                    logs.append(("Gesture button", down))
                }
            }
        case .scrollWheel:
            let dy = Self.scrollAxis(event, line: .scrollWheelEventDeltaAxis1, point: .scrollWheelEventPointDeltaAxis1, fixed: .scrollWheelEventFixedPtDeltaAxis1)
            let dx = Self.scrollAxis(event, line: .scrollWheelEventDeltaAxis2, point: .scrollWheelEventPointDeltaAxis2, fixed: .scrollWheelEventFixedPtDeltaAxis2)
            applyExclusiveScrollPulses(
                vertical: dy,
                horizontal: dx,
                now: now,
                allowThumb: !thumbComesFromHIDPP,
                invertVertical: false,
                logs: &logs
            )
        default:
            break
        }
        lock.unlock()
        switch type {
        case .leftMouseDown:
            addHoldSource(.mxLeft, "cg")
        case .leftMouseUp:
            removeHoldSource(.mxLeft, "cg")
        case .rightMouseDown:
            addHoldSource(.mxRight, "cg")
        case .rightMouseUp:
            removeHoldSource(.mxRight, "cg")
        case .otherMouseDown:
            if let owner = gestureOwner(forOtherMouse: event) {
                addHoldSource(owner, "cg")
            }
        case .otherMouseUp:
            if let owner = gestureOwner(forOtherMouse: event) {
                removeHoldSource(owner, "cg")
            }
        default:
            break
        }
        for (label, pressed) in logs {
            logEvent(label, pressed: pressed)
        }
    }

    private func gestureOwner(forOtherMouse event: CGEvent) -> DeviceButton? {
        switch event.getIntegerValueField(.mouseEventButtonNumber) {
        case 2: return .mxMiddle
        case 3: return .mxBack
        case 4: return .mxForward
        case 5, 6:
            return model.nativeHapticButtonBit != nil ? .mxHaptic : nil
        case 7:
            return .mxSide
        default: return nil
        }
    }

    private func isGestureOwner(_ button: DeviceButton) -> Bool {
        gestureOwnerButtons.contains(button)
    }

    /// Haptic pad still pins the cursor. The MX **gesture button** uses firmware
    /// raw XY (OpenLogi) and must not pin.
    private func pinsPointer(for owner: DeviceButton) -> Bool {
        owner == .mxHaptic
    }

    private func addHoldSource(_ owner: DeviceButton, _ source: String) {
        guard isGestureOwner(owner) else { return }
        if !pinsPointer(for: owner), source != "hidpp" { return }
        var sources = holdSources[owner] ?? []
        sources.insert(source)
        holdSources[owner] = sources
        beginGesture(owner: owner)
    }

    private func removeHoldSource(_ owner: DeviceButton, _ source: String) {
        var sources = holdSources[owner] ?? []
        sources.remove(source)
        if sources.isEmpty {
            holdSources[owner] = nil
            endGesture(owner: owner)
        } else {
            holdSources[owner] = sources
        }
    }

    private func beginGesture(owner: DeviceButton) {
        guard isGestureOwner(owner) else { return }
        cancelHapticRelease()
        let pin = pinsPointer(for: owner)
        if activeGestureCID != nil {
            if pin {
                pinCursor(forceWarp: false)
            }
            lock.lock()
            snapshot.gestureDown = true
            snapshot.gestureHeld = true
            if owner == .mxHaptic { snapshot.haptic = true }
            if owner == .mxSide { snapshot.side = true }
            lock.unlock()
            return
        }
        activeGestureCID = cids(for: owner).first ?? model.gestureCID
        usingRawXY = true
        ignoreNextRawXY = pin && isHapticPanel
        hapticDownAt = Date()
        gestureDelta = .zero
        pointerDelta = .zero
        gestureOrigin = CGEvent(source: nil)?.location ?? .zero
        pointerOrigin = gestureOrigin
        if pin {
            pinCursor(forceWarp: true)
        }
        lock.lock()
        snapshot.gestureDown = true
        snapshot.gestureHeld = true
        snapshot.liveGestureOwner = owner
        if owner == .mxHaptic { snapshot.haptic = true }
        if owner == .mxSide { snapshot.side = true }
        lock.unlock()
        noteLastEvent("\(owner.title) gesture down")
    }

    private func endGesture(owner: DeviceButton) {
        guard isGestureOwner(owner) else { return }
        lock.lock()
        let current = snapshot.liveGestureOwner
        lock.unlock()
        guard current == nil || current == owner else { return }
        finishHapticNow()
    }

    private func cancelActiveGesture() {
        cancelHapticRelease()
        activeGestureCID = nil
        holdSources.removeAll()
        hapticDownAt = nil
        lock.lock()
        snapshot.liveGestureOwner = nil
        snapshot.liveGesture = nil
        snapshot.gestureDown = lastHapticBit
        snapshot.gestureHeld = false
        snapshot.haptic = lastHapticBit
        snapshot.gestureDX = 0
        snapshot.gestureDY = 0
        lock.unlock()
        unfreezeCursor()
        unlockCursor()
        gestureDelta = .zero
        pointerDelta = .zero
        pointerOrigin = .zero
        usingRawXY = false
        lastFirmwareXYAt = .distantPast
    }

    private func applyHapticEdge(down: Bool) {
        if down {
            addHoldSource(.mxHaptic, "pad")
        } else {
            removeHoldSource(.mxHaptic, "pad")
        }
    }

    private func cancelHapticRelease() {
        hapticReleaseWork?.cancel()
        hapticReleaseWork = nil
    }

    private func finishHapticNow() {
        cancelHapticRelease()
        guard activeGestureCID != nil else { return }
        let cid = activeGestureCID ?? model.gestureCID
        activeGestureCID = nil
        if let owner = snapshot.liveGestureOwner {
            holdSources[owner] = nil
        }
        finishGesture(released: cid)
    }

    private func attachHIDPP(_ incoming: IOHIDDevice) {
        guard LogitechMouseRegistry.matches(incoming) else { return }
        if boltLink != nil { return }
        let routeID = "direct:\(LogitechHIDPPDiscovery.endpointKey(for: incoming))"
        if let pendingRestoreRouteID, pendingRestoreRouteID != routeID {
            return
        }
        if isSameDevice(incoming, hidppDevice) { return }
        guard hidppDevice == nil,
              LogitechHIDPPDiscovery.claim(incoming, owner: discoveryClaimID)
        else {
            return
        }
        beginProbe(incoming)
    }

    private func isSameDevice(_ lhs: IOHIDDevice, _ rhs: IOHIDDevice?) -> Bool {
        guard let rhs else { return false }
        return CFEqual(lhs, rhs)
    }

    private func beginProbe(_ device: IOHIDDevice) {
        model = LogitechMouseRegistry.model(of: device)
        let routeID = "direct:\(LogitechHIDPPDiscovery.endpointKey(for: device))"
        hidppClient.cancelAll()
        featureCatalog.removeAll()
        let preservingRestore = pendingRestoreRouteID == routeID
        clearDiscoveredControls(preservingRestore: preservingRestore)
        clearGestureOwnership()
        reprogIndex = nil
        nameIndex = nil
        forceSensingIndex = nil
        hiresWheelIndex = nil
        thumbWheelIndex = nil
        didReadThumbWheelInfo = false
        if !preservingRestore {
            originalHiresWheelMode = nil
            ownsHiresWheelMode = false
            originalThumbWheelRouting = nil
            ownsThumbWheelRouting = false
        }
        pointerScaleIndex = nil
        dpiIndex = nil
        batteryIndex = nil
        smartShiftEnhancedIndex = nil
        smartShiftIndex = nil
        hostsInfoIndex = nil
        changeHostIndex = nil
        easySwitchLoadAttempts = 0
        stopBatteryTimer()
        ready = false
        hidppDevice = device
        lastAppliedOSDPI = -1
        lastAppliedOSPointerSpeed = -1.0
        _ = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        registerHIDPPCallback(device)
        applyOSPointerSettingsIfNeeded()
        let product = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? model.kind.title
        lock.lock()
        snapshot.kind = LogitechMouseRegistry.resolvedKind(of: device)
        snapshot.name = product
        snapshot.product = product
        snapshot.address = DeviceIdentity.fromHID(device)
        snapshot.connected = true
        snapshot.connection = .bluetooth
        snapshot.unitID = 0
        snapshot.wirelessProductID = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue ?? 0
        snapshot.status = "Talking to \(product) over HID++…"
        snapshot.easySwitchHosts = []
        lock.unlock()
        probeDeviceIndices([0xFF, 0x00, 1, 2, 3, 4, 5, 6])
    }

    private func registerHIDPPCallback(_ device: IOHIDDevice) {
        let id = ObjectIdentifier(device)
        if hidppBuffers[id] != nil { return }
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
        hidppBuffers[id] = buffer
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(
            device,
            buffer,
            64,
            { context, _, _, _, _, report, length in
                guard let context, length > 0 else { return }
                let reader = Unmanaged<LogitechMouseReader>.fromOpaque(context).takeUnretainedValue()
                if report[0] == 0x02 {
                    reader.handleNativeMouseReport(report, length: length)
                    return
                }
                let bytes = Array(UnsafeBufferPointer(start: report, count: length))
                if Thread.isMainThread {
                    reader.handleReport(bytes)
                } else {
                    DispatchQueue.main.async {
                        reader.handleReport(bytes)
                    }
                }
            },
            pointer
        )
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    private func teardownHIDPP(_ device: IOHIDDevice) {
        releaseReportBuffer(device)
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        _ = IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        let routeID = "direct:\(LogitechHIDPPDiscovery.endpointKey(for: device))"
        if pendingRestoreRouteID != routeID {
            LogitechHIDPPDiscovery.release(device, owner: discoveryClaimID)
        }
    }

    private func releaseReportBuffer(_ device: IOHIDDevice) {
        guard let buffer = hidppBuffers.removeValue(forKey: ObjectIdentifier(device)) else { return }
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, nil, nil)
        DispatchQueue.main.async {
            buffer.deallocate()
        }
    }

    private func detachHIDPP(_ incoming: IOHIDDevice) {
        if !isSameDevice(incoming, hidppDevice) {
            releaseReportBuffer(incoming)
            return
        }
        restoreNativeReporting()
        teardownHIDPP(incoming)
        stopBatteryTimer()
        unfreezeCursor()
        hidppDevice = nil
        ready = false
        hidppClient.cancelAll()
        featureCatalog.removeAll()
        clearGestureOwnership()
        unlockCursor()
        lock.lock()
        snapshot = MXMasterSnapshot()
        snapshot.kind = model.kind
        snapshot.name = model.kind.title
        snapshot.status = "\(model.kind.title) disconnected"
        lock.unlock()
        setStatus("\(model.kind.title) disconnected")
        scheduleRecover()
    }

    private func notePipeDropped(_ reason: String) {
        guard running else { return }
        restoreNativeReporting()
        ready = false
        consecutiveTimeouts = 0
        hidppClient.cancelAll()
        featureCatalog.removeAll()
        clearGestureOwnership()
        stopBatteryTimer()
        if let current = hidppDevice {
            teardownHIDPP(current)
            hidppDevice = nil
        }
        if boltLink != nil {
            detachBolt(restoreNative: false)
            setStatus(reason)
            return
        }
        setStatus(reason)
        scheduleRecover()
    }

    private func scheduleRecover() {
        guard running, hidppManager != nil, boltLink == nil else { return }
        recoverWork?.cancel()
        let delay: TimeInterval = recoverAttempts < 3 ? 1.0 : 5.0
        recoverAttempts += 1
        let work = DispatchWorkItem { [weak self] in
            self?.retryHIDPP()
        }
        recoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func retryHIDPP() {
        guard running, hidppManager != nil, boltLink == nil else { return }
        if hidppDevice != nil { return }
        scanHIDPP()
        if hidppDevice == nil {
            scheduleRecover()
        }
    }

    private func failHIDPPAndTryNext(_ message: String) {
        hidppClient.cancelAll()
        featureCatalog.removeAll()
        if boltLink != nil {
            detachBolt(restoreNative: false)
            setStatus(message)
            return
        }
        if let current = hidppDevice {
            teardownHIDPP(current)
            hidppDevice = nil
        }
        setStatus(message)
        scheduleRecover()
    }

    private func probeDeviceIndices(_ indices: [UInt8]) {
        guard let index = indices.first else {
            failHIDPPAndTryNext("No HID++ reply from the mouse. LogiPluginService can block this even after Options+ is removed.")
            return
        }
        hidppClient.deviceIndex = index
        request(featureIndex: 0, function: 0, params: [0x00, 0x01]) { [weak self] data in
            guard let self else { return }
            if data != nil {
                self.identifyDevice()
                return
            }
            self.request(featureIndex: 0, function: 1, params: [0, 0, 0]) { [weak self] ping in
                guard let self else { return }
                if ping != nil {
                    self.identifyDevice()
                } else {
                    self.probeDeviceIndices(Array(indices.dropFirst()))
                }
            }
        }
    }

    private func identifyDevice() {
        let fallbackName = hidppDevice.flatMap {
            IOHIDDeviceGetProperty($0, kIOHIDProductKey as CFString) as? String
        } ?? snapshot.name
        request(featureIndex: 0, function: 0, params: [0x00, 0x05]) { [weak self] data in
            guard let self else { return }
            if let data, let nameIndex = data.first, nameIndex != 0 {
                self.nameIndex = nameIndex
                self.featureCatalog[LogitechHIDPPFeatureID.deviceName] = nameIndex
            } else if !self.model.requiresMXMasterName
                        || DeviceSupport.isMXMasterName(fallbackName) {
                self.nameIndex = nil
                self.lookupReprogThen {
                    self.finishSetup(named: fallbackName)
                }
                return
            } else {
                self.failHIDPPAndTryNext("MX Master did not report a name.")
                return
            }
            self.lookupReprogThen {
                if self.nameIndex != nil {
                    self.readName(lengthIndex: 0, assembled: "")
                } else {
                    self.finishSetup(named: fallbackName)
                }
            }
        }
    }

    private func readName(lengthIndex: Int, assembled: String) {
        guard let nameIndex else { return }
        if lengthIndex == 0 {
            request(featureIndex: nameIndex, function: 0, params: []) { [weak self] data in
                guard let self, let length = data?.first, length > 0 else {
                    self?.finishSetup(named: self?.fallbackProductName ?? "MX Master")
                    return
                }
                self.readName(lengthIndex: Int(length), assembled: "")
            }
            return
        }
        if assembled.utf8.count >= lengthIndex {
            finishSetup(named: assembled)
            return
        }
        request(featureIndex: nameIndex, function: 1, params: [UInt8(assembled.utf8.count)]) { [weak self] data in
            guard let self, let data else {
                self?.finishSetup(named: assembled.isEmpty ? self?.fallbackProductName ?? "MX Master" : assembled)
                return
            }
            let chunk = data.filter { $0 != 0 }
            let piece = String(bytes: chunk, encoding: .utf8) ?? ""
            self.readName(lengthIndex: lengthIndex, assembled: assembled + piece)
        }
    }

    private func finishSetup(named: String) {
        let trimmed = named.trimmingCharacters(in: .whitespacesAndNewlines)
        let accepted = !model.requiresMXMasterName || DeviceSupport.isMXMasterName(trimmed)
        lock.lock()
        if let hidppDevice {
            snapshot.kind = LogitechMouseRegistry.resolvedKind(of: hidppDevice)
        }
        snapshot.name = trimmed.isEmpty ? snapshot.kind.title : trimmed
        snapshot.product = snapshot.name
        snapshot.connected = accepted
        snapshot.status = accepted ? "Connected" : "Logitech device is not \(snapshot.kind.title)"
        lock.unlock()
        guard accepted else {
            failHIDPPAndTryNext("Logitech device is not an MX Master")
            return
        }
        loadDeviceIdentity { [weak self] in
            guard let self else { return }
            self.restorePendingCIDReporting { [weak self] in
                guard let self else { return }
                if self.model.enablesHiddenFeatures {
                    self.enableHiddenFeaturesThenDivert()
                } else {
                    self.enumerateAndDivert(index: 0, count: -1)
                }
            }
        }
    }

    private var fallbackProductName: String {
        let name = snapshot.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? model.kind.title : name
    }

    private func loadDeviceIdentity(completion: @escaping () -> Void) {
        lookupFeature(
            LogitechHIDPPFeatureID.deviceInformation,
            countsTowardTimeouts: false,
            allowShortReport: false,
            dropsPipeOnError: false
        ) { [weak self] index in
            guard let self, let index else {
                completion()
                return
            }
            self.request(
                featureIndex: index,
                function: 0,
                params: [],
                countsTowardTimeouts: false,
                allowShortReport: false,
                dropsPipeOnError: false
            ) { [weak self] data in
                defer { completion() }
                guard let self, let data, data.count >= 5 else { return }
                let unitID = UInt32(data[1]) << 24
                    | UInt32(data[2]) << 16
                    | UInt32(data[3]) << 8
                    | UInt32(data[4])
                guard unitID != 0 else { return }
                self.lock.lock()
                self.snapshot.unitID = unitID
                self.lock.unlock()
                self.onIdentityChanged?()
            }
        }
    }

    private func restorePendingCIDReporting(completion: @escaping () -> Void) {
        guard pendingRestoreRouteID == currentRouteID,
              !ownedReportingCIDs.isEmpty,
              let reprogIndex
        else {
            clearPendingRestoreIfComplete()
            completion()
            return
        }
        restoreReporting(
            ownedReportingCIDs.sorted(),
            reprogIndex: reprogIndex
        ) { [weak self] in
            guard let self else { return }
            if self.ownedReportingCIDs.isEmpty {
                self.clearPendingRestoreIfComplete()
                completion()
            } else {
                self.setStatus("Restoring previous mouse reporting…")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.restorePendingCIDReporting(completion: completion)
                }
            }
        }
    }

    private func clearPendingRestoreIfComplete() {
        if ownedReportingCIDs.isEmpty,
           !ownsHiresWheelMode,
           !ownsThumbWheelRouting {
            pendingRestoreRouteID = nil
        }
    }

    private func enableHiddenFeaturesThenDivert() {
        request(featureIndex: 0, function: 0, params: [0x1E, 0x00]) { [weak self] data in
            guard let self else { return }
            if let index = data?.first, index != 0 {
                self.request(featureIndex: index, function: 1, params: [1]) { [weak self] _ in
                    self?.enumerateAndDivert(index: 0, count: -1)
                }
            } else {
                self.enumerateAndDivert(index: 0, count: -1)
            }
        }
    }

    private func lookupReprogThen(_ completion: @escaping () -> Void) {
        lookupReprog(attemptsLeft: 3, then: completion)
    }

    private func lookupReprog(attemptsLeft: Int, then completion: @escaping () -> Void) {
        request(featureIndex: 0, function: 0, params: [0x1B, 0x04]) { [weak self] data in
            guard let self else { return }
            if let index = data?.first, index != 0 {
                self.reprogIndex = index
                self.featureCatalog[LogitechHIDPPFeatureID.reprogrammableControlsV4] = index
                completion()
                return
            }
            if attemptsLeft > 1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    self?.lookupReprog(attemptsLeft: attemptsLeft - 1, then: completion)
                }
                return
            }
            self.reprogIndex = nil
            completion()
        }
    }

    private func enumerateAndDivert(index: Int, count: Int) {
        guard let reprogIndex else {
            // BLE MX4 haptic is native HID button 7. Reprog is only for extra
            // buttons; a timed-out lookup must not leave the session stuck.
            setStatus("Connected. Extra-button HID++ is still coming up…")
            ready = true
            consecutiveTimeouts = 0
            recoverAttempts = 0
            recoverWork?.cancel()
            recoverWork = nil
            lookupMotionFeatures { [weak self] in
                guard let self else { return }
                self.lastWheelConfig = nil
                self.lastSentDPI = -1
                self.lastSentPointerScale = -1
                self.lastSentSmartShift = nil
                self.sendSensorSettingsIfNeeded()
                self.sendSmartShiftIfNeeded()
                self.applyWheelRouting()
                self.startBatteryPolling()
                self.publishMotionSettings()
            }
            return
        }
        if count < 0 {
            request(featureIndex: reprogIndex, function: 0, params: []) { [weak self] data in
                let total = Int(data?.first ?? 0)
                if total <= 0 {
                    if self?.isGenericModel == true {
                        self?.reprogIndex = nil
                        self?.enumerateAndDivert(index: 0, count: 0)
                    } else {
                        self?.setStatus("No reprogrammable controls. Quit Logi Options+ and reconnect the mouse.")
                    }
                    return
                }
                self?.controls.removeAll()
                self?.enumerateAndDivert(index: 0, count: total)
            }
            return
        }
        if index >= count {
            chooseGestureCID()
            armForceSensingThenDivert()
            return
        }
        request(featureIndex: reprogIndex, function: 1, params: [UInt8(index)]) { [weak self] data in
            guard let self, let data, data.count >= 2 else {
                self?.enumerateAndDivert(index: index + 1, count: count)
                return
            }
            let cid = Self.be16(data, 0)
            let task = data.count >= 4 ? Self.be16(data, 2) : 0
            let flagsLow = data.count > 4 ? data[4] : 0
            let flagsHigh = data.count > 8 ? data[8] : 0
            let info = LogitechHIDPPControlDescriptor(
                cid: cid,
                task: task,
                flagsLow: flagsLow,
                flagsHigh: flagsHigh
            )
            self.controls.append(info)
            self.enumerateAndDivert(index: index + 1, count: count)
        }
    }

    private func chooseGestureCID() {
        dynamicButtonByCID.removeAll()
        let dynamicControls = controls
            .filter {
                knownButton(for: $0.cid) == nil
                    && $0.isDivertable
                    && !Self.wheelCIDs.contains($0.cid)
            }
            .sorted { $0.cid < $1.cid }
        for (control, button) in zip(dynamicControls, DeviceButton.mxExtraButtons) {
            dynamicButtonByCID[control.cid] = button
        }

        if model.requiresGestureCID {
            hapticCID = model.gestureCID
            gestureCID = model.gestureCID
            gestureCIDs = [model.gestureCID]
        } else if let haptic = controls.first(where: {
            $0.cid == 0x01A0 && $0.canOwnGestures
        }) {
            hapticCID = haptic.cid
            gestureCID = haptic.cid
            gestureCIDs = [haptic.cid]
        } else if let discovered = controls.first(where: {
            $0.cid == model.gestureCID && $0.canOwnGestures
        }) ?? controls.first(where: {
            Self.knownGestureCIDs.contains($0.cid) && $0.canOwnGestures
        }) {
            hapticCID = discovered.cid
            gestureCID = discovered.cid
            gestureCIDs = [discovered.cid]
        } else {
            gestureCIDs = []
        }
        extraCIDs.removeAll()
        for control in controls {
            extraCIDs[control.cid] = title(for: control.cid, task: control.task)
                + String(format: " (%04X)", control.cid)
        }
        var availableButtons = Set(controls.compactMap { button(for: $0.cid) })
        var gestureCapableButtons = Set(controls.compactMap { control in
            control.canOwnGestures ? button(for: control.cid) : nil
        })
        var controlTitles: [DeviceButton: String] = [:]
        for control in controls {
            if let button = button(for: control.cid), controlTitles[button] == nil {
                controlTitles[button] = dynamicButtonByCID[control.cid] == nil
                    ? title(for: control.cid, task: control.task)
                    : extraCIDs[control.cid]
            }
        }
        if isHapticPanel || controls.contains(where: { $0.cid == 0x01A0 }) {
            availableButtons.insert(.mxHaptic)
            gestureCapableButtons.insert(.mxHaptic)
            controlTitles[.mxHaptic] = DeviceButton.mxHaptic.title
        }
        if controls.contains(where: { $0.cid == 0x00C4 }) {
            availableButtons.insert(.mxSmartShift)
            gestureCapableButtons.insert(.mxSmartShift)
            if controlTitles[.mxSmartShift] == nil {
                controlTitles[.mxSmartShift] = DeviceButton.mxSmartShift.title
            }
        }
        if controls.contains(where: { $0.cid == 0x00C3 })
            || (model.requiresGestureCID && !isHapticPanel) {
            availableButtons.insert(.mxSide)
            gestureCapableButtons.insert(.mxSide)
            controlTitles[.mxSide] = DeviceButton.mxSide.title
        }
        lock.lock()
        snapshot.availableButtons = availableButtons
        snapshot.gestureCapableButtons = gestureCapableButtons
        snapshot.controlTitles = controlTitles
        snapshot.hidppCapabilities = featureCatalog.capabilities
        lock.unlock()
        applyPressed(pressed)
        let listed = controls.map { String(format: "%04X", $0.cid) }.joined(separator: " ")
        let found = !gestureCIDs.isEmpty
        noteLastEvent(found || !model.requiresGestureCID
            ? "CIDs \(listed)"
            : String(format: "no %04X in table: %@", model.gestureCID, listed))
    }

    private func armForceSensingThenDivert() {
        guard let feature = model.forceSensingFeature, let threshold = model.forceThreshold else {
            divertKnownButtons()
            return
        }
        lookupFeature(feature) { [weak self] index in
            guard let self else { return }
            self.forceSensingIndex = index
            guard let index else {
                self.divertKnownButtons()
                return
            }
            self.request(
                featureIndex: index,
                function: 3,
                params: [
                    0,
                    UInt8(threshold >> 8),
                    UInt8(threshold & 0xFF)
                ]
            ) { [weak self] _ in
                self?.divertKnownButtons()
            }
        }
    }

    private func divertKnownButtons() {
        guard let reprogIndex else { return }
        var jobs: [DivertJob] = []
        if !isGenericModel {
            jobs.append(
                DivertJob(
                    cid: model.gestureCID,
                    flags: Self.gestureReportingFlags,
                    remap: 0,
                    highFlags: model.analyticsReportingFlags
                )
            )
            if model.gestureCID != 0x00C3 {
                jobs.append(
                    DivertJob(
                        cid: 0x00C3,
                        flags: gestureOwnerButtons.contains(.mxSide)
                            ? Self.gestureReportingFlags
                            : Self.buttonReportingFlags,
                        remap: 0,
                        highFlags: 0
                    )
                )
            }
            for cid in gestureCIDs where cid != model.gestureCID && cid != 0x00C3 {
                jobs.append(
                    DivertJob(
                        cid: cid,
                        flags: Self.gestureReportingFlags,
                        remap: 0,
                        highFlags: 0
                    )
                )
            }
        }
        for control in controls where control.isDivertable && !isGenericModel {
            if Self.nativeClickCIDs.contains(control.cid) { continue }
            if Self.wheelCIDs.contains(control.cid) { continue }
            if control.cid == model.gestureCID { continue }
            if control.cid == 0x00C3 { continue }
            if gestureCIDs.contains(control.cid) { continue }
            if model.extraButtonCIDs.contains(control.cid) {
                jobs.append(DivertJob(cid: control.cid, flags: Self.buttonReportingFlags, remap: 0, highFlags: 0))
                continue
            }
            if !model.divertsUnknownButtons { continue }
            if isGenericModel, button(for: control.cid) == nil { continue }
            if control.supportsRawXY, !isGenericModel { continue }
            jobs.append(DivertJob(cid: control.cid, flags: Self.buttonReportingFlags, remap: 0, highFlags: 0))
        }
        divert(jobs: jobs, reprogIndex: reprogIndex) { [weak self] in
            guard let self else { return }
            self.ready = true
            self.consecutiveTimeouts = 0
            self.recoverAttempts = 0
            self.recoverWork?.cancel()
            self.recoverWork = nil
            self.updateGenericControlRouting()
            self.updateKnownClickRouting()
            self.confirmGestureReporting()
            self.lookupMotionFeatures {
                self.lastWheelConfig = nil
                self.lastSentDPI = -1
                self.lastSentPointerScale = -1
                self.lastSentSmartShift = nil
                self.sendSensorSettingsIfNeeded()
                self.sendSmartShiftIfNeeded()
                self.applyWheelRouting()
                self.startBatteryPolling()
                self.publishMotionSettings()
            }
        }
    }

    private func restoreDedicatedGestureReporting() {
        guard !isGenericModel, model.requiresGestureCID, ready, let reprogIndex else { return }
        var jobs = [
            DivertJob(
                cid: model.gestureCID,
                flags: Self.gestureReportingFlags,
                remap: 0,
                highFlags: model.analyticsReportingFlags
            )
        ]
        if model.gestureCID != 0x00C3 {
            jobs.append(
                DivertJob(
                    cid: 0x00C3,
                    flags: gestureOwnerButtons.contains(.mxSide)
                        ? Self.gestureReportingFlags
                        : Self.buttonReportingFlags,
                    remap: 0,
                    highFlags: 0
                )
            )
        }
        divert(jobs: jobs, reprogIndex: reprogIndex) {}
    }

    private func confirmGestureReporting() {
        guard let reprogIndex else { return }
        guard !isGenericModel else {
            setStatus("Connected")
            return
        }
        let cid = model.gestureCID
        request(
            featureIndex: reprogIndex,
            function: 2,
            params: [
                UInt8(cid >> 8),
                UInt8(cid & 0xFF)
            ]
        ) { [weak self] data in
            guard let self else { return }
            let cidHex = String(format: "%04X", cid)
            if let data, !data.isEmpty {
                let hex = data.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " ")
                self.noteLastEvent("\(cidHex) reporting \(hex)")
            } else {
                self.noteLastEvent("\(cidHex) reporting missing")
            }
            self.setStatus("Connected")
        }
    }

    private func divert(
        jobs: [DivertJob],
        reprogIndex: UInt8,
        generation: Int? = nil,
        completion: @escaping () -> Void
    ) {
        if let generation, generation != routingGeneration {
            completion()
            return
        }
        guard let job = jobs.first else {
            completion()
            return
        }
        captureOriginalReporting(cid: job.cid, reprogIndex: reprogIndex) { [weak self] captured in
            guard let self else { return }
            if let generation, generation != self.routingGeneration {
                completion()
                return
            }
            // 3S has no native pad. Skipping divert when getCidReporting fails
            // leaves CID 0x00C3 undiverted while Back/Forward still work.
            let dedicated = !self.isGenericModel
                && (job.cid == self.model.gestureCID || job.cid == 0x00C3)
            guard captured || dedicated else {
                self.divert(
                    jobs: Array(jobs.dropFirst()),
                    reprogIndex: reprogIndex,
                    generation: generation,
                    completion: completion
                )
                return
            }
            if captured {
                self.ownedReportingCIDs.insert(job.cid)
            }
            let params = LogitechHIDPP2.cidReportingParameters(
                cid: job.cid,
                flags: job.flags,
                remap: job.remap,
                highFlags: job.highFlags
            )
            self.request(
                featureIndex: reprogIndex,
                function: 3,
                params: params,
                countsTowardTimeouts: false,
                dropsPipeOnError: false
            ) { [weak self] data in
                guard let self else { return }
                if data != nil {
                    self.confirmedReportingCIDs.insert(job.cid)
                }
                self.divert(
                    jobs: Array(jobs.dropFirst()),
                    reprogIndex: reprogIndex,
                    generation: generation,
                    completion: completion
                )
            }
        }
    }

    private func captureOriginalReporting(
        cid: UInt16,
        reprogIndex: UInt8,
        completion: @escaping (Bool) -> Void
    ) {
        if originalReportingByCID[cid] != nil {
            completion(true)
            return
        }
        request(
            featureIndex: reprogIndex,
            function: 2,
            params: [UInt8(cid >> 8), UInt8(cid & 0xFF)],
            countsTowardTimeouts: false,
            allowShortReport: false,
            dropsPipeOnError: false
        ) { [weak self] data in
            guard let self,
                  let state = LogitechHIDPPCIDReportingState(payload: data),
                  state.cid == cid
            else {
                completion(false)
                return
            }
            self.originalReportingByCID[cid] = state
            completion(true)
        }
    }

    private func restoreReporting(
        _ cids: [UInt16],
        reprogIndex: UInt8,
        completion: @escaping () -> Void
    ) {
        guard let cid = cids.first else {
            completion()
            return
        }
        guard let original = originalReportingByCID[cid] else {
            ownedReportingCIDs.remove(cid)
            restoreReporting(
                Array(cids.dropFirst()),
                reprogIndex: reprogIndex,
                completion: completion
            )
            return
        }
        request(
            featureIndex: reprogIndex,
            function: 3,
            params: original.restoreParameters,
            countsTowardTimeouts: false,
            allowShortReport: false,
            dropsPipeOnError: false
        ) { [weak self] data in
            guard let self else { return }
            if data != nil {
                self.ownedReportingCIDs.remove(cid)
                self.confirmedReportingCIDs.remove(cid)
                self.originalReportingByCID[cid] = nil
                self.pressed.remove(cid)
                self.applyPressed(self.pressed)
            }
            self.restoreReporting(
                Array(cids.dropFirst()),
                reprogIndex: reprogIndex,
                completion: completion
            )
        }
    }

    private func lookupFeature(
        _ id: UInt16,
        countsTowardTimeouts: Bool = true,
        allowShortReport: Bool = true,
        dropsPipeOnError: Bool = true,
        completion: @escaping (UInt8?) -> Void
    ) {
        request(
            featureIndex: 0,
            function: 0,
            params: LogitechHIDPP2.featureLookupParameters(id),
            countsTowardTimeouts: countsTowardTimeouts,
            allowShortReport: allowShortReport,
            dropsPipeOnError: dropsPipeOnError
        ) { [weak self] data in
            guard let data, data.count >= 1 else {
                completion(nil)
                return
            }
            let index = data[0] == 0 && id != 0 ? nil : data[0]
            if let index {
                self?.featureCatalog[id] = index
            }
            completion(index)
        }
    }

    private func lookupMotionFeatures(completion: @escaping () -> Void) {
        lookupFeature(0x0001) { [weak self] featureSet in
            guard let self else { return }
            if let featureSet {
                self.request(featureIndex: featureSet, function: 0, params: []) { [weak self] data in
                    let slots = LogitechHIDPP2.featureSetIndices(
                        count: Int(data?.first ?? 0)
                    )
                    self?.readFeatureSlots(
                        setIndex: featureSet,
                        slots: slots,
                        then: completion
                    )
                }
            } else {
                self.lookupMotionFeaturesByID(then: completion)
            }
        }
    }

    private func readFeatureSlots(
        setIndex: UInt8,
        slots: [UInt8],
        then completion: @escaping () -> Void
    ) {
        guard let slot = slots.first else {
            lookupMotionFeaturesByID(then: completion)
            return
        }
        request(featureIndex: setIndex, function: 1, params: [slot]) { [weak self] data in
            guard let self else { return }
            if let data, data.count >= 2 {
                let id = Self.be16(data, 0)
                let index = slot
                self.featureCatalog[id] = index
                switch id {
                case 0x2121: self.hiresWheelIndex = index
                case 0x2150: self.thumbWheelIndex = index
                case 0x2205: self.pointerScaleIndex = index
                case 0x2201: self.dpiIndex = index
                case 0x1004: self.batteryIndex = index
                case 0x2111: self.smartShiftEnhancedIndex = index
                case 0x2110: self.smartShiftIndex = index
                case 0x1814: self.changeHostIndex = index
                case 0x1815: self.hostsInfoIndex = index
                default: break
                }
            }
            self.readFeatureSlots(
                setIndex: setIndex,
                slots: Array(slots.dropFirst()),
                then: completion
            )
        }
    }

    private func lookupMotionFeaturesByID(then completion: @escaping () -> Void) {
        lookupFeature(0x2121) { [weak self] hires in
            guard let self else { return }
            if self.hiresWheelIndex == nil { self.hiresWheelIndex = hires }
            self.lookupFeature(0x2150) { [weak self] thumb in
                guard let self else { return }
                if self.thumbWheelIndex == nil { self.thumbWheelIndex = thumb }
                self.lookupFeature(0x2205) { [weak self] scaling in
                    guard let self else { return }
                    if self.pointerScaleIndex == nil { self.pointerScaleIndex = scaling }
                    self.lookupFeature(0x2201) { [weak self] dpi in
                        guard let self else { return }
                        if self.dpiIndex == nil { self.dpiIndex = dpi }
                        self.lookupFeature(0x1004) { [weak self] battery in
                            guard let self else { return }
                            if self.batteryIndex == nil { self.batteryIndex = battery }
                            self.lookupFeature(0x2111) { [weak self] enhanced in
                                guard let self else { return }
                                if self.smartShiftEnhancedIndex == nil {
                                    self.smartShiftEnhancedIndex = enhanced
                                }
                                self.lookupFeature(0x2110) { [weak self] legacy in
                                    guard let self else { return }
                                    if self.smartShiftIndex == nil { self.smartShiftIndex = legacy }
                                    self.readDPIList(then: completion)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func readDPIList(then completion: @escaping () -> Void) {
        guard let dpiIndex else {
            completion()
            return
        }
        request(featureIndex: dpiIndex, function: 1, params: [0]) { [weak self] data in
            defer { completion() }
            guard let self, let data, data.count >= 3 else { return }
            var values: [Int] = []
            var rangeStart: Int?
            var offset = 1
            while offset + 1 < data.count {
                let raw = Int(Self.be16(data, offset))
                offset += 2
                if raw == 0 { break }
                if raw >> 13 == 0b111 {
                    let step = max(raw & 0x1FFF, 1)
                    rangeStart = values.last
                    if let start = rangeStart, offset + 1 < data.count {
                        let end = Int(Self.be16(data, offset))
                        offset += 2
                        if end > start {
                            var dpi = start + step
                            while dpi < end {
                                values.append(dpi)
                                dpi += step
                            }
                            values.append(end)
                        }
                    }
                    rangeStart = nil
                } else {
                    values.append(raw)
                }
            }
            self.dpiValues = Array(Set(values)).sorted()
            self.publishMotionSettings()
        }
    }

    private func startBatteryPolling() {
        lock.lock()
        snapshot.batterySupported = batteryIndex != nil
        lock.unlock()
        readBattery()
        startBatteryTimer()
        loadEasySwitchHosts()
    }

    private func loadEasySwitchHosts() {
        let read = { [weak self] in
            guard let self else { return }
            MXEasySwitchHIDPP.load(
                hostsInfoIndex: self.hostsInfoIndex,
                changeHostIndex: self.changeHostIndex,
                request: { [weak self] feature, function, params, completion in
                    guard let self else {
                        completion(nil)
                        return
                    }
                    self.request(
                        featureIndex: feature,
                        function: function,
                        params: params,
                        countsTowardTimeouts: false,
                        allowShortReport: false,
                        dropsPipeOnError: false,
                        completion: completion
                    )
                }
            ) { [weak self] hosts in
                guard let self else { return }
                self.lock.lock()
                self.snapshot.easySwitchHosts = hosts
                self.lock.unlock()
                if hosts.isEmpty, self.ready, self.easySwitchLoadAttempts < 1 {
                    self.easySwitchLoadAttempts += 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                        self?.loadEasySwitchHosts()
                    }
                }
            }
        }
        lookupFeature(
            MXEasySwitchHIDPP.hostsInfoFeature,
            countsTowardTimeouts: false,
            allowShortReport: false,
            dropsPipeOnError: false
        ) { [weak self] hostsInfo in
            guard let self else { return }
            self.hostsInfoIndex = hostsInfo
            self.lookupFeature(
                MXEasySwitchHIDPP.changeHostFeature,
                countsTowardTimeouts: false,
                allowShortReport: false,
                dropsPipeOnError: false
            ) { [weak self] changeHost in
                guard let self else { return }
                self.changeHostIndex = changeHost
                read()
            }
        }
    }

    func reloadEasySwitchHosts() {
        easySwitchLoadAttempts = 0
        loadEasySwitchHosts()
    }

    func setFriendlyName(_ name: String) {
        guard ready else { return }
        lookupFeature(
            MXFriendlyNameHIDPP.featureID,
            countsTowardTimeouts: false,
            allowShortReport: false,
            dropsPipeOnError: false
        ) { [weak self] index in
            guard let self, let index else { return }
            MXFriendlyNameHIDPP.set(
                name: name,
                featureIndex: index,
                request: { [weak self] feature, function, params, completion in
                    guard let self else {
                        completion(nil)
                        return
                    }
                    self.request(
                        featureIndex: feature,
                        function: function,
                        params: params,
                        countsTowardTimeouts: false,
                        allowShortReport: false,
                        dropsPipeOnError: false,
                        completion: completion
                    )
                }
            ) { _ in }
        }
    }

    private func readBattery() {
        guard let batteryIndex else { return }
        request(featureIndex: batteryIndex, function: 1, params: []) { [weak self] data in
            self?.applyBattery(data)
        }
    }

    private func applyBattery(_ data: Data?) {
        guard let reading = LogitechUnifiedBatteryReading(payload: data) else { return }
        lock.lock()
        snapshot.batterySupported = true
        snapshot.batteryAvailable = true
        snapshot.batteryPercent = reading.percentage
        snapshot.batteryCharging = reading.isCharging
        snapshot.batteryFull = reading.isFull
        snapshot.batteryStateDescription = reading.stateDescription
        lock.unlock()
    }

    private func startBatteryTimer() {
        stopBatteryTimer()
        guard batteryIndex != nil else { return }
        let timer = Timer(timeInterval: 300, repeats: true) { [weak self] _ in
            self?.readBattery()
        }
        timer.tolerance = 30
        RunLoop.main.add(timer, forMode: .common)
        batteryTimer = timer
    }

    private func stopBatteryTimer() {
        batteryTimer?.invalidate()
        batteryTimer = nil
    }

    private func applyWheelRouting() {
        guard ready else { return }
        guard hiresWheelIndex != nil || thumbWheelIndex != nil else { return }
        if pendingRestoreRouteID == currentRouteID,
           ownsHiresWheelMode || ownsThumbWheelRouting {
            wheelRoutingGeneration += 1
            let generation = wheelRoutingGeneration
            restoreWheelRouting(generation: generation) { [weak self] in
                guard let self, self.wheelRoutingGeneration == generation else { return }
                self.clearPendingRestoreIfComplete()
                self.lastWheelConfig = nil
                if self.ownsHiresWheelMode || self.ownsThumbWheelRouting {
                    self.setStatus("Restoring previous wheel reporting…")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        self?.applyWheelRouting()
                    }
                    return
                }
                if self.managed {
                    self.applyWheelRouting()
                }
            }
            return
        }
        if isGenericModel, !managed {
            wheelRoutingGeneration += 1
            restoreWheelRouting(generation: wheelRoutingGeneration)
            return
        }
        // Leave the main wheel on native HID so a CGEvent tap can reverse and
        // scale it. Only the thumb wheel stays on HID++ (it often has no HID axis).
        // High-res bit is Logitech “smooth scrolling”: many small steps per notch.
        let divertThumb = wheelsEnabled
        let highRes = desiredSmoothScrolling
        let invertThumb = desiredThumbInvert
        if lastWheelConfig?.divert == divertThumb,
           lastWheelConfig?.invert == invertThumb,
           lastWheelConfig?.highRes == highRes {
            readThumbWheelInfoIfNeeded()
            return
        }
        lastWheelConfig = (divertThumb, invertThumb, highRes)
        wheelRoutingGeneration += 1
        let generation = wheelRoutingGeneration
        if let hiresWheelIndex {
            let flags: UInt8 = highRes ? 0b0000_0010 : 0
            applyHiresWheelMode(
                index: hiresWheelIndex,
                flags: flags,
                generation: generation
            ) { [weak self] in
                guard let self, self.wheelRoutingGeneration == generation else { return }
                self.applyThumbRouting(
                    divert: divertThumb,
                    invert: invertThumb,
                    generation: generation
                )
                self.readThumbWheelInfoIfNeeded()
            }
            publishMotionSettings()
            return
        }
        applyThumbRouting(
            divert: divertThumb,
            invert: invertThumb,
            generation: generation
        )
        readThumbWheelInfoIfNeeded()
        publishMotionSettings()
    }

    private func applyHiresWheelMode(
        index: UInt8,
        flags: UInt8,
        generation: Int,
        completion: @escaping () -> Void
    ) {
        let write = { [weak self] in
            guard let self, self.wheelRoutingGeneration == generation else { return }
            self.ownsHiresWheelMode = true
            self.request(
                featureIndex: index,
                function: 2,
                params: [flags],
                countsTowardTimeouts: false,
                dropsPipeOnError: false
            ) { _ in completion() }
        }
        if originalHiresWheelMode != nil {
            write()
            return
        }
        request(
            featureIndex: index,
            function: 1,
            params: [],
            countsTowardTimeouts: false,
            dropsPipeOnError: false
        ) { [weak self] data in
            guard let self, self.wheelRoutingGeneration == generation else { return }
            guard let mode = data?.first else {
                self.lastWheelConfig = nil
                completion()
                return
            }
            self.originalHiresWheelMode = mode
            write()
        }
    }

    private func applyThumbRouting(divert: Bool, invert: Bool, generation: Int) {
        guard let thumbWheelIndex else { return }
        let write = { [weak self] in
            guard let self, self.wheelRoutingGeneration == generation else { return }
            self.ownsThumbWheelRouting = true
            self.request(
                featureIndex: thumbWheelIndex,
                function: 2,
                params: [divert ? 1 : 0, invert ? 1 : 0],
                countsTowardTimeouts: false,
                dropsPipeOnError: false
            ) { _ in }
        }
        if originalThumbWheelRouting != nil {
            write()
            return
        }
        request(
            featureIndex: thumbWheelIndex,
            function: 1,
            params: [],
            countsTowardTimeouts: false,
            dropsPipeOnError: false
        ) { [weak self] data in
            guard let self, self.wheelRoutingGeneration == generation else { return }
            guard let data, data.count >= 2 else {
                self.lastWheelConfig = nil
                return
            }
            self.originalThumbWheelRouting = (data[0], data[1] & 1)
            write()
        }
    }

    private func restoreWheelRouting(
        generation: Int,
        completion: @escaping () -> Void = {}
    ) {
        let restoreThumb = { [weak self] in
            guard let self, self.wheelRoutingGeneration == generation else { return }
            guard self.ownsThumbWheelRouting,
                  let thumbWheelIndex = self.thumbWheelIndex,
                  let originalThumbWheelRouting = self.originalThumbWheelRouting
            else {
                self.clearPendingRestoreIfComplete()
                completion()
                return
            }
            self.request(
                featureIndex: thumbWheelIndex,
                function: 2,
                params: [originalThumbWheelRouting.mode, originalThumbWheelRouting.invert],
                countsTowardTimeouts: false,
                dropsPipeOnError: false
            ) { [weak self] data in
                guard let self, self.wheelRoutingGeneration == generation else { return }
                if data != nil {
                    self.ownsThumbWheelRouting = false
                    self.originalThumbWheelRouting = nil
                }
                self.clearPendingRestoreIfComplete()
                completion()
            }
        }
        if ownsHiresWheelMode,
           let hiresWheelIndex,
           let originalHiresWheelMode {
            request(
                featureIndex: hiresWheelIndex,
                function: 2,
                params: [originalHiresWheelMode],
                countsTowardTimeouts: false,
                dropsPipeOnError: false
            ) { [weak self] data in
                guard let self, self.wheelRoutingGeneration == generation else { return }
                if data != nil {
                    self.ownsHiresWheelMode = false
                    self.originalHiresWheelMode = nil
                }
                restoreThumb()
            }
        } else {
            restoreThumb()
        }
    }

    /// OpenLogi `getThumbwheelInfo`: native ratchets vs diverted increments per
    /// revolution. Diverted scroll has to scale by that ratio or one physical
    /// notch is six line ticks on MX4 (20 / 120).
    private func readThumbWheelInfoIfNeeded() {
        guard let thumbWheelIndex, !didReadThumbWheelInfo else { return }
        didReadThumbWheelInfo = true
        request(
            featureIndex: thumbWheelIndex,
            function: 0,
            params: [],
            countsTowardTimeouts: false,
            dropsPipeOnError: false
        ) { [weak self] data in
            guard let self, let data, data.count >= 4 else { return }
            let native = Int(Self.be16(data, 0))
            let diverted = Int(Self.be16(data, 2))
            self.lock.lock()
            self.snapshot.thumbNativeResolution = native
            self.snapshot.thumbDivertedResolution = diverted
            self.lock.unlock()
        }
    }

    private func restoreNativeReporting() {
        guard canWriteHIDPP else { return }
        let hasOwnedState = !ownedReportingCIDs.isEmpty
            || ownsHiresWheelMode
            || ownsThumbWheelRouting
        if hasOwnedState, let currentRouteID {
            pendingRestoreRouteID = currentRouteID
        }
        confirmedReportingCIDs.removeAll()
        wheelRoutingGeneration += 1
        hidppClient.cancelAll()
        if let reprogIndex {
            for cid in ownedReportingCIDs.sorted() {
                guard let original = originalReportingByCID[cid] else { continue }
                sendHIDPP(
                    featureIndex: reprogIndex,
                    function: 3,
                    params: original.restoreParameters
                )
            }
        }
        if ownsHiresWheelMode,
           let hiresWheelIndex,
           let originalHiresWheelMode {
            sendHIDPP(featureIndex: hiresWheelIndex, function: 2, params: [originalHiresWheelMode])
        }
        if ownsThumbWheelRouting,
           let thumbWheelIndex,
           let originalThumbWheelRouting {
            sendHIDPP(
                featureIndex: thumbWheelIndex,
                function: 2,
                params: [originalThumbWheelRouting.mode, originalThumbWheelRouting.invert]
            )
        }
        pressed.removeAll()
        applyPressed([])
    }

    private func sendHIDPP(featureIndex: UInt8, function: UInt8, params: [UInt8]) {
        hidppClient.send(featureIndex: featureIndex, function: function, parameters: params)
    }

    private func writeHIDPPReport(_ report: [UInt8]) {
        if let boltLink {
            boltLink.write(report)
            return
        }
        guard let hidppDevice, !report.isEmpty else { return }
        _ = report.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return kIOReturnError }
            return IOHIDDeviceSetReport(hidppDevice, kIOHIDReportTypeOutput, CFIndex(report[0]), base, report.count)
        }
    }

    private func handleHiresWheel(_ payload: Data) {
        guard payload.count >= 3 else { return }
        let delta = Int16(bitPattern: Self.be16(payload, 1))
        guard delta != 0 else { return }
        let now = Date()
        lock.lock()
        if delta > 0 {
            snapshot.wheelDown = true
            snapshot.wheelUp = false
        } else {
            snapshot.wheelUp = true
            snapshot.wheelDown = false
        }
        wheelPulseUntil = now.addingTimeInterval(0.18)
        lock.unlock()
        noteLastEvent(String(format: "wheel %+d", delta))
    }

    private func handleThumbWheel(_ payload: Data) {
        guard payload.count >= 2 else { return }
        let delta = Int16(bitPattern: Self.be16(payload, 0))
        guard delta != 0 else { return }
        let now = Date()
        lock.lock()
        snapshot.pendingScrollX += Double(delta)
        if delta > 0 {
            snapshot.thumbRight = true
            snapshot.thumbLeft = false
        } else {
            snapshot.thumbLeft = true
            snapshot.thumbRight = false
        }
        thumbPulseUntil = now.addingTimeInterval(0.18)
        lock.unlock()
        noteLastEvent(String(format: "thumb %+d", delta))
    }

    private func request(
        featureIndex: UInt8,
        function: UInt8,
        params: [UInt8],
        countsTowardTimeouts: Bool = true,
        allowShortReport: Bool = true,
        dropsPipeOnError: Bool = true,
        completion: @escaping (Data?) -> Void
    ) {
        hidppClient.request(
            featureIndex: featureIndex,
            function: function,
            parameters: params,
            options: LogitechHIDPP2Client.RequestOptions(
                countsTowardTimeouts: countsTowardTimeouts,
                allowShortReport: allowShortReport,
                dropsPipeOnError: dropsPipeOnError
            ),
            completion: completion
        )
    }

    private func handleReport(_ report: [UInt8]) {
        guard report.first != 0x02 else { return }
        guard report.count >= 4 else { return }
        var bytes = report
        if bytes[0] != 0x10 && bytes[0] != 0x11 && bytes.count >= 3 {
            bytes.insert(0x11, at: 0)
        }
        let result = hidppClient.handle(bytes)
        guard case let .event(incoming) = result else {
            return
        }
        let featureIndex = incoming.featureIndex
        let function = incoming.function
        let swID = incoming.softwareID
        let payload = incoming.payload
        if let reprogIndex, featureIndex == reprogIndex {
            if function == 0 {
                handleDivertedButtons(payload)
            } else if function == 1 {
                handleRawXY(payload)
            } else if function == 2 {
                handleAnalytics(payload)
            } else if swID == 0 {
                noteLastEvent(String(format: "reprog fn%d %@", function, Self.hex(payload)))
            }
            return
        }
        if let hiresWheelIndex, featureIndex == hiresWheelIndex, function == 0 {
            handleHiresWheel(payload)
            return
        }
        if let thumbWheelIndex, featureIndex == thumbWheelIndex, function == 0 {
            handleThumbWheel(payload)
            return
        }
        if let forceSensingIndex, featureIndex == forceSensingIndex {
            handleForceSensing(payload)
            return
        }
        if let batteryIndex, featureIndex == batteryIndex {
            applyBattery(payload)
            return
        }
        noteLastEvent(String(format: "HID++ feat %02X fn%d %@", featureIndex, function, Self.hex(payload)))
    }

    private func handleNativeMouseReport(_ report: UnsafePointer<UInt8>, length: Int) {
        guard length >= 2 else { return }
        let buttonBits = nativeButtonBits(report, length: length)
        applyNativeButtons(buttonBits)
        if let bit = model.nativeHapticButtonBit {
            let hapticDown = report[1] & bit != 0
            if hapticDown != lastHapticBit {
                lastHapticBit = hapticDown
                if hapticDown {
                    pressed.insert(model.gestureCID)
                } else {
                    pressed.remove(model.gestureCID)
                }
                applyPressed(pressed)
                applyHapticEdge(down: hapticDown)
            }
        }
        let xyOffset = 1 + model.nativeMouseButtonBytes
        var nativeVertical = 0
        var nativeHorizontal = 0
        if length > xyOffset + 3 {
            nativeVertical = Int(Int8(bitPattern: report[xyOffset + 3]))
        }
        if length > xyOffset + 4 {
            nativeHorizontal = Int(Int8(bitPattern: report[xyOffset + 4]))
        }
        if nativeVertical != 0 || nativeHorizontal != 0 {
            applyNativeScroll(vertical: nativeVertical, horizontal: nativeHorizontal)
        }
        guard activeGestureCID != nil, length >= xyOffset + 3 else { return }
        lock.lock()
        let owner = snapshot.liveGestureOwner
        lock.unlock()
        guard owner == .mxHaptic else { return }
        let dx = Self.signExtend12(Int(report[xyOffset]) | (Int(report[xyOffset + 1] & 0x0F) << 8))
        let dy = Self.signExtend12((Int(report[xyOffset + 1]) >> 4) | (Int(report[xyOffset + 2]) << 4))
        guard dx != 0 || dy != 0 else { return }
        guard abs(dx) < 512, abs(dy) < 512 else { return }
        usingRawXY = true
        addGestureHID(dx: Double(dx), dy: Double(dy))
        lock.lock()
        snapshot.gestureDX = gestureDelta.width
        snapshot.gestureDY = gestureDelta.height
        snapshot.gestureDown = true
        snapshot.gestureHeld = true
        lock.unlock()
    }

    private func nativeButtonBits(_ report: UnsafePointer<UInt8>, length: Int) -> UInt16 {
        var bits = UInt16(report[1])
        if model.nativeMouseButtonBytes > 1, length > 2 {
            bits |= UInt16(report[2]) << 8
        }
        return bits
    }

    private func applyNativeButtons(_ bits: UInt16) {
        let previous = lastNativeButtons
        guard bits != previous else { return }
        lastNativeButtons = bits
        lock.lock()
        snapshot.left = bits & 0x01 != 0
        snapshot.right = bits & 0x02 != 0
        snapshot.middle = bits & 0x04 != 0
        lock.unlock()
        if (bits ^ previous) & 0x01 != 0 {
            logEvent("Left", pressed: bits & 0x01 != 0)
        }
        if (bits ^ previous) & 0x02 != 0 {
            logEvent("Right", pressed: bits & 0x02 != 0)
        }
        if (bits ^ previous) & 0x04 != 0 {
            logEvent("Middle", pressed: bits & 0x04 != 0)
        }
    }

    private func applyNativeScroll(vertical: Int, horizontal: Int) {
        let now = Date()
        var logs: [(String, Bool)] = []
        lock.lock()
        applyExclusiveScrollPulses(
            vertical: Double(vertical),
            horizontal: Double(horizontal),
            now: now,
            allowThumb: !thumbComesFromHIDPP,
            invertVertical: true,
            logs: &logs
        )
        lock.unlock()
        for (label, pressed) in logs {
            logEvent(label, pressed: pressed)
        }
    }

    /// Thumb ticks come from HID++ `0x2150` once that feature is diverted.
    /// CG / native pan on the same report as the main wheel is not the thumb.
    private var thumbComesFromHIDPP: Bool { wheelsEnabled && thumbWheelIndex != nil }

    /// Wheel and thumb must not pulse together. MX high-res / smooth reports
    /// often carry a leftover axis-2 delta on a vertical notch.
    private func applyExclusiveScrollPulses(
        vertical: Double,
        horizontal: Double,
        now: Date,
        allowThumb: Bool,
        invertVertical: Bool,
        logs: inout [(String, Bool)]
    ) {
        let dx = allowThumb ? horizontal : 0
        let dy = vertical
        if dy == 0, dx == 0 { return }
        if abs(dy) >= abs(dx) {
            let wheelDown = invertVertical ? dy > 0 : dy < 0
            if wheelDown {
                snapshot.wheelDown = true
                snapshot.wheelUp = false
                logs.append(("Wheel down", true))
            } else {
                snapshot.wheelUp = true
                snapshot.wheelDown = false
                logs.append(("Wheel up", true))
            }
            wheelPulseUntil = now.addingTimeInterval(0.18)
            return
        }
        if dx > 0 {
            snapshot.thumbRight = true
            snapshot.thumbLeft = false
            logs.append(("Thumb wheel right", true))
        } else {
            snapshot.thumbLeft = true
            snapshot.thumbRight = false
            logs.append(("Thumb wheel left", true))
        }
        thumbPulseUntil = now.addingTimeInterval(0.18)
    }

    private static func scrollAxis(
        _ event: CGEvent,
        line: CGEventField,
        point: CGEventField,
        fixed: CGEventField
    ) -> Double {
        let lineDelta = event.getDoubleValueField(line)
        let pointDelta = Double(event.getIntegerValueField(point))
        let fixedDelta = event.getDoubleValueField(fixed)
        return [lineDelta, pointDelta, fixedDelta].max(by: { abs($0) < abs($1) }) ?? 0
    }

    private func handleDivertedButtons(_ payload: Data) {
        var next = Set<UInt16>()
        var offset = 0
        while offset + 1 < payload.count {
            let cid = Self.be16(payload, offset)
            if cid != 0 { next.insert(cid) }
            offset += 2
            if next.count >= 4 { break }
        }
        confirmedReportingCIDs.formUnion(next.intersection(ownedReportingCIDs))
        let previous = pressed
        let removed = previous.subtracting(next)
        let added = next.subtracting(previous)
        pressed = next
        for cid in next where button(for: cid) == nil && extraCIDs[cid] == nil {
            extraCIDs[cid] = String(format: "CID %04X", cid)
        }
        applyPressed(next)

        for cid in added {
            guard let button = button(for: cid), isGestureOwner(button) else { continue }
            if Self.primaryClickCIDs.contains(cid) { continue }
            addHoldSource(button, "hidpp")
        }
        for cid in removed {
            guard let button = button(for: cid) else { continue }
            if Self.primaryClickCIDs.contains(cid) { continue }
            removeHoldSource(button, "hidpp")
        }
    }

    private func applyPressed(_ next: Set<UInt16>) {
        let extras = extraCIDs.keys.sorted().compactMap { cid -> MXMasterControl? in
            if knownButton(for: cid) != nil { return nil }
            return MXMasterControl(
                id: cid,
                title: extraCIDs[cid] ?? String(format: "CID %04X", cid),
                down: next.contains(cid)
            )
        }
        var dynamicButtons: [DeviceButton: Bool] = [:]
        for (cid, button) in dynamicButtonByCID {
            dynamicButtons[button] = next.contains(cid)
        }
        var capturedButtonStates: [DeviceButton: Bool] = [:]
        let confirmedControls = controls.filter { confirmedReportingCIDs.contains($0.cid) }
        for button in Set(confirmedControls.compactMap({ button(for: $0.cid) })) {
            capturedButtonStates[button] = cids(for: button).contains(where: next.contains)
        }
        let isConfirmed = { (button: DeviceButton) in
            self.cids(for: button).contains(where: self.confirmedReportingCIDs.contains)
        }
        lock.lock()
        if isConfirmed(.mxBack) {
            snapshot.back = next.contains(0x0053)
        }
        if isConfirmed(.mxForward) {
            snapshot.forward = next.contains(0x0056) || next.contains(0x0054)
        }
        if isConfirmed(.mxSmartShift) {
            snapshot.smartShift = next.contains(0x00C4)
        }
        if isConfirmed(.mxModeShift) {
            snapshot.modeShift = next.contains(0x00D0)
                || next.contains(0x00ED)
                || next.contains(0x00FD)
        }
        snapshot.side = next.contains(0x00C3)
        let hidppHaptic = next.contains(0x01A0)
            || (isHapticPanel && next.contains(model.gestureCID))
        let holding = activeGestureCID != nil
        snapshot.haptic = hidppHaptic || lastHapticBit
        snapshot.extras = extras
        snapshot.dynamicButtons = dynamicButtons
        snapshot.capturedButtonStates = capturedButtonStates
        snapshot.gestureDown = snapshot.haptic
            || next.contains(where: { self.gestureCIDs.contains($0) })
            || holding
        lock.unlock()

        var logged = [
            ("Back", next.contains(0x0053)),
            ("Forward", next.contains(0x0056) || next.contains(0x0054)),
            ("Mode shift", next.contains(0x00C4)),
            ("DPI", next.contains(0x00D0) || next.contains(0x00ED) || next.contains(0x00FD)),
            ("Gesture button", next.contains(0x00C3)),
            ("Haptic button", next.contains(model.gestureCID) || next.contains(0x01A0)),
            ("Gesture hold", next.contains(where: { gestureCIDs.contains($0) }))
        ]
        logged.append(contentsOf: extras.map { ($0.title, $0.down) })
        noteButtons(logged)
    }

    private func handleForceSensing(_ payload: Data) {
        noteLastEvent("force \(Self.hex(payload))")
        let pressed = payload.contains { $0 != 0 }
        var next = self.pressed
        if pressed {
            next.insert(model.gestureCID)
        } else {
            next.remove(model.gestureCID)
        }
        if next != self.pressed {
            var reconstructed = Data()
            for cid in next {
                reconstructed.append(UInt8(cid >> 8))
                reconstructed.append(UInt8(cid & 0xFF))
            }
            handleDivertedButtons(reconstructed)
        }
    }

    private func handleRawXY(_ payload: Data) {
        guard payload.count >= 4 else { return }
        if ignoreNextRawXY {
            ignoreNextRawXY = false
            noteLastEvent("raw XY (ignored first sample)")
            return
        }
        let dx = Int16(bitPattern: Self.be16(payload, 0))
        let dy = Int16(bitPattern: Self.be16(payload, 2))
        usingRawXY = true
        lastFirmwareXYAt = Date()
        addGestureHID(dx: Double(dx), dy: Double(dy))
        lock.lock()
        snapshot.gestureDX = gestureDelta.width
        snapshot.gestureDY = gestureDelta.height
        if !snapshot.gestureDown {
            snapshot.gestureDown = true
            if snapshot.liveGestureOwner == .mxSide || pressed.contains(0x00C3) {
                snapshot.side = true
            } else if isHapticPanel {
                snapshot.haptic = true
            } else {
                snapshot.side = true
            }
        }
        lock.unlock()
    }

    private func handleAnalytics(_ payload: Data) {
        var offset = 0
        var next = pressed
        var sawHaptic = false
        while offset + 2 < payload.count {
            let cid = Self.be16(payload, offset)
            let event = payload[offset + 2]
            offset += 3
            guard cid != 0 else { continue }
            sawHaptic = sawHaptic || cid == hapticCID || gestureCIDs.contains(cid)
            if event == 0 {
                next.remove(cid)
            } else {
                next.insert(cid)
            }
        }
        noteLastEvent(sawHaptic ? "analytics haptic \(Self.hex(payload))" : "analytics \(Self.hex(payload))")
        if next != pressed {
            var reconstructed = Data()
            for cid in next {
                reconstructed.append(UInt8(cid >> 8))
                reconstructed.append(UInt8(cid & 0xFF))
            }
            handleDivertedButtons(reconstructed)
        }
    }

    private func finishGesture(released: UInt16) {
        let delta = LogitechGestureMotion.liveDelta(
            hid: gestureDelta,
            pointer: pointerDelta
        )
        let held = hapticDownAt.map { Date().timeIntervalSince($0) } ?? 0
        hapticDownAt = nil
        let moved = held >= 0.10 && hypot(delta.width, delta.height) >= Self.pointerSwipeDistance
        let slot: DeviceButton
        if moved {
            slot = Self.classify(delta: delta, tapLimit: 0)
        } else {
            slot = .mxGesture
        }
        lock.lock()
        snapshot.pendingGesture = slot
        snapshot.pendingGestureOwner = button(for: released) ?? snapshot.liveGestureOwner ?? .mxHaptic
        snapshot.liveGestureOwner = nil
        snapshot.lastGesture = slot
        snapshot.liveGesture = nil
        snapshot.gestureDown = false
        snapshot.gestureHeld = false
        snapshot.haptic = false
        snapshot.gestureDX = 0
        snapshot.gestureDY = 0
        lastGestureAt = Date()
        lock.unlock()
        unfreezeCursor()
        unlockCursor()
        logEvent(slot.title, pressed: true)
        gestureDelta = .zero
        pointerDelta = .zero
        pointerOrigin = .zero
        usingRawXY = false
        lastFirmwareXYAt = .distantPast
    }

    private func handleMouseValue(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let device = IOHIDElementGetDevice(element)
        let vendor = (IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int) ?? 0
        guard vendor == DeviceSupport.logitechVendorID else { return }
        guard matchesCurrentDirectMouse(device) else { return }
        lock.lock()
        let connected = snapshot.connected
        lock.unlock()
        guard connected else { return }

        let page = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let integer = IOHIDValueGetIntegerValue(value)
        let now = Date()

        var logged: [(String, Bool)] = []
        lock.lock()
        switch (page, usage) {
        case (0x09, 1):
            snapshot.left = integer != 0
        case (0x09, 2):
            snapshot.right = integer != 0
        case (0x09, 3):
            snapshot.middle = integer != 0
        case (0x09, 4):
            if !ready { snapshot.back = integer != 0 }
        case (0x09, 5):
            if !ready { snapshot.forward = integer != 0 }
        case (0x09, 6):
            snapshot.smartShift = integer != 0
        case (0x09, 7):
            if model.nativeHapticButtonBit != nil {
                snapshot.haptic = integer != 0 || lastHapticBit
                snapshot.gestureDown = snapshot.haptic || snapshot.gestureDown || activeGestureCID != nil
            }
        case (0x09, 8):
            snapshot.side = integer != 0
        case (0x01, 0x30):
            if activeGestureCID != nil, snapshot.liveGestureOwner == .mxHaptic, integer != 0 {
                usingRawXY = true
                addGestureHID(dx: Double(integer), dy: 0)
                snapshot.gestureDX = gestureDelta.width
            }
        case (0x01, 0x31):
            if activeGestureCID != nil, snapshot.liveGestureOwner == .mxHaptic, integer != 0 {
                usingRawXY = true
                addGestureHID(dx: 0, dy: Double(integer))
                snapshot.gestureDY = gestureDelta.height
            }
        case (0x01, 0x38):
            if integer > 0 {
                snapshot.wheelDown = true
                snapshot.wheelUp = false
                wheelPulseUntil = now.addingTimeInterval(0.18)
            } else if integer < 0 {
                snapshot.wheelUp = true
                snapshot.wheelDown = false
                wheelPulseUntil = now.addingTimeInterval(0.18)
            }
        case (0x0C, 0x238):
            if !thumbComesFromHIDPP {
                if integer > 0 {
                    snapshot.thumbRight = true
                    snapshot.thumbLeft = false
                    thumbPulseUntil = now.addingTimeInterval(0.18)
                } else if integer < 0 {
                    snapshot.thumbLeft = true
                    snapshot.thumbRight = false
                    thumbPulseUntil = now.addingTimeInterval(0.18)
                }
            }
        default:
            lock.unlock()
            return
        }
        logged = [
            ("Left", snapshot.left),
            ("Right", snapshot.right),
            ("Middle", snapshot.middle),
            ("Wheel up", snapshot.wheelUp && now < wheelPulseUntil),
            ("Wheel down", snapshot.wheelDown && now < wheelPulseUntil),
            ("Thumb wheel left", snapshot.thumbLeft && now < thumbPulseUntil),
            ("Thumb wheel right", snapshot.thumbRight && now < thumbPulseUntil),
            ("Mode shift", snapshot.smartShift),
            ("Gesture button", snapshot.side),
            ("Haptic button", snapshot.haptic)
        ]
        lock.unlock()
        noteButtons(logged)
        if page == 0x09, usage == 7, model.nativeHapticButtonBit != nil {
            applyHapticEdge(down: integer != 0)
        }
    }

    private func matchesCurrentDirectMouse(_ device: IOHIDDevice) -> Bool {
        guard boltLink == nil, let hidppDevice else { return false }
        if CFEqual(device, hidppDevice) { return true }
        let productID = (IOHIDDeviceGetProperty(
            device,
            kIOHIDProductIDKey as CFString
        ) as? NSNumber)?.intValue
        let currentProductID = (IOHIDDeviceGetProperty(
            hidppDevice,
            kIOHIDProductIDKey as CFString
        ) as? NSNumber)?.intValue
        guard productID != nil, productID == currentProductID else { return false }
        let address = DeviceIdentity.fromHID(device)
        let currentAddress = DeviceIdentity.fromHID(hidppDevice)
        return DeviceIdentity.isConcrete(address)
            && DeviceIdentity.isConcrete(currentAddress)
            && DeviceIdentity.same(address, currentAddress)
    }

    private func noteButtons(_ buttons: [(String, Bool)]) {
        lock.lock()
        let previous = previousButtons
        var events = snapshot.events
        for (label, pressed) in buttons {
            if previous[label] != pressed {
                events.insert(InputLogEvent(id: UUID(), date: Date(), label: label, pressed: pressed), at: 0)
            }
            previousButtons[label] = pressed
        }
        if events.count > 40 {
            events = Array(events.prefix(40))
        }
        snapshot.events = events
        lock.unlock()
    }

    private func logEvent(_ label: String, pressed: Bool) {
        lock.lock()
        snapshot.events.insert(InputLogEvent(id: UUID(), date: Date(), label: label, pressed: pressed), at: 0)
        if snapshot.events.count > 40 {
            snapshot.events = Array(snapshot.events.prefix(40))
        }
        lock.unlock()
    }

    private func setStatus(_ status: String) {
        lock.lock()
        snapshot.status = status
        lock.unlock()
    }

    private func noteLastEvent(_ text: String) {
        lock.lock()
        snapshot.lastHIDEvent = text
        lock.unlock()
    }

    private static let hapticSwipeDistance: CGFloat = 240
    private static let pointerSwipeDistance: CGFloat = 70

    private func addGestureHID(dx: Double, dy: Double) {
        let dpi = MappingProfile.nearestDPI(desiredDPI, in: dpiValues)
        let factor = MappingProfile.gestureSpeedFactor(dpi: dpi)
        gestureDelta.width += CGFloat(dx * factor)
        gestureDelta.height += CGFloat(dy * factor)
    }

    private static func classify(delta: CGSize, tapLimit: CGFloat) -> DeviceButton {
        let dx = delta.width
        let dy = delta.height
        if hypot(dx, dy) < tapLimit {
            return .mxGesture
        }
        if abs(dy) >= abs(dx) {
            return dy < 0 ? .mxGestureUp : .mxGestureDown
        }
        return dx < 0 ? .mxGestureLeft : .mxGestureRight
    }

    private func button(for cid: UInt16) -> DeviceButton? {
        dynamicButtonByCID[cid] ?? knownButton(for: cid)
    }

    private func knownButton(for cid: UInt16) -> DeviceButton? {
        if cid == 0x00C3 { return .mxSide }
        if cid == model.gestureCID { return .mxHaptic }
        if cid == 0x01A0 { return .mxHaptic }
        switch cid {
        case 0x0050: return .mxLeft
        case 0x0051: return .mxRight
        case 0x0052: return .mxMiddle
        case 0x0053: return .mxBack
        case 0x0054, 0x0056: return .mxForward
        case 0x00C4: return .mxSmartShift
        case 0x00D0, 0x00ED, 0x00FD: return .mxModeShift
        case 0x00D6, 0x00D7: return .mxGesture
        default: return nil
        }
    }

    private func title(for cid: UInt16, task _: UInt16) -> String {
        if cid == 0x00C3 { return DeviceButton.mxSide.title }
        if cid == 0x01A0 || cid == model.gestureCID { return DeviceButton.mxHaptic.title }
        if let button = button(for: cid) { return button.title }
        switch cid {
        case 0x00D4: return "Thumb wheel"
        default: return String(format: "Button %04X", cid)
        }
    }

    private static let gestureReportingFlags: UInt8 = 0x33
    private static let buttonReportingFlags: UInt8 = 0x03
    private static let clearReportingFlags: UInt8 = 0x22
    private static let analyticsReportingFlags: UInt8 = 0x03

    private static func hex(_ data: Data) -> String {
        data.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private func reportingFlags(for control: LogitechHIDPPControlDescriptor) -> UInt8 {
        if control.cid == model.gestureCID {
            return Self.gestureReportingFlags
        }
        if control.cid == 0x00C3 {
            return gestureOwnerButtons.contains(.mxSide)
                ? Self.gestureReportingFlags
                : Self.buttonReportingFlags
        }
        if gestureOwnerButtons.contains(button(for: control.cid) ?? .mxSide),
           control.supportsRawXY || Self.knownGestureCIDs.contains(control.cid) {
            return Self.gestureReportingFlags
        }
        return Self.buttonReportingFlags
    }

    private static func be16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
    }

    private static func signExtend12(_ raw: Int) -> Int {
        let value = raw & 0xFFF
        return value >= 0x800 ? value - 0x1000 : value
    }

    private func cids(for button: DeviceButton) -> [UInt16] {
        let dynamic = dynamicButtonByCID.compactMap { cid, mapped in
            mapped == button ? cid : nil
        }
        if !dynamic.isEmpty {
            return dynamic.sorted()
        }
        switch button {
        case .mxLeft: return [0x0050]
        case .mxRight: return [0x0051]
        case .mxMiddle: return [0x0052]
        case .mxBack: return [0x0053]
        case .mxForward: return [0x0054, 0x0056]
        case .mxSmartShift: return [0x00C4]
        case .mxModeShift: return [0x00D0, 0x00ED, 0x00FD]
        case .mxSide: return [0x00C3]
        case .mxHaptic: return isHapticPanel ? [model.gestureCID] : []
        default: return []
        }
    }

    private static let knownGestureCIDs: Set<UInt16> = [0x01A0, 0x00C3, 0x00D6, 0x00D7]
    private static let primaryClickCIDs: Set<UInt16> = [0x0050, 0x0051]
    private static let nativeClickCIDs: Set<UInt16> = [0x0050, 0x0051, 0x0052]
    private static let wheelCIDs: Set<UInt16> = [0x00D4, 0x00D7]
}

/// One session tap for every MX reader. A second `CGEvent.tapCreate` often
/// fails, so MX4 used to miss left/right/wheel while 3S still lit up.
private enum MXClickProbe {
    private static let lock = NSLock()
    private static var readers: [ObjectIdentifier: LogitechMouseReader] = [:]
    private static var tap: CFMachPort?
    private static var source: CFRunLoopSource?
    private static var scrollTap: CFMachPort?
    private static var scrollSource: CFRunLoopSource?

    static let callback: CGEventTapCallBack = { _, type, event, _ in
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            MXClickProbe.lock.lock()
            if let tap = MXClickProbe.tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            if let scrollTap = MXClickProbe.scrollTap {
                CGEvent.tapEnable(tap: scrollTap, enable: true)
            }
            MXClickProbe.lock.unlock()
            return Unmanaged.passUnretained(event)
        }
        MXClickProbe.lock.lock()
        let readers = Array(MXClickProbe.readers.values)
        MXClickProbe.lock.unlock()
        var swallow = false
        for reader in readers {
            reader.handleClickEvent(type: type, event: event)
            if reader.shouldSwallowPointerEvent(type, event: event) {
                swallow = true
            }
        }
        if swallow { return nil }
        return Unmanaged.passUnretained(event)
    }

    static func add(_ reader: LogitechMouseReader) {
        lock.lock()
        readers[ObjectIdentifier(reader)] = reader
        let needsTap = tap == nil
        lock.unlock()
        guard needsTap else { return }
        let mask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseUp.rawValue)
            | CGEventMask(1 << CGEventType.rightMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.rightMouseUp.rawValue)
            | CGEventMask(1 << CGEventType.otherMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.otherMouseUp.rawValue)
            | CGEventMask(1 << CGEventType.mouseMoved.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseDragged.rawValue)
            | CGEventMask(1 << CGEventType.rightMouseDragged.rawValue)
            | CGEventMask(1 << CGEventType.otherMouseDragged.rawValue)
        guard let created = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: nil
        ) else { return }
        let loopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), loopSource, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)
        let scrollMask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        let createdScroll = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: scrollMask,
            callback: callback,
            userInfo: nil
        )
        var scrollLoop: CFRunLoopSource?
        if let createdScroll {
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, createdScroll, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: createdScroll, enable: true)
            scrollLoop = source
        }
        lock.lock()
        tap = created
        source = loopSource
        scrollTap = createdScroll
        scrollSource = scrollLoop
        lock.unlock()
    }

    static func remove(_ reader: LogitechMouseReader) {
        lock.lock()
        readers.removeValue(forKey: ObjectIdentifier(reader))
        let empty = readers.isEmpty
        let doomedTap = empty ? tap : nil
        let doomedSource = empty ? source : nil
        let doomedScrollTap = empty ? scrollTap : nil
        let doomedScrollSource = empty ? scrollSource : nil
        if empty {
            tap = nil
            source = nil
            scrollTap = nil
            scrollSource = nil
        }
        lock.unlock()
        if let doomedSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), doomedSource, .commonModes)
        }
        if let doomedTap {
            CFMachPortInvalidate(doomedTap)
        }
        if let doomedScrollSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), doomedScrollSource, .commonModes)
        }
        if let doomedScrollTap {
            CFMachPortInvalidate(doomedScrollTap)
        }
    }
}
