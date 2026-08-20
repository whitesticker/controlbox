import Foundation
import IOKit.hid

struct AppleTVRemoteSnapshot: Equatable, Sendable {
    var connected = false
    var name = "Apple TV Remote"
    var product = "Siri Remote A2540"

    var back = false
    var tv = false
    var siri = false
    var mute = false
    var playPause = false
    var power = false
    var volumeUp = false
    var volumeDown = false
    var select = false
    var clickUp = false
    var clickDown = false
    var clickLeft = false
    var clickRight = false

    var lastHIDSignal = "Press a button"
    var lastHIDMappedName = "—"
    var lastRawReport = "No reports yet"

    var batteryPercent: Int?
    var batteryCharging = false
    var batteryFull = false
    var batteryAvailable = false
    var batteryStateDescription = "Unknown"

    var touchAvailable = false
    var touchActive = false
    var touchX: Float = 0.5
    var touchY: Float = 0.5
    var touchSize: Float = 0
    var touchFamilyID = 0
    var wheelActive = false
    var wheelDegrees: Double = 0
    var wheelAccumulated: Double = 0

    var hidReports = 0
    var hidButtonReports = 0
    var hidLargeReports = 0
    var micHIDPackets = 0
    var micActive = false
    var micLevel: Float = 0
    var micSource = "Idle — hold Siri to arm the host enable"
    var micArmLog = "Not armed yet"

    var events: [InputLogEvent] = []
}

final class AppleTVRemoteHIDReader {
    private struct AttachedDevice {
        let device: IOHIDDevice
        let buffer: UnsafeMutablePointer<UInt8>
        let usagePage: UInt32
        let usage: UInt32
        var seized = false
    }

    private var manager: IOHIDManager?
    private let lock = NSLock()
    private var deviceCount = 0
    private var buttons = AppleTVRemoteSnapshot()
    private var attached: [ObjectIdentifier: AttachedDevice] = [:]
    private let bufferSize = 512
    private var lastMicReport = Date.distantPast
    private var siriWasDown = false

    var snapshot: AppleTVRemoteSnapshot {
        lock.lock()
        defer { lock.unlock() }
        var copy = buttons
        copy.connected = deviceCount > 0
        if Date().timeIntervalSince(lastMicReport) > 0.35 {
            copy.micActive = false
            copy.micLevel = 0
        }
        return copy
    }

    func start() {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching = DeviceSupport.appleTVRemoteProductIDs.map { productID -> [String: Any] in
            [
                kIOHIDVendorIDKey as String: DeviceSupport.appleVendorID,
                kIOHIDProductIDKey as String: productID
            ]
        }
        IOHIDManagerSetDeviceMatchingMultiple(mgr, matching as CFArray)

        let pointer = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(mgr, { context, _, _, device in
            guard let context else { return }
            Unmanaged<AppleTVRemoteHIDReader>.fromOpaque(context).takeUnretainedValue().attach(device)
        }, pointer)
        IOHIDManagerRegisterDeviceRemovalCallback(mgr, { context, _, _, device in
            guard let context else { return }
            Unmanaged<AppleTVRemoteHIDReader>.fromOpaque(context).takeUnretainedValue().detach(device)
        }, pointer)
        IOHIDManagerRegisterInputValueCallback(mgr, { context, _, _, value in
            guard let context else { return }
            Unmanaged<AppleTVRemoteHIDReader>.fromOpaque(context).takeUnretainedValue().handle(value)
        }, pointer)

        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = mgr

        if let copied = IOHIDManagerCopyDevices(mgr) {
            for case let device as IOHIDDevice in (copied as NSSet) {
                attach(device)
            }
        }
    }

    func stop() {
        lock.lock()
        let devices = attached
        lock.unlock()
        for item in devices.values where item.seized {
            IOHIDDeviceClose(item.device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        }
        if let manager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil
        lock.lock()
        attached.values.forEach { $0.buffer.deallocate() }
        attached.removeAll()
        deviceCount = 0
        buttons = AppleTVRemoteSnapshot()
        siriWasDown = false
        lock.unlock()
    }

    func applyTouch(_ touch: AppleTVTouchSnapshot) {
        lock.lock()
        defer { lock.unlock() }
        buttons.touchAvailable = touch.available
        buttons.touchActive = touch.active
        buttons.touchX = touch.x
        buttons.touchY = touch.y
        buttons.touchSize = touch.size
        buttons.touchFamilyID = touch.familyID
        buttons.wheelActive = touch.wheelActive
        buttons.wheelDegrees = touch.wheelDegrees
        buttons.wheelAccumulated = touch.wheelAccumulated
    }

    func applyBatteryPercent(_ percent: Int) {
        lock.lock()
        defer { lock.unlock() }
        applyBatteryLevel(percent, nibble: false)
    }

    private func attach(_ device: IOHIDDevice) {
        let id = ObjectIdentifier(device)
        lock.lock()
        let already = attached[id] != nil
        if !already { deviceCount += 1 }
        lock.unlock()
        guard !already else { return }

        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        buffer.initialize(repeating: 0, count: bufferSize)
        let usagePage = uintProperty(kIOHIDPrimaryUsagePageKey, device)
        let usage = uintProperty(kIOHIDPrimaryUsageKey, device)
        let audio = usagePage == 0x0C && usage == 0x04
        let seized = audio && IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice)) == kIOReturnSuccess

