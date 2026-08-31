import Foundation
import IOKit.hid

/// HID++ 2.0 client for MX Mechanical / Mini. Settings only: backlight,
/// lighting effect, battery saving, battery percent.
/// Do not seize. Do not divert keys. Do not open Bolt `C548`. Do not treat
/// keyboard reports as HID++ (only report IDs `0x10` / `0x11`).
final class MXKeyboardReader {
    private static let deviceNameFeature: UInt16 = 0x0005
    private static let unifiedBatteryFeature: UInt16 = 0x1004
    private static let backlight2Feature: UInt16 = 0x1982
    private static let effectUnchanged: UInt8 = 0xFF
    private static let effectDebounce: TimeInterval = 0.05
    private static let powerSaveBit: UInt16 = 1 << 2
    private static let modeShift: UInt16 = 3
    private static let modeMask: UInt16 = 0b11 << 3
    private static let batteryInterval: TimeInterval = 30

    private struct Pending {
        let swID: UInt8
        let featureIndex: UInt8
        let completion: (Data?) -> Void
    }

    private struct BacklightConfig {
        var enabled: Bool
        var options: UInt16
        var mode: UInt8
        var effectList: UInt16
        var level: UInt8
        var durationHandsOut: UInt16
        var durationHandsIn: UInt16
        var durationPowered: UInt16
    }

    private var snapshot = MXKeyboardSnapshot()
    private let lock = NSLock()
    private let ioQueue = DispatchQueue(label: "controlbox.mx-keyboard.io")
    private var running = false
    private var hidppManager: IOHIDManager?
    private var hidppDevice: IOHIDDevice?
    private var queuedHIDPP: [IOHIDDevice] = []
    private var hidppBuffers: [ObjectIdentifier: UnsafeMutablePointer<UInt8>] = [:]
    private var hidppQueue: [(featureIndex: UInt8, function: UInt8, params: [UInt8], completion: (Data?) -> Void)] = []
    private var pending: Pending?
    private var hidppEpoch = 0
    private var swCounter: UInt8 = 0x07
    private var deviceIndex: UInt8 = 0xFF
    private var batteryIndex: UInt8?
    private var backlightIndex: UInt8?
    private var nameIndex: UInt8?
    private var backlightConfig: BacklightConfig?
    private var consecutiveTimeouts = 0
    private var batteryTimer: Timer?
    private var recoverWork: DispatchWorkItem?
    private var effectWriteWork: DispatchWorkItem?

