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
    var name = "MX Master"
    var product = "Logitech MX Master"
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
    var extras: [MXMasterControl] = []
    var events: [InputLogEvent] = []
    var lastHIDEvent = "—"
}

final class LogitechMXMasterReader {
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

    private var hidppManager: IOHIDManager?
    private var mouseManager: IOHIDManager?
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
    private var activeGestureCID: UInt16?
    private var lastDivertedNative: Set<UInt16> = []
    private var ignoreNextRawXY = false
    private var lastHapticArm = Date.distantPast
    private var pressed = Set<UInt16>()
    private var controls: [ControlInfo] = []
    private var extraCIDs: [UInt16: String] = [:]
    private var gestureOrigin = CGPoint.zero
    private var gestureDelta = CGSize.zero
    private var usingRawXY = false
    private var cursorLocked = false
    private var ready = false
    private var previousButtons: [String: Bool] = [:]
    private var wheelPulseUntil = Date.distantPast
    private var thumbPulseUntil = Date.distantPast
    private var lastGestureAt = Date.distantPast
    private var hidppBuffers: [ObjectIdentifier: UnsafeMutablePointer<UInt8>] = [:]
    private var hiresWheelIndex: UInt8?
    private var thumbWheelIndex: UInt8?
    private var pointerScaleIndex: UInt8?
    private var dpiIndex: UInt8?
    private var dpiValues: [Int] = []
    private var lastPointerSpeed: Double = -1
    private var desiredPointerSpeed: Double = 0.5
    private var lastWheelConfig: (divert: Bool, invert: Bool)?
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
        if value.haptic || value.gestureDown {
            value.liveGesture = Self.classify(delta: gestureDelta, tapLimit: usingRawXY ? 110 : 36)
            value.gestureDX = gestureDelta.width
            value.gestureDY = gestureDelta.height
            value.gestureDown = true
        }
        return value
    }

    func start() {
        startHIDPP()
        startMouse()
    }

    func stop() {
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
        hidppDevice = nil
        unlockCursor()
        queuedHIDPP.removeAll()
        ready = false
        pending = nil
        hiresWheelIndex = nil
        thumbWheelIndex = nil
        pointerScaleIndex = nil
        dpiIndex = nil
        dpiValues = []
        lastPointerSpeed = -1
        lastWheelConfig = nil
        hidppQueue.removeAll()
        desiredPointerSpeed = 0.5
        naturalScrolling = true
        injectEnabled = false
        wheelsEnabled = false
        for buffer in hidppBuffers.values {
            buffer.deallocate()
        }
        hidppBuffers.removeAll()
        lock.lock()
        snapshot = MXMasterSnapshot()
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
        let cids = Set(buttons.flatMap(Self.cids(for:)))
        guard cids != gestureCIDs else { return }
        gestureCIDs = cids
        if let haptic = cids.first(where: { $0 == hapticCID }) {
            gestureCID = haptic
        } else {
            gestureCID = cids.first ?? hapticCID
        }
        divertNativeGestureOwners()
    }

    func applyScrollDirection(_ natural: Bool) {
        guard naturalScrolling != natural else { return }
        naturalScrolling = natural
        lastWheelConfig = nil
        applyWheelRouting()
    }

    func applyPointerSpeed(_ speed: Double) {
        desiredPointerSpeed = min(max(speed, 0), 1)
        sendPointerSpeedIfNeeded()
    }

    private func sendPointerSpeedIfNeeded() {
        guard ready else { return }
        let clamped = desiredPointerSpeed
        guard abs(clamped - lastPointerSpeed) > 0.01 else { return }
        var sent = false
        if let pointerScaleIndex {
            let factor = pow(4.0, (clamped - 0.5) * 2)
            let scaling = UInt16(min(max(factor * 256, 16), 4096))
            request(featureIndex: pointerScaleIndex, function: 1, params: [
                UInt8(scaling >> 8),
                UInt8(scaling & 0xFF)
            ]) { _ in }
            sent = true
        }
        if let dpiIndex {
            let dpi = dpiValue(for: clamped)
            request(featureIndex: dpiIndex, function: 3, params: [
                0,
                UInt8((dpi >> 8) & 0xFF),
                UInt8(dpi & 0xFF)
            ]) { _ in }
            sent = true
        }
        if sent {
            lastPointerSpeed = clamped
        }
    }

    private func dpiValue(for slider: Double) -> Int {
        if !dpiValues.isEmpty {
            let index = Int((slider * Double(dpiValues.count - 1)).rounded())
            return dpiValues[min(max(index, 0), dpiValues.count - 1)]
        }
        if slider <= 0.5 {
            return Int((400 + slider * 2 * 1200).rounded())
        }
        return Int((1600 + (slider - 0.5) * 2 * 6400).rounded())
    }

    func pollGesturePointer() {
        maybeRearmHaptic()
        lock.lock()
        let down = snapshot.haptic || snapshot.gestureDown
        let skipCursor = usingRawXY
        lock.unlock()
        guard down else {
            unlockCursor()
            return
        }
        lockCursor()
        CGWarpMouseCursorPosition(gestureOrigin)
        guard !skipCursor else { return }
        let location = CGEvent(source: nil)?.location ?? .zero
        lock.lock()
        gestureDelta.width += location.x - gestureOrigin.x
        gestureDelta.height += location.y - gestureOrigin.y
        snapshot.gestureDX = gestureDelta.width
        snapshot.gestureDY = gestureDelta.height
        lock.unlock()
        CGWarpMouseCursorPosition(gestureOrigin)
    }

    private func lockCursor() {
        guard !cursorLocked else { return }
        gestureOrigin = CGEvent(source: nil)?.location ?? .zero
        CGAssociateMouseAndMouseCursorPosition(0)
        CGWarpMouseCursorPosition(gestureOrigin)
        cursorLocked = true
    }

    private func unlockCursor() {
        guard cursorLocked else { return }
        CGWarpMouseCursorPosition(gestureOrigin)
        CGAssociateMouseAndMouseCursorPosition(1)
        cursorLocked = false
    }

    private func startHIDPP() {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matches: [[String: Any]] = [
            [
                kIOHIDVendorIDKey as String: DeviceSupport.logitechVendorID,
                kIOHIDPrimaryUsagePageKey as String: 0xFF00
            ],
            [
                kIOHIDVendorIDKey as String: DeviceSupport.logitechVendorID,
                kIOHIDDeviceUsagePageKey as String: 0xFF00
            ]
        ]
        IOHIDManagerSetDeviceMatchingMultiple(mgr, matches as CFArray)
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(mgr, { context, _, _, device in
            guard let context else { return }
            Unmanaged<LogitechMXMasterReader>.fromOpaque(context).takeUnretainedValue().attachHIDPP(device)
        }, pointer)
        IOHIDManagerRegisterDeviceRemovalCallback(mgr, { context, _, _, device in
            guard let context else { return }
            Unmanaged<LogitechMXMasterReader>.fromOpaque(context).takeUnretainedValue().detachHIDPP(device)
        }, pointer)
        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        var opened = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        if opened != kIOReturnSuccess {
            opened = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        hidppManager = mgr
        if let copied = IOHIDManagerCopyDevices(mgr) {
            var devices: [IOHIDDevice] = []
            for case let item as IOHIDDevice in (copied as NSSet) {
                devices.append(item)
            }
            devices.sort { lhs, rhs in
                isLikelyMXMaster(lhs) && !isLikelyMXMaster(rhs)
            }
            for device in devices {
                attachHIDPP(device)
            }
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

    private func attachHIDPP(_ incoming: IOHIDDevice) {
        if incoming == hidppDevice { return }
        if queuedHIDPP.contains(where: { $0 == incoming }) { return }
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

    private func beginProbe(_ device: IOHIDDevice) {
        hidppQueue.removeAll()
        pending = nil
        hidppDevice = device
        _ = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        registerHIDPPCallback(device)
        let product = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? "Logitech HID++"
        setStatus("Talking to \(product) over HID++…")
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
                guard let context else { return }
                Unmanaged<LogitechMXMasterReader>.fromOpaque(context).takeUnretainedValue()
                    .handleReport(report, length: length)
            },
            pointer
        )
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    private func teardownHIDPP(_ device: IOHIDDevice, keepQueued: Bool) {
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        if let buffer = hidppBuffers.removeValue(forKey: ObjectIdentifier(device)) {
            buffer.deallocate()
        }
        if !keepQueued {
            queuedHIDPP.removeAll { $0 == device }
        }
    }

    private func detachHIDPP(_ incoming: IOHIDDevice) {
        queuedHIDPP.removeAll { $0 == incoming }
        if hidppDevice != incoming {
            if let buffer = hidppBuffers.removeValue(forKey: ObjectIdentifier(incoming)) {
                buffer.deallocate()
            }
            return
        }
        teardownHIDPP(incoming, keepQueued: false)
        hidppDevice = nil
        ready = false
        pending = nil
        hidppQueue.removeAll()
        unlockCursor()
        lock.lock()
        snapshot = MXMasterSnapshot()
        snapshot.status = "MX Master disconnected"
        lock.unlock()
        probeNextHIDPP(failed: "MX Master disconnected")
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
    }

    private func popBestQueued() -> IOHIDDevice? {
        if let index = queuedHIDPP.firstIndex(where: isLikelyMXMaster) {
            return queuedHIDPP.remove(at: index)
        }
        guard !queuedHIDPP.isEmpty else { return nil }
        return queuedHIDPP.removeFirst()
    }

    private func isLikelyMXMaster(_ device: IOHIDDevice) -> Bool {
        let product = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? ""
        return DeviceSupport.isMXMasterName(product)
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
                self.request(featureIndex: 0, function: 0, params: [0x1B, 0x04]) { [weak self] reprog in
                    guard let self else { return }
                    self.reprogIndex = reprog?.first
                    self.finishSetup(named: fallbackName)
                }
                return
            } else {
                self.failHIDPPAndTryNext("MX Master did not report a name.")
                return
            }
            self.request(featureIndex: 0, function: 0, params: [0x1B, 0x04]) { [weak self] reprog in
                guard let self else { return }
                self.reprogIndex = reprog?.first
                if let nameIndex = self.nameIndex {
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
        snapshot.name = trimmed.isEmpty ? "MX Master" : trimmed
        snapshot.product = snapshot.name
        snapshot.connected = isMX
        snapshot.status = isMX ? "Connected" : "Logitech device is not an MX Master"
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

    private func enumerateAndDivert(index: Int, count: Int) {
        guard let reprogIndex else {
            setStatus("This MX Master does not expose the gesture button.")
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
            divertKnownButtons()
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
        hapticCID = 0x01A0
        gestureCIDs = [0x01A0]
        if controls.contains(where: { $0.cid == 0x01A0 }) {
            gestureCID = 0x01A0
        }
        if controls.contains(where: { $0.cid == 0x00C3 }) {
            gestureCIDs.insert(0x00C3)
            if !controls.contains(where: { $0.cid == 0x01A0 }) {
                gestureCID = 0x00C3
            }
        }
        for cid in [UInt16(0x00D6), 0x00D7] where controls.contains(where: { $0.cid == cid }) {
            gestureCIDs.insert(cid)
        }
    }

    private func divertKnownButtons() {
        guard let reprogIndex else { return }
        extraCIDs.removeAll()
        var jobs: [(UInt16, UInt8, UInt8)] = [
            (0x01A0, 0x33, 0x03)
        ]
        for control in controls where control.divertable {
            if Self.nativeClickCIDs.contains(control.cid), !gestureCIDs.contains(control.cid) { continue }
            if Self.wheelCIDs.contains(control.cid) { continue }
            if control.cid == 0x01A0 { continue }
            jobs.append((control.cid, Self.reportingFlags(for: control), 0))
            if Self.button(for: control.cid) == nil, !gestureCIDs.contains(control.cid) {
                extraCIDs[control.cid] = Self.title(for: control.cid, task: control.task)
            }
        }
        divert(jobs: jobs, reprogIndex: reprogIndex) { [weak self] in
            guard let self else { return }
            self.ready = true
            self.lastHapticArm = Date()
            self.lookupMotionFeatures {
                self.lastWheelConfig = nil
                self.lastPointerSpeed = -1
                self.sendPointerSpeedIfNeeded()
                self.applyWheelRouting()
                self.setStatus("Connected. Pointer speed, wheel speed, and scroll direction are applied from the profile.")
            }
        }
    }

    private func maybeRearmHaptic() {
        guard ready, let reprogIndex else { return }
        guard Date().timeIntervalSince(lastHapticArm) > 3 else { return }
        lastHapticArm = Date()
        lastWheelConfig = nil
        armHaptic(reprogIndex: reprogIndex) { [weak self] in
            self?.applyWheelRouting()
        }
    }

    private func armHaptic(reprogIndex: UInt8, completion: (() -> Void)? = nil) {
        let params: [UInt8] = [0x01, 0xA0, 0x33, 0, 0, 0x03]
        request(featureIndex: reprogIndex, function: 3, params: params) { _ in
            completion?()
        }
    }

    private func divert(jobs: [(UInt16, UInt8, UInt8)], reprogIndex: UInt8, completion: @escaping () -> Void) {
        guard let job = jobs.first else {
            completion()
            return
        }
        var params: [UInt8] = [
            UInt8(job.0 >> 8), UInt8(job.0 & 0xFF),
            job.1,
            0, 0
        ]
        if job.2 != 0 {
            params.append(job.2)
        }
        request(featureIndex: reprogIndex, function: 3, params: params) { [weak self] data in
            guard let self else { return }
            if data == nil, job.1 != 0x03 {
                self.divert(jobs: [(job.0, 0x03, job.2)] + Array(jobs.dropFirst()), reprogIndex: reprogIndex, completion: completion)
                return
            }
            self.divert(jobs: Array(jobs.dropFirst()), reprogIndex: reprogIndex, completion: completion)
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
        }
    }

    private func applyWheelRouting() {
        guard ready else { return }
        guard hiresWheelIndex != nil || thumbWheelIndex != nil else { return }
        // Leave the main wheel on native HID so a CGEvent tap can reverse and
        // scale it. Only the thumb wheel stays on HID++ (it often has no HID axis).
        let divertThumb = wheelsEnabled
        if lastWheelConfig?.divert == divertThumb, lastWheelConfig?.invert == false { return }
        lastWheelConfig = (divertThumb, false)
        if let hiresWheelIndex {
            request(featureIndex: hiresWheelIndex, function: 2, params: [0b0000_0010]) { [weak self] _ in
                self?.applyThumbRouting(divert: divertThumb, invert: false)
            }
            return
        }
        applyThumbRouting(divert: divertThumb, invert: false)
    }

    private func applyThumbRouting(divert: Bool, invert: Bool) {
        guard let thumbWheelIndex else { return }
        request(featureIndex: thumbWheelIndex, function: 2, params: [divert ? 1 : 0, invert ? 1 : 0]) { _ in }
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
        var short = [UInt8](repeating: 0, count: 7)
        short[0] = 0x10
        short[1] = deviceIndex
        short[2] = call.featureIndex
        short[3] = (call.function << 4) | (swID & 0x0F)
        for (offset, byte) in call.params.prefix(3).enumerated() {
            short[4 + offset] = byte
        }
        let kr = report.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return kIOReturnError }
            return IOHIDDeviceSetReport(hidppDevice, kIOHIDReportTypeOutput, CFIndex(0x11), base, 20)
        }
        _ = short.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return kIOReturnError }
            return IOHIDDeviceSetReport(hidppDevice, kIOHIDReportTypeOutput, CFIndex(0x10), base, 7)
        }
        if kr != kIOReturnSuccess {
            _ = report.withUnsafeBufferPointer { buffer in
                guard let base = buffer.baseAddress else { return kIOReturnError }
                return IOHIDDeviceSetReport(hidppDevice, kIOHIDReportTypeOutput, 0, base, 20)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self, let pending = self.pending, pending.swID == swID else { return }
            self.pending = nil
            pending.completion(nil)
        }
    }

    private func handleReport(_ report: UnsafePointer<UInt8>, length: Int) {
        guard length >= 4 else { return }
        var bytes = Array(UnsafeBufferPointer(start: report, count: length))
        if bytes[0] != 0x10 && bytes[0] != 0x11 && bytes.count >= 3 {
            bytes.insert(0x11, at: 0)
        }
        guard bytes.count >= 4 else { return }
        if bytes[2] == 0x8F {
            if let pending {
                self.pending = nil
                pending.completion(nil)
            }
            return
        }
        let featureIndex = bytes[2]
        let function = bytes.count > 3 ? bytes[3] >> 4 : 0
        let swID = bytes.count > 3 ? bytes[3] & 0x0F : 0
        let payload = Data(bytes.dropFirst(4))

        if swID != 0, let pending, pending.swID == swID {
            self.pending = nil
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
            }
            return
        }
        if let hiresWheelIndex, featureIndex == hiresWheelIndex, function == 0 {
            handleHiresWheel(payload)
            return
        }
        if let thumbWheelIndex, featureIndex == thumbWheelIndex, function == 0 {
            handleThumbWheel(payload)
        }
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
        applyPressed(next)

        if activeGestureCID == nil, let cid = added.first(where: { gestureCIDs.contains($0) }) {
            activeGestureCID = cid
            usingRawXY = false
            ignoreNextRawXY = true
            gestureDelta = .zero
            gestureOrigin = CGEvent(source: nil)?.location ?? .zero
            lockCursor()
            lock.lock()
            snapshot.liveGestureOwner = Self.button(for: cid) ?? .mxHaptic
            snapshot.gestureDown = true
            lock.unlock()
            noteLastEvent("gesture down")
        }
        if let cid = activeGestureCID, removed.contains(cid) {
            activeGestureCID = nil
            finishGesture(released: cid)
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
        snapshot.haptic = next.contains(self.hapticCID)
        snapshot.extras = extras
        snapshot.gestureDown = next.contains(where: { self.gestureCIDs.contains($0) }) || next.contains(self.hapticCID)
        lock.unlock()

        var logged = [
            ("Back", next.contains(0x0053)),
            ("Forward", next.contains(0x0056) || next.contains(0x0054)),
            ("Mode shift", next.contains(0x00C4)),
            ("DPI", next.contains(0x00D0) || next.contains(0x00ED) || next.contains(0x00FD)),
            ("Haptic", next.contains(hapticCID)),
            ("Gesture", next.contains(hapticCID) || next.contains(where: { gestureCIDs.contains($0) }))
        ]
        logged.append(contentsOf: extras.map { ($0.title, $0.down) })
        noteButtons(logged)
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
        gestureDelta.width += CGFloat(dx)
        gestureDelta.height += CGFloat(dy)
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
        if sawHaptic {
            noteLastEvent("analytics haptic")
        }
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
        let moved = hypot(gestureDelta.width, gestureDelta.height) >= (usingRawXY ? 80 : 36)
        let button: DeviceButton
        if moved {
            button = Self.classify(delta: gestureDelta, tapLimit: 0)
        } else {
            button = .mxGesture
        }
        lock.lock()
        snapshot.pendingGesture = button
        snapshot.pendingGestureOwner = Self.button(for: released) ?? snapshot.liveGestureOwner ?? .mxHaptic
        snapshot.liveGestureOwner = nil
        snapshot.lastGesture = button
        snapshot.liveGesture = nil
        snapshot.gestureDown = false
        snapshot.haptic = false
        snapshot.gestureDX = 0
        snapshot.gestureDY = 0
        lastGestureAt = Date()
        lock.unlock()
        unlockCursor()
        logEvent(button.title, pressed: true)
        gestureDelta = .zero
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
        let wasHaptic = snapshot.haptic
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
            snapshot.haptic = integer != 0
            snapshot.gestureDown = integer != 0 || snapshot.gestureDown
        case (0x01, 0x30):
            if snapshot.haptic || snapshot.gestureDown, integer != 0 {
                usingRawXY = true
                gestureDelta.width += CGFloat(integer)
                snapshot.gestureDX = gestureDelta.width
            }
        case (0x01, 0x31):
            if snapshot.haptic || snapshot.gestureDown, integer != 0 {
                usingRawXY = true
                gestureDelta.height += CGFloat(integer)
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
            ("Haptic", snapshot.haptic)
        ]
        lock.unlock()
        noteButtons(logged)
        if page == 0x09, usage == 7, gestureCIDs.contains(hapticCID) {
            if integer != 0, !wasHaptic {
                usingRawXY = false
                ignoreNextRawXY = true
                gestureDelta = .zero
                gestureOrigin = CGEvent(source: nil)?.location ?? .zero
                lockCursor()
                lock.lock()
                snapshot.liveGestureOwner = .mxHaptic
                lock.unlock()
                noteLastEvent("haptic HID down")
            } else if integer == 0, wasHaptic {
                finishGesture(released: hapticCID)
            }
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

    private static func classify(delta: CGSize, tapLimit: CGFloat) -> DeviceButton {
        let dx = delta.width
        let dy = delta.height
        if hypot(dx, dy) < tapLimit {
            return .mxGesture
        }
        if abs(dx) > abs(dy) {
            return dx < 0 ? .mxGestureLeft : .mxGestureRight
        }
        return dy < 0 ? .mxGestureUp : .mxGestureDown
    }

    private static func button(for cid: UInt16) -> DeviceButton? {
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

    private static func title(for cid: UInt16, task _: UInt16) -> String {
        if let button = button(for: cid) { return button.title }
        switch cid {
        case 0x00D4: return "Thumb wheel"
        default: return String(format: "Button %04X", cid)
        }
    }

    private static func reportingFlags(for control: ControlInfo) -> UInt8 {
        var flags: UInt8 = 0x03
        if control.rawXY || Self.knownGestureCIDs.contains(control.cid) || control.cid == 0x01A0 {
            flags |= 0x30
        }
        if control.forceRawXY {
            flags |= 0xC0
        }
        return flags
    }

    private static func be16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
    }

    private static func cids(for button: DeviceButton) -> [UInt16] {
        switch button {
        case .mxLeft: return [0x0050]
        case .mxRight: return [0x0051]
        case .mxMiddle: return [0x0052]
        case .mxBack: return [0x0053]
        case .mxForward: return [0x0054, 0x0056]
        case .mxSmartShift: return [0x00C4]
        case .mxModeShift: return [0x00D0, 0x00ED, 0x00FD]
        case .mxHaptic: return [0x01A0, 0x00C3]
        default: return []
        }
    }

    private func divertNativeGestureOwners() {
        guard ready, let reprogIndex else { return }
        let extra = gestureCIDs.intersection(Self.nativeClickCIDs)
        guard extra != lastDivertedNative else { return }
        lastDivertedNative = extra
        let jobs = extra.map { ($0, UInt8(0x03), UInt8(0)) }
        divert(jobs: jobs, reprogIndex: reprogIndex) { }
    }
    private static let knownGestureCIDs: Set<UInt16> = [0x00C3, 0x00D6, 0x00D7]
    private static let nativeClickCIDs: Set<UInt16> = [0x0050, 0x0051, 0x0052]
    private static let wheelCIDs: Set<UInt16> = [0x00D4]
}