        lock.lock()
        attached[id] = AttachedDevice(
            device: device,
            buffer: buffer,
            usagePage: usagePage,
            usage: usage,
            seized: seized
        )
        if audio {
            buttons.micArmLog = seized ? "Audio interface seized" : "Audio seize failed — driver still owns it"
        }
        lock.unlock()

        let pointer = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(
            device,
            buffer,
            bufferSize,
            { context, _, _, _, reportID, report, length in
                guard let context else { return }
                Unmanaged<AppleTVRemoteHIDReader>.fromOpaque(context).takeUnretainedValue()
                    .handleReport(reportID: reportID, report: report, length: length)
            },
            pointer
        )

        if audio {
            sendEnable(to: device)
        }
    }

    private func detach(_ device: IOHIDDevice) {
        let id = ObjectIdentifier(device)
        lock.lock()
        if let existing = attached.removeValue(forKey: id) {
            if existing.seized {
                IOHIDDeviceClose(existing.device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
            }
            existing.buffer.deallocate()
            deviceCount = max(0, deviceCount - 1)
        }
        lock.unlock()
    }

    private func handle(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let page = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let pressed = IOHIDValueGetIntegerValue(value) != 0
        let isButton = IOHIDElementGetLogicalMax(element) == 1
        let signal = Self.describe(page: page, usage: usage)
        let mapped = Self.mappedName(page: page, usage: usage)

        var siriRising = false
        var siriFalling = false
        lock.lock()
        if pressed, isButton {
            buttons.lastHIDSignal = signal
            buttons.lastHIDMappedName = mapped
        }
        switch (page, usage) {
        case (0x0C, 0x60): buttons.tv = pressed
        case (0x0C, 0xE9): buttons.volumeUp = pressed
        case (0x0C, 0xEA): buttons.volumeDown = pressed
        case (0x0C, 0x80): buttons.select = pressed
        case (0x0C, 0x30): buttons.power = pressed
        case (0x0C, 0x04):
            buttons.siri = pressed
            siriRising = pressed && !siriWasDown
            siriFalling = !pressed && siriWasDown
            siriWasDown = pressed
        case (0x01, 0x86): buttons.back = pressed
        case (0x0C, 0xE2): buttons.mute = pressed
        case (0x0C, 0xCD): buttons.playPause = pressed
        case (0x0C, 0x42): buttons.clickUp = pressed
        case (0x0C, 0x43): buttons.clickDown = pressed
        case (0x0C, 0x44): buttons.clickLeft = pressed
        case (0x0C, 0x45): buttons.clickRight = pressed
        case (0x84, 0x20), (0x84, 0x30):
            applyBatteryLevel(Int(IOHIDValueGetIntegerValue(value)), nibble: true)
        default: break
        }
        let devices = attached.values.map(\.device)
        lock.unlock()

        if siriRising {
            armMicrophone(devices)
        } else if siriFalling {
            disarmMicrophone(devices)
        }
    }

    private func handleReport(reportID: UInt32, report: UnsafePointer<UInt8>, length: CFIndex) {
        guard length > 0 else { return }
        let bytes = UnsafeBufferPointer(start: report, count: Int(length))
        let hex = bytes.prefix(12).map { String(format: "%02X", $0) }.joined(separator: " ")

        lock.lock()
        defer { lock.unlock() }
        buttons.hidReports += 1
        if length <= 4 {
            buttons.hidButtonReports += 1
        }
        if length > 16 {
            buttons.hidLargeReports += 1
        }
        buttons.lastRawReport = String(format: "id %u len %ld  %@", reportID, length, hex)

        let siriDown = buttons.siri
        let looksLikeAudio = length >= 80 || reportID == 0xFA || reportID == 0xFF && length > 16
        if looksLikeAudio {
            lastMicReport = Date()
            buttons.micHIDPackets += 1
            buttons.micActive = true
            buttons.micSource = siriDown ? "Large HID report while Siri held" : "Large HID report"
            let sampleCount = min(bytes.count, 48)
            var total: Float = 0
            let start = min(2, sampleCount)
            if sampleCount > start {
                for index in start..<sampleCount {
                    total += Float(bytes[index])
                }
                buttons.micLevel = min(total / Float(sampleCount - start) / 255, 1)
            }
        }
        if reportID == 0xFF || length > 8 {
            for offset in 0..<min(bytes.count, 8) {
                let value = Int(bytes[offset])
                if (1...100).contains(value) {
                    applyBatteryLevel(value, nibble: false)
                    break
                }
            }
        }
    }

    private func armMicrophone(_ devices: [IOHIDDevice]) {
        var log: [String] = []
        for device in devices {
            let id = ObjectIdentifier(device)
            lock.lock()
            let usagePage = attached[id]?.usagePage ?? 0
            let usage = attached[id]?.usage ?? 0
            let alreadySeized = attached[id]?.seized ?? false
            lock.unlock()

            if !alreadySeized, usagePage == 0x0C, usage == 0x04 {
                let kr = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
                log.append("seize \(Self.hex(kr))")
                if kr == kIOReturnSuccess {
                    lock.lock()
                    if var item = attached[id] {
                        item.seized = true
                        attached[id] = item
                    }
                    lock.unlock()
                }
            }

            setNumberProperty("PushToTalk", 1, on: device)
            log.append("featFF \(Self.hex(setReport(device, type: kIOHIDReportTypeFeature, id: 0xFF, bytes: [0xAF])))")
            log.append("feat0 \(Self.hex(setReport(device, type: kIOHIDReportTypeFeature, id: 0, bytes: [0xAF])))")
            log.append("outFF \(Self.hex(setReport(device, type: kIOHIDReportTypeOutput, id: 0xFF, bytes: [0xAF])))")
            if usagePage == 0xFF00 {
                log.append("ptt99 \(Self.hex(setReport(device, type: kIOHIDReportTypeFeature, id: 0x99, bytes: [0x01])))")
            }
        }
        lock.lock()
        buttons.micSource = "Siri down — sent host enable"
        buttons.micArmLog = log.prefix(8).joined(separator: " · ")
        lock.unlock()
    }

    private func disarmMicrophone(_ devices: [IOHIDDevice]) {
        for device in devices {
            setNumberProperty("PushToTalk", 0, on: device)
            _ = setReport(device, type: kIOHIDReportTypeFeature, id: 0x99, bytes: [0x00])
        }
        lock.lock()
        buttons.micSource = "Siri up — PTT released"
        lock.unlock()
    }

    private func sendEnable(to device: IOHIDDevice) {
        _ = setReport(device, type: kIOHIDReportTypeFeature, id: 0xFF, bytes: [0xAF])
    }

    private func setReport(
        _ device: IOHIDDevice,
        type: IOHIDReportType,
        id: UInt32,
        bytes: [UInt8]
    ) -> IOReturn {
        var payload = bytes
        let count = payload.count
        return payload.withUnsafeMutableBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return kIOReturnError }
            return IOHIDDeviceSetReport(device, type, CFIndex(id), base, count)
        }
    }

    private func setNumberProperty(_ key: String, _ value: Int, on device: IOHIDDevice) {
        let number = NSNumber(value: value)
        IOHIDDeviceSetProperty(device, key as CFString, number)
        let service = IOHIDDeviceGetService(device)
        if service != 0 {
            IORegistryEntrySetCFProperty(service, key as CFString, number)
        }
    }

    private static func describe(page: UInt32, usage: UInt32) -> String {
        String(format: "page 0x%X  usage 0x%X", page, usage)
    }

    private static func mappedName(page: UInt32, usage: UInt32) -> String {
        switch (page, usage) {
        case (0x0C, 0x60): return "TV"
        case (0x0C, 0xE9): return "Volume Up"
        case (0x0C, 0xEA): return "Volume Down"
        case (0x0C, 0x80): return "Select"
        case (0x0C, 0x30): return "Power"
        case (0x0C, 0x04): return "Siri"
        case (0x01, 0x86): return "Back"
        case (0x0C, 0xE2): return "Mute"
        case (0x0C, 0xCD): return "Play/Pause"
        case (0x0C, 0x42): return "Clickpad Up"
        case (0x0C, 0x43): return "Clickpad Down"
        case (0x0C, 0x44): return "Clickpad Left"
        case (0x0C, 0x45): return "Clickpad Right"
        default: return "Unmapped"
        }
    }

    private static func hex(_ value: IOReturn) -> String {
        String(format: "0x%X", UInt32(bitPattern: Int32(value)))
    }

    private func applyBatteryLevel(_ value: Int, nibble: Bool) {
        let percent: Int
        if nibble, (0...10).contains(value) {
            percent = min(value * 10, 100)
        } else if (0...100).contains(value) {
            percent = value
        } else {
            return
        }
        buttons.batteryAvailable = true
        buttons.batteryPercent = percent
        buttons.batteryFull = percent >= 95
        buttons.batteryStateDescription = buttons.batteryFull ? "Full" : "Discharging"
    }

    private func uintProperty(_ key: String, _ device: IOHIDDevice) -> UInt32 {
        if let number = IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber {
            return number.uint32Value
        }
        return 0
    }
}