    var current: MXKeyboardSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }

    func start() {
        running = true
        startHIDPP()
    }

    func stop() {
        running = false
        recoverWork?.cancel()
        recoverWork = nil
        effectWriteWork?.cancel()
        effectWriteWork = nil
        stopBatteryTimer()
        hidppEpoch += 1
        hidppQueue.removeAll()
        pending = nil
        ioQueue.sync {}
        if let hidppDevice {
            IOHIDDeviceUnscheduleFromRunLoop(hidppDevice, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            releaseReportBuffer(hidppDevice)
            _ = IOHIDDeviceClose(hidppDevice, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        if let hidppManager {
            IOHIDManagerUnscheduleFromRunLoop(hidppManager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(hidppManager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        hidppManager = nil
        hidppDevice = nil
        queuedHIDPP.removeAll()
        clearFeatureIndices()
        lock.lock()
        snapshot = MXKeyboardSnapshot()
        lock.unlock()
    }

    func setBacklightEnabled(_ enabled: Bool) {
        publish { $0.backlightEnabled = enabled }
        enqueueBacklightWrite { config in
            config.enabled = enabled
            return Self.effectUnchanged
        }
    }

    func setBacklightEffect(_ effect: MXKeyboardBacklightEffect) {
        publish { $0.backlightEffect = effect }
        effectWriteWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.enqueueBacklightWrite { _ in
                effect.rawValue
            }
        }
        effectWriteWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.effectDebounce, execute: work)
    }

    func setBatterySaving(_ enabled: Bool) {
        publish { $0.batterySaving = enabled }
        enqueueBacklightWrite { config in
            if enabled {
                config.options |= Self.powerSaveBit
            } else {
                config.options &= ~Self.powerSaveBit
            }
            return Self.effectUnchanged
        }
    }

    private func enqueueBacklightWrite(_ update: @escaping (inout BacklightConfig) -> UInt8) {
        DispatchQueue.main.async { [weak self] in
            self?.commitBacklight(update)
        }
    }

    private func commitBacklight(_ update: @escaping (inout BacklightConfig) -> UInt8) {
        guard backlightIndex != nil else { return }
        let apply: (BacklightConfig) -> Void = { [weak self] current in
            guard let self else { return }
            var next = current
            let effect = update(&next)
            self.backlightConfig = next
            self.writeBacklight(next, effect: effect) { [weak self] ok in
                if !ok {
                    self?.readBacklight()
                }
            }
        }
        if let backlightConfig {
            apply(backlightConfig)
            return
        }
        readBacklight { config in
            guard let config else { return }
            apply(config)
        }
    }

    private func startHIDPP() {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatchingMultiple(mgr, MXMechanicalSupport.hidManagerMatches() as CFArray)
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(mgr, { context, _, _, device in
            guard let context else { return }
            let reader = Unmanaged<MXKeyboardReader>.fromOpaque(context)
            DispatchQueue.main.async {
                reader.takeUnretainedValue().attachHIDPP(device)
            }
        }, pointer)
        IOHIDManagerRegisterDeviceRemovalCallback(mgr, { context, _, _, device in
            guard let context else { return }
            let reader = Unmanaged<MXKeyboardReader>.fromOpaque(context)
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
        for device in devices where MXMechanicalSupport.matches(device) {
            attachHIDPP(device)
        }
    }

    private func attachHIDPP(_ incoming: IOHIDDevice) {
        guard running else { return }
        if isSameDevice(incoming, hidppDevice) { return }
        if hidppDevice == nil {
            beginProbe(incoming)
            return
        }
        queuedHIDPP.append(incoming)
    }

    private func detachHIDPP(_ incoming: IOHIDDevice) {
        queuedHIDPP.removeAll { isSameDevice(incoming, $0) }
        guard isSameDevice(incoming, hidppDevice) else { return }
        failHIDPPAndTryNext("MX Mechanical disconnected")
    }

    private func beginProbe(_ device: IOHIDDevice) {
        hidppEpoch += 1
        hidppQueue.removeAll()
        pending = nil
        clearFeatureIndices()
        stopBatteryTimer()
        hidppDevice = device
        consecutiveTimeouts = 0
        _ = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        registerHIDPPCallback(device)
        let product = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? "MX Mechanical"
        let kind = MXMechanicalSupport.kind(of: device)
        lock.lock()
        snapshot.kind = kind
        snapshot.name = product
        snapshot.product = product
        snapshot.address = DeviceIdentity.fromHID(device)
        snapshot.connected = true
        snapshot.hidppReady = false
        snapshot.status = "Talking to \(product) over HID++…"
        lock.unlock()
        probeDeviceIndices([0xFF, 0x00, 1, 2, 3])
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
                let first = report[0]
                guard first == 0x10 || first == 0x11 else { return }
                let bytes = Array(UnsafeBufferPointer(start: report, count: length))
                let reader = Unmanaged<MXKeyboardReader>.fromOpaque(context).takeUnretainedValue()
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

    private func releaseReportBuffer(_ device: IOHIDDevice) {
        let id = ObjectIdentifier(device)
        if let buffer = hidppBuffers.removeValue(forKey: id) {
            IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, nil, nil)
            buffer.deallocate()
        }
    }

    private func probeDeviceIndices(_ indices: [UInt8]) {
        guard let index = indices.first else {
            failHIDPPAndTryNext("No HID++ reply from the keyboard. LogiPluginService can block this even after Options+ is removed.")
            return
        }
        deviceIndex = index
        request(featureIndex: 0, function: 0, params: [0x00, 0x01]) { [weak self] data in
            guard let self else { return }
            if data != nil {
                self.identifyDevice()
                return
            }
            self.probeDeviceIndices(Array(indices.dropFirst()))
        }
    }

    private func identifyDevice() {
        lookup(Self.deviceNameFeature) { [weak self] index in
            guard let self else { return }
            self.nameIndex = index
            self.lookupFeaturesThenLoad()
        }
    }

    private func lookupFeaturesThenLoad() {
        lookup(Self.unifiedBatteryFeature) { [weak self] battery in
            guard let self else { return }
            self.batteryIndex = battery
            self.lookup(Self.backlight2Feature) { [weak self] backlight in
                guard let self else { return }
                self.backlightIndex = backlight
                self.finishSetup()
            }
        }
    }

    private func finishSetup() {
        if let hidppDevice {
            let kind = MXMechanicalSupport.kind(of: hidppDevice)
            let product = (IOHIDDeviceGetProperty(hidppDevice, kIOHIDProductKey as CFString) as? String) ?? kind.title
            publish {
                $0.kind = kind
                $0.name = product
                $0.product = product
                $0.connected = true
                $0.hidppReady = true
                $0.status = "Connected"
                $0.backlightSupported = self.backlightIndex != nil
                $0.batteryAvailable = self.batteryIndex != nil
            }
        }
        readNameIfNeeded()
        readBattery()
        readBacklight()
        startBatteryTimer()
    }

    private func readNameIfNeeded() {
        guard let nameIndex else { return }
        request(featureIndex: nameIndex, function: 0, params: []) { [weak self] data in
            guard let self, let length = data?.first, length > 0 else { return }
            self.readName(length: Int(length), assembled: "")
        }
    }

    private func readName(length: Int, assembled: String) {
        guard let nameIndex else { return }
        if assembled.utf8.count >= length {
            let trimmed = assembled.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            publish {
                $0.name = trimmed
                $0.product = trimmed
                $0.kind = MXMechanicalSupport.kind(from: trimmed)
            }
            return
        }
        request(featureIndex: nameIndex, function: 1, params: [UInt8(assembled.utf8.count)]) { [weak self] data in
            guard let self, let data else { return }
            let chunk = data.filter { $0 != 0 }
            let piece = String(bytes: chunk, encoding: .utf8) ?? ""
            self.readName(length: length, assembled: assembled + piece)
        }
    }

    private func readBattery() {
        guard let batteryIndex else { return }
        request(featureIndex: batteryIndex, function: 1, params: []) { [weak self] data in
            self?.applyBattery(data)
        }
    }

    private func applyBattery(_ data: Data?) {
        guard let data, !data.isEmpty else { return }
        let percent = Int(data[0])
        let status = data.count > 2 ? data[2] : 0
        let charging = status == 1 || status == 4
        let full = status == 3 || (percent >= 95 && (status == 2 || status == 3))
        let description: String
        switch status {
        case 1, 4: description = "Charging"
        case 2: description = "Almost full"
        case 3: description = full ? "Full" : "Almost full"
        default: description = "Discharging"
        }
        publish {
            $0.batteryAvailable = true
            $0.batteryPercent = percent
            $0.batteryCharging = charging
            $0.batteryFull = full
            $0.batteryStateDescription = description
        }
    }

    private func readBacklight(completion: ((BacklightConfig?) -> Void)? = nil) {
        guard let backlightIndex else {
            completion?(nil)
            return
        }
        request(featureIndex: backlightIndex, function: 0, params: []) { [weak self] data in
            guard let self else {
                completion?(nil)
                return
            }
            if let config = self.parseBacklightConfig(data) {
                self.backlightConfig = config
                self.publishBacklight(config)
                self.requestBacklight(function: 2, params: []) { [weak self] info in
                    self?.applyBacklightInfo(info)
                    completion?(config)
                }
            } else {
                completion?(nil)
            }
        }
    }

    private func parseBacklightConfig(_ data: Data?) -> BacklightConfig? {
        guard let data, data.count >= 6 else { return nil }
        let rawOptions = UInt16(data[1]) | UInt16(data.count > 2 ? data[2] : 0) << 8
        let mode = UInt8((rawOptions & Self.modeMask) >> Self.modeShift)
        let effects: UInt16
        if data.count >= 5 {
            effects = UInt16(data[3]) | UInt16(data[4]) << 8
        } else {
            effects = 0
        }
        func le16(_ offset: Int) -> UInt16 {
            guard data.count >= offset + 2 else { return 0 }
            return UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
        }
        return BacklightConfig(
            enabled: data[0] & 1 != 0,
            options: rawOptions & ~Self.modeMask,
            mode: mode,
            effectList: effects,
            level: data.count > 5 ? data[5] : 0,
            durationHandsOut: le16(6),
            durationHandsIn: le16(8),
            durationPowered: le16(10)
        )
    }

    private func publishBacklight(_ config: BacklightConfig) {
        var effects = MXKeyboardBacklightEffect.allCases.filter { effect in
            config.effectList & (1 << effect.rawValue) != 0 && effect.showsInPicker
        }
        if effects.isEmpty {
            effects = MXKeyboardBacklightEffect.allCases.filter(\.showsInPicker)
        }
        publish {
            $0.backlightSupported = true
            $0.backlightEnabled = config.enabled
            $0.supportedEffects = effects
            $0.batterySavingSupported = true
            $0.batterySaving = config.options & Self.powerSaveBit != 0
        }
    }

    private func applyBacklightInfo(_ data: Data?) {
        guard let data, data.count >= 4,
              let effect = MXKeyboardBacklightEffect(rawValue: data[3])
        else { return }
        publish { $0.backlightEffect = effect }
    }

    private func writeBacklight(_ config: BacklightConfig, effect: UInt8, completion: @escaping (Bool) -> Void) {
        var mode = config.mode
        if mode == 2 { mode = 1 }
        let writable = config.options & (1 | 1 << 1 | Self.powerSaveBit)
        let optionsByte = UInt8(writable & 0x07) | (mode << 3)
        var params = [UInt8](repeating: 0, count: 10)
        params[0] = config.enabled ? 1 : 0
        params[1] = optionsByte
        params[2] = effect
        params[3] = config.level
        params[4] = UInt8(config.durationHandsOut & 0xFF)
        params[5] = UInt8(config.durationHandsOut >> 8)
        params[6] = UInt8(config.durationHandsIn & 0xFF)
        params[7] = UInt8(config.durationHandsIn >> 8)
        params[8] = UInt8(config.durationPowered & 0xFF)
        params[9] = UInt8(config.durationPowered >> 8)
        requestBacklight(function: 1, params: params) { data in
            completion(data != nil)
        }
    }

    private func requestBacklight(function: UInt8, params: [UInt8], completion: @escaping (Data?) -> Void) {
        guard let backlightIndex else {
            completion(nil)
            return
        }
        request(featureIndex: backlightIndex, function: function, params: params, completion: completion)
    }

    private func lookup(_ feature: UInt16, completion: @escaping (UInt8?) -> Void) {
        request(
            featureIndex: 0,
            function: 0,
            params: [UInt8(feature >> 8), UInt8(feature & 0xFF)]
        ) { data in
            if let index = data?.first, index != 0 {
                completion(index)
            } else {
                completion(nil)
            }
        }
    }

    private func startBatteryTimer() {
        stopBatteryTimer()
        let timer = Timer(timeInterval: Self.batteryInterval, repeats: true) { [weak self] _ in
            self?.readBattery()
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        batteryTimer = timer
    }

    private func stopBatteryTimer() {
        batteryTimer?.invalidate()
        batteryTimer = nil
    }

    private func failHIDPPAndTryNext(_ message: String) {
        hidppEpoch += 1
        hidppQueue.removeAll()
        pending = nil
        stopBatteryTimer()
        ioQueue.sync {}
        if let current = hidppDevice {
            IOHIDDeviceUnscheduleFromRunLoop(current, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            releaseReportBuffer(current)
            _ = IOHIDDeviceClose(current, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        hidppDevice = nil
        clearFeatureIndices()
        lock.lock()
        snapshot.connected = false
        snapshot.hidppReady = false
        snapshot.status = message
        lock.unlock()
        if let next = popBestQueued() {
            beginProbe(next)
            return
        }
        scheduleRecover()
    }

    private func popBestQueued() -> IOHIDDevice? {
        guard !queuedHIDPP.isEmpty else { return nil }
        return queuedHIDPP.removeFirst()
    }

    private func scheduleRecover() {
        recoverWork?.cancel()
        guard running else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.scanHIDPP()
        }
        recoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    private func clearFeatureIndices() {
        batteryIndex = nil
        backlightIndex = nil
        nameIndex = nil
        backlightConfig = nil
    }

    private func isSameDevice(_ lhs: IOHIDDevice, _ rhs: IOHIDDevice?) -> Bool {
        guard let rhs else { return false }
        return CFEqual(lhs, rhs)
    }

    private func request(featureIndex: UInt8, function: UInt8, params: [UInt8], completion: @escaping (Data?) -> Void) {
        hidppQueue.append((featureIndex, function, params, completion))
        pumpHIDPP()
    }

    private func pumpHIDPP() {
        guard pending == nil, let hidppDevice, let call = hidppQueue.first else { return }
        swCounter = swCounter == 0x0F ? 0x08 : swCounter + 1
        let swID = swCounter
        pending = Pending(swID: swID, featureIndex: call.featureIndex, completion: { [weak self] data in
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
        let device = hidppDevice
        ioQueue.async {
            _ = report.withUnsafeBufferPointer { buffer in
                guard let base = buffer.baseAddress else { return kIOReturnError }
                return IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(0x11), base, 20)
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
            self.lock.lock()
            let ready = self.snapshot.hidppReady
            self.lock.unlock()
            guard !ready else { return }
            self.consecutiveTimeouts += 1
            if self.consecutiveTimeouts >= 3 {
                self.failHIDPPAndTryNext("HID++ timed out. LogiPluginService can block this even after Options+ is removed.")
            }
        }
    }

    private func handleReport(_ report: [UInt8]) {
        guard report.count >= 4 else { return }
        guard report[0] == 0x10 || report[0] == 0x11 else { return }
        if report[2] == 0x8F {
            if let pending {
                self.pending = nil
                pending.completion(nil)
            }
            return
        }
        let featureIndex = report[2]
        let swID = report[3] & 0x0F
        let payload = Data(report.dropFirst(4))
        if let pending, pending.swID == swID || (swID == 0 && pending.featureIndex == featureIndex) {
            self.pending = nil
            consecutiveTimeouts = 0
            pending.completion(payload)
            return
        }
        if let batteryIndex, featureIndex == batteryIndex {
            applyBattery(payload)
        }
    }

    private func publish(_ mutate: (inout MXKeyboardSnapshot) -> Void) {
        lock.lock()
        mutate(&snapshot)
        lock.unlock()
    }
}
