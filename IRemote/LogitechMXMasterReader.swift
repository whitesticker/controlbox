import CoreGraphics
import Foundation
import IRemoteControl
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
    var availableDPI: [Int] = []
    var appliedDPI = 0
    var smoothScrolling = true
    var extras: [MXMasterControl] = []
    var events: [InputLogEvent] = []
    var lastHIDEvent = "—"
}

final class LogitechMXMasterReader {
    private let model: MXMasterHIDModel

    init(model: MXMasterHIDModel) {
        self.model = model
        snapshot.kind = model.kind
        snapshot.name = model.kind.title
        snapshot.product = model.kind.title
        snapshot.status = model.lookingStatus
        hapticCID = model.gestureCID
        gestureCID = model.gestureCID
        gestureCIDs = [model.gestureCID]
    }

    private struct Pending {
        let swID: UInt8
        let completion: (Data?) -> Void
    }

    private struct ControlInfo {
        var cid: UInt16
        var task: UInt16
        var divertable: Bool
        var rawXY: Bool
        var forceRawXY: Bool
    }

    private struct DivertJob {
        var cid: UInt16
        var flags: UInt8
        var remap: UInt16
        var highFlags: UInt8
    }

    private var hidppManager: IOHIDManager?
    private var mouseManager: IOHIDManager?
    private var clickTap: CFMachPort?
    private var clickSource: CFRunLoopSource?
    private var hidppDevice: IOHIDDevice?
    private var queuedHIDPP: [IOHIDDevice] = []
    private let lock = NSLock()
    private var snapshot = MXMasterSnapshot()
    private var pending: Pending?
    private var swCounter: UInt8 = 0x0B
    private var deviceIndex: UInt8 = 0xFF
    private var reprogIndex: UInt8?
    private var nameIndex: UInt8?
    private var gestureCID: UInt16 = 0x01A0
    private var hapticCID: UInt16 = 0x01A0
    private var gestureCIDs: Set<UInt16> = [0x01A0]
    private var gestureOwnerButtons: Set<DeviceButton> = [.mxHaptic]
    private var holdSources: [DeviceButton: Set<String>] = [:]
    private var activeGestureCID: UInt16?
    private var lastHapticBit = false
    private var ignoreNextRawXY = false
    private var pressed = Set<UInt16>()
    private var running = false
    private var recoverAttempts = 0
    private var recoverWork: DispatchWorkItem?
    private var hapticReleaseWork: DispatchWorkItem?
    private var hapticDownAt: Date?
    private var controls: [ControlInfo] = []
    private var extraCIDs: [UInt16: String] = [:]
    private var gestureOrigin = CGPoint.zero
    private var gestureDelta = CGSize.zero
    private var pointerOrigin = CGPoint.zero
    private var pointerDelta = CGSize.zero
    private var usingRawXY = false
    private var cursorLocked = false
    private var cursorFrozen = false
    private var ready = false
    private var previousButtons: [String: Bool] = [:]
    private var wheelPulseUntil = Date.distantPast
    private var thumbPulseUntil = Date.distantPast
    private var lastGestureAt = Date.distantPast
    private var hidppBuffers: [ObjectIdentifier: UnsafeMutablePointer<UInt8>] = [:]
    private var hiresWheelIndex: UInt8?
    private var thumbWheelIndex: UInt8?
    private var forceSensingIndex: UInt8?
    private var pointerScaleIndex: UInt8?
    private var dpiIndex: UInt8?
    private var dpiValues: [Int] = []
    private var lastSentDPI = -1
    private var lastSentPointerScale = -1
    private var lastAppliedOSDPI = -1
    private var lastAppliedOSPointerSpeed = -1.0
    private var desiredDPI = MappingProfile.defaultSensorDPI
    private var desiredPointerSpeed = 0.5
    private var desiredHapticGestureSpeed = 0.5
    private var desiredSmoothScrolling = true
    private var lastWheelConfig: (divert: Bool, invert: Bool, highRes: Bool)?
    private var consecutiveTimeouts = 0
    private var hidppEpoch = 0
    private var hidppQueue: [(featureIndex: UInt8, function: UInt8, params: [UInt8], completion: (Data?) -> Void)] = []
    var naturalScrolling = true
    var injectEnabled = false
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
            let live = Self.liveDelta(hid: gestureDelta, pointer: pointerDelta)
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
        holdSources.removeAll()
        hidppEpoch += 1
        unfreezeCursor()
        unlockCursor()
        restoreNativeReporting()
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
        if let clickSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), clickSource, .commonModes)
        }
        if let clickTap {
            CFMachPortInvalidate(clickTap)
        }
        clickSource = nil
        clickTap = nil
        hidppManager = nil
        mouseManager = nil
        hidppDevice = nil
        queuedHIDPP.removeAll()
        ready = false
        pending = nil
        hiresWheelIndex = nil
        thumbWheelIndex = nil
        forceSensingIndex = nil
        pointerScaleIndex = nil
        dpiIndex = nil
        dpiValues = []
        lastSentDPI = -1
        lastSentPointerScale = -1
        lastAppliedOSDPI = -1
        lastAppliedOSPointerSpeed = -1.0
        lastWheelConfig = nil
        consecutiveTimeouts = 0
        hidppQueue.removeAll()
        desiredDPI = MappingProfile.defaultSensorDPI
        desiredPointerSpeed = 0.5
        desiredHapticGestureSpeed = 0.5
        lastHapticBit = false
        desiredSmoothScrolling = true
        naturalScrolling = true
        injectEnabled = false
        wheelsEnabled = false
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
        let owners = buttons.intersection([.mxHaptic])
        gestureOwnerButtons = owners
        var cids = Set(owners.flatMap { self.cids(for: $0) })
        cids.subtract(Self.nativeClickCIDs)
        guard cids != gestureCIDs else { return }
        gestureCIDs = cids
        if let haptic = cids.first(where: { $0 == hapticCID }) {
            gestureCID = haptic
        } else {
            gestureCID = cids.first ?? hapticCID
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

    func applyHapticGestureSpeed(_ speed: Double) {
        let next = min(max(speed, 0), 1)
        guard next != desiredHapticGestureSpeed else { return }
        desiredHapticGestureSpeed = next
    }

    func applySmoothScrolling(_ enabled: Bool) {
        guard desiredSmoothScrolling != enabled else { return }
        desiredSmoothScrolling = enabled
        lastWheelConfig = nil
        applyWheelRouting()
        publishMotionSettings()
    }

    private func sendSensorSettingsIfNeeded() {
        guard ready else { return }
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

    private func applyOSPointerSettingsIfNeeded() {
        guard let hidppDevice else { return }
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
        lock.unlock()
    }

    func pollGesturePointer() {
        guard activeGestureCID != nil else {
            unfreezeCursor()
            unlockCursor()
            return
        }
        pinCursor(forceWarp: false)
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
        IOHIDManagerSetDeviceMatchingMultiple(mgr, model.hidManagerMatches() as CFArray)
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(mgr, { context, _, _, device in
            guard let context else { return }
            let reader = Unmanaged<LogitechMXMasterReader>.fromOpaque(context)
            DispatchQueue.main.async {
                reader.takeUnretainedValue().attachHIDPP(device)
            }
        }, pointer)
        IOHIDManagerRegisterDeviceRemovalCallback(mgr, { context, _, _, device in
            guard let context else { return }
            let reader = Unmanaged<LogitechMXMasterReader>.fromOpaque(context)
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
            return isLikelyMXMaster(lhs) && !isLikelyMXMaster(rhs)
        }
        for device in devices where model.matches(device) {
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
            Unmanaged<LogitechMXMasterReader>.fromOpaque(context).takeUnretainedValue().handleMouseValue(value)
        }, pointer)
        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        mouseManager = mgr
    }

    private func startClickProbe() {
        guard clickTap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseUp.rawValue)
            | CGEventMask(1 << CGEventType.rightMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.rightMouseUp.rawValue)
            | CGEventMask(1 << CGEventType.otherMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.otherMouseUp.rawValue)
            | CGEventMask(1 << CGEventType.scrollWheel.rawValue)
            | CGEventMask(1 << CGEventType.mouseMoved.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseDragged.rawValue)
            | CGEventMask(1 << CGEventType.rightMouseDragged.rawValue)
            | CGEventMask(1 << CGEventType.otherMouseDragged.rawValue)
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let reader = Unmanaged<LogitechMXMasterReader>.fromOpaque(context).takeUnretainedValue()
                reader.handleClickEvent(type: type, event: event)
                if reader.shouldSwallowPointerEvent(type, event: event) {
                    return nil
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: pointer
        ) else { return }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        clickTap = tap
        clickSource = source
    }

    private func shouldSwallowPointerEvent(_ type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            return activeGestureCID != nil || cursorFrozen
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

    private func handleClickEvent(type: CGEventType, event: CGEvent) {
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
            }
        case .scrollWheel:
            let dy = event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
            let dx = event.getDoubleValueField(.scrollWheelEventDeltaAxis2)
            if dy > 0 {
                snapshot.wheelUp = true
                snapshot.wheelDown = false
                wheelPulseUntil = now.addingTimeInterval(0.18)
                logs.append(("Wheel up", true))
            } else if dy < 0 {
                snapshot.wheelDown = true
                snapshot.wheelUp = false
                wheelPulseUntil = now.addingTimeInterval(0.18)
                logs.append(("Wheel down", true))
            }
            if dx > 0 {
                snapshot.thumbRight = true
                snapshot.thumbLeft = false
                thumbPulseUntil = now.addingTimeInterval(0.18)
                logs.append(("Thumb wheel right", true))
            } else if dx < 0 {
                snapshot.thumbLeft = true
                snapshot.thumbRight = false
                thumbPulseUntil = now.addingTimeInterval(0.18)
                logs.append(("Thumb wheel left", true))
            }
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

    private func isGestureOwner(_ button: DeviceButton) -> Bool {
        gestureOwnerButtons.contains(button)
    }

    private func addHoldSource(_ owner: DeviceButton, _ source: String) {
        guard isGestureOwner(owner) else { return }
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
        if activeGestureCID != nil {
            pinCursor(forceWarp: false)
            lock.lock()
            snapshot.gestureDown = true
            snapshot.gestureHeld = true
            if owner == .mxHaptic { snapshot.haptic = true }
            lock.unlock()
            return
        }
        activeGestureCID = cids(for: owner).first ?? model.gestureCID
        usingRawXY = true
        ignoreNextRawXY = false
        hapticDownAt = Date()
        gestureDelta = .zero
        pointerDelta = .zero
        gestureOrigin = CGEvent(source: nil)?.location ?? .zero
        pointerOrigin = gestureOrigin
        pinCursor(forceWarp: true)
        lock.lock()
        snapshot.gestureDown = true
        snapshot.gestureHeld = true
        snapshot.liveGestureOwner = owner
        if owner == .mxHaptic { snapshot.haptic = true }
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
        guard model.matches(incoming) else { return }
        if isSameDevice(incoming, hidppDevice) { return }
        if queuedHIDPP.contains(where: { isSameDevice(incoming, $0) }) { return }
        if hidppDevice == nil {
            beginProbe(incoming)
            return
        }
        if isLikelyMXMaster(incoming), let current = hidppDevice, !isLikelyMXMaster(current) {
            queuedHIDPP.insert(current, at: 0)
            teardownHIDPP(current, keepQueued: true)
            beginProbe(incoming)
            return
        }
        queuedHIDPP.append(incoming)
    }

    private func isSameDevice(_ lhs: IOHIDDevice, _ rhs: IOHIDDevice?) -> Bool {
        guard let rhs else { return false }
        return CFEqual(lhs, rhs)
    }

    private func beginProbe(_ device: IOHIDDevice) {
        hidppEpoch += 1
        hidppQueue.removeAll()
        pending = nil
        reprogIndex = nil
        nameIndex = nil
        forceSensingIndex = nil
        hiresWheelIndex = nil
        thumbWheelIndex = nil
        pointerScaleIndex = nil
        dpiIndex = nil
        ready = false
        hidppDevice = device
        lastAppliedOSDPI = -1
        lastAppliedOSPointerSpeed = -1.0
        _ = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        registerHIDPPCallback(device)
        applyOSPointerSettingsIfNeeded()
        let product = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? model.kind.title
        lock.lock()
        snapshot.kind = model.resolvedKind(of: device)
        snapshot.name = product
        snapshot.product = product
        snapshot.address = DeviceIdentity.fromHID(device)
        snapshot.connected = true
        snapshot.status = "Talking to \(product) over HID++…"
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
                let reader = Unmanaged<LogitechMXMasterReader>.fromOpaque(context).takeUnretainedValue()
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

    private func teardownHIDPP(_ device: IOHIDDevice, keepQueued: Bool) {
        releaseReportBuffer(device)
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        _ = IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        if !keepQueued {
            queuedHIDPP.removeAll { isSameDevice(device, $0) }
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
        queuedHIDPP.removeAll { isSameDevice(incoming, $0) }
        if !isSameDevice(incoming, hidppDevice) {
            releaseReportBuffer(incoming)
            return
        }
        teardownHIDPP(incoming, keepQueued: false)
        unfreezeCursor()
        hidppDevice = nil
        ready = false
        pending = nil
        hidppQueue.removeAll()
        unlockCursor()
        lock.lock()
        snapshot = MXMasterSnapshot()
        snapshot.kind = model.kind
        snapshot.name = model.kind.title
        snapshot.status = "\(model.kind.title) disconnected"
        lock.unlock()
        probeNextHIDPP(failed: "MX Master disconnected")
    }

    private func notePipeDropped(_ reason: String) {
        guard running else { return }
        ready = false
        consecutiveTimeouts = 0
        hidppEpoch += 1
        hidppQueue.removeAll()
        pending = nil
        if let current = hidppDevice {
            teardownHIDPP(current, keepQueued: true)
            hidppDevice = nil
        }
        setStatus(reason)
        scheduleRecover()
    }

    private func scheduleRecover() {
        guard running, hidppManager != nil else { return }
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
        guard running, hidppManager != nil else { return }
        if hidppDevice != nil { return }
        scanHIDPP()
        if hidppDevice == nil {
            scheduleRecover()
        }
    }

    private func failHIDPPAndTryNext(_ message: String) {
        hidppQueue.removeAll()
        pending = nil
        if let current = hidppDevice {
            teardownHIDPP(current, keepQueued: false)
            hidppDevice = nil
        }
        probeNextHIDPP(failed: message)
    }

    private func probeNextHIDPP(failed message: String) {
        if let next = popBestQueued() {
            beginProbe(next)
            return
        }
        setStatus(message)
        scheduleRecover()
    }

    private func popBestQueued() -> IOHIDDevice? {
        if let index = queuedHIDPP.firstIndex(where: isLikelyMXMaster) {
            return queuedHIDPP.remove(at: index)
        }
        guard !queuedHIDPP.isEmpty else { return nil }
        return queuedHIDPP.removeFirst()
    }

    private func isLikelyMXMaster(_ device: IOHIDDevice) -> Bool {
        model.matches(device)
    }

    private func probeDeviceIndices(_ indices: [UInt8]) {
        guard let index = indices.first else {
            failHIDPPAndTryNext("No HID++ reply from the mouse. LogiPluginService can block this even after Options+ is removed.")
            return
        }
        deviceIndex = index
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
        } ?? "MX Master"
        request(featureIndex: 0, function: 0, params: [0x00, 0x05]) { [weak self] data in
            guard let self else { return }
            if let data, let nameIndex = data.first, nameIndex != 0 {
                self.nameIndex = nameIndex
            } else if DeviceSupport.isMXMasterName(fallbackName) {
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
                    self?.finishSetup(named: "MX Master")
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
                self?.finishSetup(named: assembled.isEmpty ? "MX Master" : assembled)
                return
            }
            let chunk = data.filter { $0 != 0 }
            let piece = String(bytes: chunk, encoding: .utf8) ?? ""
            self.readName(lengthIndex: lengthIndex, assembled: assembled + piece)
        }
    }

    private func finishSetup(named: String) {
        let trimmed = named.trimmingCharacters(in: .whitespacesAndNewlines)
        let isMX = DeviceSupport.isMXMasterName(trimmed)
        lock.lock()
        if let hidppDevice {
            snapshot.kind = model.resolvedKind(of: hidppDevice)
        }
        snapshot.name = trimmed.isEmpty ? snapshot.kind.title : trimmed
        snapshot.product = snapshot.name
        snapshot.connected = isMX
        snapshot.status = isMX ? "Connected" : "Logitech device is not \(snapshot.kind.title)"
        lock.unlock()
        guard isMX else {
            failHIDPPAndTryNext("Logitech device is not an MX Master")
            return
        }
        enableHiddenFeaturesThenDivert()
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
                self.sendSensorSettingsIfNeeded()
                self.applyWheelRouting()
            }
            return
        }
        if count < 0 {
            request(featureIndex: reprogIndex, function: 0, params: []) { [weak self] data in
                let total = Int(data?.first ?? 0)
                if total <= 0 {
                    self?.setStatus("No reprogrammable controls. Quit Logi Options+ and reconnect the mouse.")
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
            let info = ControlInfo(
                cid: cid,
                task: task,
                divertable: flagsLow & 0x20 != 0,
                rawXY: flagsHigh & 0x01 != 0,
                forceRawXY: flagsHigh & 0x02 != 0
            )
            self.controls.append(info)
            self.enumerateAndDivert(index: index + 1, count: count)
        }
    }

    private func chooseGestureCID() {
        hapticCID = model.gestureCID
        gestureCID = model.gestureCID
        gestureCIDs = [model.gestureCID]
        extraCIDs.removeAll()
        for control in controls {
            extraCIDs[control.cid] = title(for: control.cid, task: control.task)
                + String(format: " (%04X)", control.cid)
        }
        applyPressed(pressed)
        let listed = controls.map { String(format: "%04X", $0.cid) }.joined(separator: " ")
        let found = controls.contains(where: { $0.cid == model.gestureCID })
        noteLastEvent(found ? "CIDs \(listed)" : String(format: "no %04X in table: %@", model.gestureCID, listed))
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
        var jobs: [DivertJob] = [
            DivertJob(
                cid: model.gestureCID,
                flags: Self.gestureReportingFlags,
                remap: 0,
                highFlags: model.analyticsReportingFlags
            )
        ]
        for control in controls where control.divertable {
            if Self.nativeClickCIDs.contains(control.cid) { continue }
            if Self.wheelCIDs.contains(control.cid) { continue }
            if gestureCIDs.contains(control.cid) { continue }
            if model.extraButtonCIDs.contains(control.cid) {
                jobs.append(DivertJob(cid: control.cid, flags: Self.buttonReportingFlags, remap: 0, highFlags: 0))
                continue
            }
            if control.rawXY { continue }
            jobs.append(DivertJob(cid: control.cid, flags: Self.buttonReportingFlags, remap: 0, highFlags: 0))
        }
        divert(jobs: jobs, reprogIndex: reprogIndex) { [weak self] in
            guard let self else { return }
            self.ready = true
            self.consecutiveTimeouts = 0
            self.recoverAttempts = 0
            self.recoverWork?.cancel()
            self.recoverWork = nil
            self.confirmGestureReporting()
            self.lookupMotionFeatures {
                self.lastWheelConfig = nil
                self.lastSentDPI = -1
                self.lastSentPointerScale = -1
                self.sendSensorSettingsIfNeeded()
                self.applyWheelRouting()
            }
        }
    }

    private func confirmGestureReporting() {
        guard let reprogIndex else { return }
        request(
            featureIndex: reprogIndex,
            function: 2,
            params: [
                UInt8(model.gestureCID >> 8),
                UInt8(model.gestureCID & 0xFF)
            ]
        ) { [weak self] data in
            guard let self else { return }
            let listed = self.controls.map { String(format: "%04X", $0.cid) }.joined(separator: " ")
            let cidHex = String(format: "%04X", self.model.gestureCID)
            if let data, !data.isEmpty {
                let hex = data.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " ")
                self.noteLastEvent("\(cidHex) reporting \(hex)")
                self.setStatus("Connected. CIDs \(listed). \(cidHex) \(hex)")
            } else {
                self.noteLastEvent("\(cidHex) reporting missing")
                self.setStatus("Connected. CIDs \(listed). \(cidHex) reporting missing")
            }
        }
    }

    private func divert(jobs: [DivertJob], reprogIndex: UInt8, completion: @escaping () -> Void) {
        guard let job = jobs.first else {
            completion()
            return
        }
        var params: [UInt8] = [
            UInt8(job.cid >> 8), UInt8(job.cid & 0xFF),
            job.flags,
            UInt8(job.remap >> 8), UInt8(job.remap & 0xFF)
        ]
        if job.highFlags != 0 {
            params.append(job.highFlags)
        }
        request(featureIndex: reprogIndex, function: 3, params: params) { [weak self] _ in
            self?.divert(jobs: Array(jobs.dropFirst()), reprogIndex: reprogIndex, completion: completion)
        }
    }

    private func lookupFeature(_ id: UInt16, completion: @escaping (UInt8?) -> Void) {
        request(featureIndex: 0, function: 0, params: [UInt8(id >> 8), UInt8(id & 0xFF)]) { data in
            guard let data, data.count >= 1 else {
                completion(nil)
                return
            }
            completion(data[0] == 0 && id != 0 ? nil : data[0])
        }
    }

    private func lookupMotionFeatures(completion: @escaping () -> Void) {
        lookupFeature(0x0001) { [weak self] featureSet in
            guard let self else { return }
            if let featureSet {
                self.request(featureIndex: featureSet, function: 0, params: []) { [weak self] data in
                    let count = Int(data?.first ?? 0) + 1
                    self?.readFeatureSlots(setIndex: featureSet, slot: 0, count: min(count, 48), then: completion)
                }
            } else {
                self.lookupMotionFeaturesByID(then: completion)
            }
        }
    }

    private func readFeatureSlots(setIndex: UInt8, slot: Int, count: Int, then completion: @escaping () -> Void) {
        if slot >= count {
            lookupMotionFeaturesByID(then: completion)
            return
        }
        request(featureIndex: setIndex, function: 1, params: [UInt8(slot)]) { [weak self] data in
            guard let self else { return }
            if let data, data.count >= 2 {
                let id = Self.be16(data, 0)
                let index = UInt8(slot)
                switch id {
                case 0x2121: self.hiresWheelIndex = index
                case 0x2150: self.thumbWheelIndex = index
                case 0x2205: self.pointerScaleIndex = index
                case 0x2201: self.dpiIndex = index
                default: break
                }
            }
            self.readFeatureSlots(setIndex: setIndex, slot: slot + 1, count: count, then: completion)
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
                        self.readDPIList(then: completion)
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

    private func applyWheelRouting() {
        guard ready else { return }
        guard hiresWheelIndex != nil || thumbWheelIndex != nil else { return }
        // Leave the main wheel on native HID so a CGEvent tap can reverse and
        // scale it. Only the thumb wheel stays on HID++ (it often has no HID axis).
        // High-res bit is Logitech “smooth scrolling”: many small steps per notch.
        let divertThumb = wheelsEnabled
        let highRes = desiredSmoothScrolling
        if lastWheelConfig?.divert == divertThumb,
           lastWheelConfig?.invert == false,
           lastWheelConfig?.highRes == highRes {
            return
        }
        lastWheelConfig = (divertThumb, false, highRes)
        if let hiresWheelIndex {
            let flags: UInt8 = highRes ? 0b0000_0010 : 0
            request(featureIndex: hiresWheelIndex, function: 2, params: [flags]) { [weak self] _ in
                self?.applyThumbRouting(divert: divertThumb, invert: false)
            }
            publishMotionSettings()
            return
        }
        applyThumbRouting(divert: divertThumb, invert: false)
        publishMotionSettings()
    }

    private func applyThumbRouting(divert: Bool, invert: Bool) {
        guard let thumbWheelIndex else { return }
        request(featureIndex: thumbWheelIndex, function: 2, params: [divert ? 1 : 0, invert ? 1 : 0]) { _ in }
    }

    private func restoreNativeReporting() {
        guard hidppDevice != nil else { return }
        hidppQueue.removeAll()
        pending = nil
        var cids = Set(controls.map(\.cid))
        cids.formUnion(gestureCIDs)
        cids.insert(model.gestureCID)
        if let reprogIndex {
            for cid in cids {
                sendHIDPP(featureIndex: reprogIndex, function: 3, params: [
                    UInt8(cid >> 8), UInt8(cid & 0xFF), Self.clearReportingFlags, 0, 0
                ])
            }
        }
        if let thumbWheelIndex {
            sendHIDPP(featureIndex: thumbWheelIndex, function: 2, params: [0, 0])
        }
    }

    private func sendHIDPP(featureIndex: UInt8, function: UInt8, params: [UInt8]) {
        guard let hidppDevice else { return }
        swCounter = swCounter == 0x0F ? 0x08 : swCounter + 1
        let swID = swCounter
        var report = [UInt8](repeating: 0, count: 20)
        report[0] = 0x11
        report[1] = deviceIndex
        report[2] = featureIndex
        report[3] = (function << 4) | (swID & 0x0F)
        for (offset, byte) in params.prefix(16).enumerated() {
            report[4 + offset] = byte
        }
        _ = report.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return kIOReturnError }
            return IOHIDDeviceSetReport(hidppDevice, kIOHIDReportTypeOutput, CFIndex(0x11), base, 20)
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

    private func request(featureIndex: UInt8, function: UInt8, params: [UInt8], completion: @escaping (Data?) -> Void) {
        hidppQueue.append((featureIndex, function, params, completion))
        pumpHIDPP()
    }

    private func pumpHIDPP() {
        guard pending == nil, let hidppDevice, let call = hidppQueue.first else { return }
        swCounter = swCounter == 0x0F ? 0x08 : swCounter + 1
        let swID = swCounter
        pending = Pending(swID: swID, completion: { [weak self] data in
            guard let self else { return }
            if !self.hidppQueue.isEmpty {
                self.hidppQueue.removeFirst()
            }
            call.completion(data)
            self.pumpHIDPP()
        })
        var report = [UInt8](repeating: 0, count: 20)
        report[0] = 0x11
        report[1] = deviceIndex
        report[2] = call.featureIndex
        report[3] = (call.function << 4) | (swID & 0x0F)
        for (offset, byte) in call.params.prefix(16).enumerated() {
            report[4 + offset] = byte
        }
        let kr = report.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return kIOReturnError }
            return IOHIDDeviceSetReport(hidppDevice, kIOHIDReportTypeOutput, CFIndex(0x11), base, 20)
        }
        if model.tryShortHIDPPReport, call.params.count <= 3 {
            var short = [UInt8](repeating: 0, count: 7)
            short[0] = 0x10
            short[1] = deviceIndex
            short[2] = call.featureIndex
            short[3] = (call.function << 4) | (swID & 0x0F)
            for (offset, byte) in call.params.prefix(3).enumerated() {
                short[4 + offset] = byte
            }
            _ = short.withUnsafeBufferPointer { buffer in
                guard let base = buffer.baseAddress else { return kIOReturnError }
                return IOHIDDeviceSetReport(hidppDevice, kIOHIDReportTypeOutput, CFIndex(0x10), base, 7)
            }
        }
        if model.tryShortHIDPPReport, kr != kIOReturnSuccess {
            _ = report.withUnsafeBufferPointer { buffer in
                guard let base = buffer.baseAddress else { return kIOReturnError }
                return IOHIDDeviceSetReport(hidppDevice, kIOHIDReportTypeOutput, 0, base, 20)
            }
        }
        let epoch = hidppEpoch
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self,
                  self.hidppEpoch == epoch,
                  let pending = self.pending,
                  pending.swID == swID
            else { return }
            self.pending = nil
            pending.completion(nil)
            guard self.ready else { return }
            self.consecutiveTimeouts += 1
            if self.consecutiveTimeouts >= 3 {
                self.notePipeDropped("HID++ timed out. Retrying…")
            }
        }
    }

    private func handleReport(_ report: [UInt8]) {
        guard report.first != 0x02 else { return }
        guard report.count >= 4 else { return }
        var bytes = report
        if bytes[0] != 0x10 && bytes[0] != 0x11 && bytes.count >= 3 {
            bytes.insert(0x11, at: 0)
        }
        guard bytes.count >= 4 else { return }
        if bytes[2] == 0x8F {
            let wasReady = ready
            if let pending {
                self.pending = nil
                pending.completion(nil)
            }
            if wasReady {
                notePipeDropped("HID++ error. Retrying…")
            }
            return
        }
        let featureIndex = bytes[2]
        let function = bytes.count > 3 ? bytes[3] >> 4 : 0
        let swID = bytes.count > 3 ? bytes[3] & 0x0F : 0
        let payload = Data(bytes.dropFirst(4))

        if swID != 0, let pending, pending.swID == swID {
            self.pending = nil
            self.consecutiveTimeouts = 0
            pending.completion(payload)
            return
        }
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
        noteLastEvent(String(format: "HID++ feat %02X fn%d %@", featureIndex, function, Self.hex(payload)))
    }

    private func handleNativeMouseReport(_ report: UnsafePointer<UInt8>, length: Int) {
        guard length >= 2 else { return }
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
        guard activeGestureCID != nil, length >= xyOffset + 3 else { return }
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

    private func handleDivertedButtons(_ payload: Data) {
        var next = Set<UInt16>()
        var offset = 0
        while offset + 1 < payload.count {
            let cid = Self.be16(payload, offset)
            if cid != 0 { next.insert(cid) }
            offset += 2
            if next.count >= 4 { break }
        }
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
            if Self.nativeClickCIDs.contains(cid) { continue }
            addHoldSource(button, "hidpp")
        }
        for cid in removed {
            guard let button = button(for: cid) else { continue }
            if Self.nativeClickCIDs.contains(cid) { continue }
            removeHoldSource(button, "hidpp")
        }
    }

    private func applyPressed(_ next: Set<UInt16>) {
        let extras = extraCIDs.keys.sorted().map { cid in
            MXMasterControl(id: cid, title: extraCIDs[cid] ?? String(format: "CID %04X", cid), down: next.contains(cid))
        }
        lock.lock()
        snapshot.back = next.contains(0x0053)
        snapshot.forward = next.contains(0x0056) || next.contains(0x0054)
        snapshot.smartShift = next.contains(0x00C4)
        snapshot.modeShift = next.contains(0x00D0) || next.contains(0x00ED) || next.contains(0x00FD)
        let hidppHaptic = next.contains(model.gestureCID)
        let holding = activeGestureCID != nil
        snapshot.haptic = hidppHaptic || lastHapticBit
        snapshot.extras = extras
        snapshot.gestureDown = snapshot.haptic
            || next.contains(where: { self.gestureCIDs.contains($0) })
            || holding
        lock.unlock()

        var logged = [
            ("Back", next.contains(0x0053)),
            ("Forward", next.contains(0x0056) || next.contains(0x0054)),
            ("Mode shift", next.contains(0x00C4)),
            ("DPI", next.contains(0x00D0) || next.contains(0x00ED) || next.contains(0x00FD)),
            (model.gestureControlTitle, next.contains(model.gestureCID)),
            ("Gesture", next.contains(where: { gestureCIDs.contains($0) }))
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
        addGestureHID(dx: Double(dx), dy: Double(dy))
        lock.lock()
        snapshot.gestureDX = gestureDelta.width
        snapshot.gestureDY = gestureDelta.height
        if !snapshot.gestureDown {
            snapshot.gestureDown = true
            snapshot.haptic = true
        }
        lock.unlock()
        noteLastEvent(String(format: "raw XY %+d,%+d", dx, dy))
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
        let delta = Self.liveDelta(hid: gestureDelta, pointer: pointerDelta)
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
    }

    private func handleMouseValue(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let device = IOHIDElementGetDevice(element)
        let product = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? ""
        let vendor = (IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int) ?? 0
        guard vendor == DeviceSupport.logitechVendorID else { return }
        lock.lock()
        let connected = snapshot.connected
        let mxName = snapshot.name
        lock.unlock()
        let looksLikeMX = DeviceSupport.isMXMasterName(product) || DeviceSupport.isMXMasterName(mxName)
        guard looksLikeMX, connected || DeviceSupport.isMXMasterName(product) else { return }
        if DeviceSupport.isMXMasterName(product) {
            lock.lock()
            if !snapshot.connected {
                snapshot.connected = true
                snapshot.name = product
                snapshot.product = product
                if snapshot.status.contains("Looking") || snapshot.status.contains("No MX Master") {
                    snapshot.status = "Mouse connected. Extra buttons come up over HID++."
                }
            }
            lock.unlock()
        }

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
            if integer > 0 {
                snapshot.thumbRight = true
                snapshot.thumbLeft = false
                thumbPulseUntil = now.addingTimeInterval(0.18)
            } else if integer < 0 {
                snapshot.thumbLeft = true
                snapshot.thumbRight = false
                thumbPulseUntil = now.addingTimeInterval(0.18)
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
            (model.gestureControlTitle, snapshot.haptic)
        ]
        lock.unlock()
        noteButtons(logged)
        if page == 0x09, usage == 7, model.nativeHapticButtonBit != nil {
            applyHapticEdge(down: integer != 0)
        }
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
        let factor = MappingProfile.gestureSpeedFactor(slider: desiredHapticGestureSpeed, dpi: dpi)
        gestureDelta.width += CGFloat(dx * factor)
        gestureDelta.height += CGFloat(dy * factor)
    }

    private static func liveDelta(hid: CGSize, pointer: CGSize) -> CGSize {
        if hid.width != 0 || hid.height != 0 {
            return hid
        }
        return pointer
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

    private func gestureOwner(forOtherMouse event: CGEvent) -> DeviceButton? {
        switch event.getIntegerValueField(.mouseEventButtonNumber) {
        case 2: return .mxMiddle
        case 3: return .mxBack
        case 4: return .mxForward
        case 5, 6:
            return model.nativeHapticButtonBit != nil ? .mxHaptic : nil
        default: return nil
        }
    }

    private func button(for cid: UInt16) -> DeviceButton? {
        if cid == model.gestureCID { return .mxHaptic }
        switch cid {
        case 0x0050: return .mxLeft
        case 0x0051: return .mxRight
        case 0x0052: return .mxMiddle
        case 0x0053: return .mxBack
        case 0x0054, 0x0056: return .mxForward
        case 0x00C4: return .mxSmartShift
        case 0x00D0, 0x00ED, 0x00FD: return .mxModeShift
        case 0x01A0: return .mxHaptic
        case 0x00C3, 0x00D6, 0x00D7: return .mxGesture
        default: return nil
        }
    }

    private func title(for cid: UInt16, task _: UInt16) -> String {
        if cid == model.gestureCID { return model.gestureControlTitle }
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

    private func reportingFlags(for control: ControlInfo) -> UInt8 {
        if control.rawXY || control.cid == model.gestureCID || Self.knownGestureCIDs.contains(control.cid) {
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
        switch button {
        case .mxLeft: return [0x0050]
        case .mxRight: return [0x0051]
        case .mxMiddle: return [0x0052]
        case .mxBack: return [0x0053]
        case .mxForward: return [0x0054, 0x0056]
        case .mxSmartShift: return [0x00C4]
        case .mxModeShift: return [0x00D0, 0x00ED, 0x00FD]
        case .mxHaptic: return [model.gestureCID]
        default: return []
        }
    }

    private static let knownGestureCIDs: Set<UInt16> = [0x00C3, 0x00D6, 0x00D7]
    private static let nativeClickCIDs: Set<UInt16> = [0x0050, 0x0051, 0x0052]
    private static let wheelCIDs: Set<UInt16> = [0x00D4, 0x00D7]
}
