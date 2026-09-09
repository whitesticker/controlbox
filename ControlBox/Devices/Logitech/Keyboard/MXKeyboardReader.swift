import Foundation
import ControlBoxCore
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
    private static let batteryInterval: TimeInterval = 300

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
    private var boltLink: LogiBoltHIDPPLink?
    private var queuedHIDPP: [IOHIDDevice] = []
    private var hidppBuffers: [ObjectIdentifier: UnsafeMutablePointer<UInt8>] = [:]
    private var featureCatalog = LogitechHIDPPFeatureCatalog()
    private var batteryIndex: UInt8?
    private var backlightIndex: UInt8?
    private var nameIndex: UInt8?
    private var hostsInfoIndex: UInt8?
    private var changeHostIndex: UInt8?
    private var backlightConfig: BacklightConfig?
    private var consecutiveTimeouts = 0
    private var easySwitchLoadAttempts = 0
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
        hidppClient.cancelAll()
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
        if let link = boltLink {
            link.onReport = nil
            boltLink = nil
        }
        queuedHIDPP.removeAll()
        clearFeatureIndices()
        lock.lock()
        snapshot = MXKeyboardSnapshot()
        lock.unlock()
    }

    var usesBluetoothHIDPP: Bool { hidppDevice != nil && boltLink == nil }

    var usesBoltHIDPP: Bool { boltLink != nil }

    var boltSlotID: String? { boltLink.map { "\($0.receiverID)-\($0.slot)" } }

    var hidppCapabilities: LogitechHIDPPCapabilities { featureCatalog.capabilities }

    private var canWriteHIDPP: Bool { hidppDevice != nil || boltLink != nil }

    private lazy var hidppClient: LogitechHIDPP2Client = {
        let client = LogitechHIDPP2Client(
            initialSoftwareID: 0x07,
            replyMatchPolicy: .softwareIDOrFeatureEvent,
            canWrite: { [weak self] in self?.canWriteHIDPP == true },
            write: { [weak self] report in
                self?.writeHIDPPReport(report)
            }
        )
        client.onReply = { [weak self] in
            self?.consecutiveTimeouts = 0
        }
        client.onTimeout = { [weak self] _ in
            guard let self else { return }
            self.lock.lock()
            let ready = self.snapshot.hidppReady
            self.lock.unlock()
            guard !ready else { return }
            self.consecutiveTimeouts += 1
            if self.consecutiveTimeouts >= 3 {
                self.failHIDPPAndTryNext(
                    "HID++ timed out. LogiPluginService can block this even after Options+ is removed."
                )
            }
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
        guard kind.isMXKeyboard else { return false }
        if hidppDevice != nil { return false }
        if boltLink?.id == link.id {
            lock.lock()
            let connected = snapshot.connected
            lock.unlock()
            if connected { return true }
        }
        detachBolt(restoreStatus: boltLink != nil)
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
        clearFeatureIndices()
        stopBatteryTimer()
        consecutiveTimeouts = 0
        hidppClient.deviceIndex = UInt8(link.slot)
        lock.lock()
        snapshot.kind = kind
        snapshot.name = name
        snapshot.product = name
        snapshot.address = address
        snapshot.connected = true
        snapshot.hidppReady = false
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
        detachBolt(restoreStatus: true)
    }

    private func detachBolt(restoreStatus: Bool) {
        guard boltLink != nil else { return }
        boltLink?.onReport = nil
        boltLink = nil
        hidppClient.cancelAll()
        stopBatteryTimer()
        clearFeatureIndices()
        lock.lock()
        snapshot = MXKeyboardSnapshot()
        lock.unlock()
        _ = restoreStatus
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
        if boltLink != nil {
            detachBolt()
        }
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
        hidppClient.cancelAll()
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
        snapshot.connection = .bluetooth
        snapshot.unitID = 0
        snapshot.wirelessProductID = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue ?? 0
        snapshot.status = "Talking to \(product) over HID++…"
        snapshot.easySwitchHosts = []
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
        hidppClient.deviceIndex = index
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
        loadEasySwitchHosts()
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
        guard let reading = LogitechUnifiedBatteryReading(payload: data) else { return }
        publish {
            $0.batteryAvailable = true
            $0.batteryPercent = reading.percentage
            $0.batteryCharging = reading.isCharging
            $0.batteryFull = reading.isFull
            $0.batteryStateDescription = reading.stateDescription
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
            params: LogitechHIDPP2.featureLookupParameters(feature)
        ) { [weak self] data in
            if let index = data?.first, index != 0 {
                self?.featureCatalog[feature] = index
                completion(index)
            } else {
                completion(nil)
            }
        }
    }

    private func loadEasySwitchHosts() {
        lookup(MXEasySwitchHIDPP.hostsInfoFeature) { [weak self] hostsInfo in
            guard let self else { return }
            self.hostsInfoIndex = hostsInfo
            self.lookup(MXEasySwitchHIDPP.changeHostFeature) { [weak self] changeHost in
                guard let self else { return }
                self.changeHostIndex = changeHost
                MXEasySwitchHIDPP.load(
                    hostsInfoIndex: self.hostsInfoIndex,
                    changeHostIndex: self.changeHostIndex,
                    request: { [weak self] feature, function, params, completion in
                        guard let self else {
                            completion(nil)
                            return
                        }
                        self.request(featureIndex: feature, function: function, params: params, completion: completion)
                    }
                ) { [weak self] hosts in
                    guard let self else { return }
                    self.publish { $0.easySwitchHosts = hosts }
                    self.lock.lock()
                    let ready = self.snapshot.hidppReady
                    self.lock.unlock()
                    if hosts.isEmpty, ready, self.easySwitchLoadAttempts < 1 {
                        self.easySwitchLoadAttempts += 1
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                            self?.loadEasySwitchHosts()
                        }
                    }
                }
            }
        }
    }

    func reloadEasySwitchHosts() {
        easySwitchLoadAttempts = 0
        loadEasySwitchHosts()
    }

    func setFriendlyName(_ name: String) {
        lock.lock()
        let ready = snapshot.hidppReady
        lock.unlock()
        guard ready else { return }
        lookup(MXFriendlyNameHIDPP.featureID) { [weak self] index in
            guard let self, let index else { return }
            MXFriendlyNameHIDPP.set(
                name: name,
                featureIndex: index,
                request: { [weak self] feature, function, params, completion in
                    guard let self else {
                        completion(nil)
                        return
                    }
                    self.request(featureIndex: feature, function: function, params: params, completion: completion)
                }
            ) { _ in }
        }
    }

    private func startBatteryTimer() {
        stopBatteryTimer()
        let timer = Timer(timeInterval: Self.batteryInterval, repeats: true) { [weak self] _ in
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

    private func failHIDPPAndTryNext(_ message: String) {
        hidppClient.cancelAll()
        stopBatteryTimer()
        ioQueue.sync {}
        if boltLink != nil {
            detachBolt()
            return
        }
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
        guard running, boltLink == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.scanHIDPP()
        }
        recoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    private func clearFeatureIndices() {
        featureCatalog.removeAll()
        batteryIndex = nil
        backlightIndex = nil
        nameIndex = nil
        hostsInfoIndex = nil
        changeHostIndex = nil
        backlightConfig = nil
        easySwitchLoadAttempts = 0
    }

    private func isSameDevice(_ lhs: IOHIDDevice, _ rhs: IOHIDDevice?) -> Bool {
        guard let rhs else { return false }
        return CFEqual(lhs, rhs)
    }

    private func request(featureIndex: UInt8, function: UInt8, params: [UInt8], completion: @escaping (Data?) -> Void) {
        hidppClient.request(
            featureIndex: featureIndex,
            function: function,
            parameters: params,
            completion: completion
        )
    }

    private func writeHIDPPReport(_ report: [UInt8]) {
        if let boltLink {
            boltLink.write(report)
        } else if let device = hidppDevice {
            ioQueue.async {
                _ = report.withUnsafeBufferPointer { buffer in
                    guard let base = buffer.baseAddress else { return kIOReturnError }
                    return IOHIDDeviceSetReport(
                        device,
                        kIOHIDReportTypeOutput,
                        CFIndex(report[0]),
                        base,
                        report.count
                    )
                }
            }
        }
    }

    private func handleReport(_ report: [UInt8]) {
        let result = hidppClient.handle(report)
        guard case let .event(incoming) = result else {
            return
        }
        if let batteryIndex, incoming.featureIndex == batteryIndex {
            applyBattery(incoming.payload)
        }
    }

    private func publish(_ mutate: (inout MXKeyboardSnapshot) -> Void) {
        lock.lock()
        mutate(&snapshot)
        lock.unlock()
    }
}
