import Foundation
import IOKit.hid

struct DualSenseHIDBatteryReading: Equatable {
    var percent: Int
    var isCharging: Bool
    var isFull: Bool
}

/// Shared DualSense HID battery nibble reader. Tracks each HID device separately
/// so two DualSenses do not overwrite one percentage.
final class DualSenseHIDBatteryReader {
    private var manager: IOHIDManager?
    private var buffers: [ObjectIdentifier: UnsafeMutablePointer<UInt8>] = [:]
    private var addresses: [ObjectIdentifier: String] = [:]
    private var readings: [ObjectIdentifier: DualSenseHIDBatteryReading] = [:]
    private let bufferSize = 128

    func start() {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [[String: Any]] = [
            [kIOHIDVendorIDKey as String: 0x054C, kIOHIDProductIDKey as String: 0x0CE6],
            [kIOHIDVendorIDKey as String: 0x054C, kIOHIDProductIDKey as String: 0x0DF2]
        ]
        IOHIDManagerSetDeviceMatchingMultiple(mgr, matching as CFArray)

        let pointer = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(mgr, { context, _, _, device in
            guard let context else { return }
            Unmanaged<DualSenseHIDBatteryReader>.fromOpaque(context).takeUnretainedValue().attach(device)
        }, pointer)
        IOHIDManagerRegisterDeviceRemovalCallback(mgr, { context, _, _, device in
            guard let context else { return }
            Unmanaged<DualSenseHIDBatteryReader>.fromOpaque(context).takeUnretainedValue().detach(device)
        }, pointer)

        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = mgr

        if let copied = IOHIDManagerCopyDevices(mgr) {
            let devices = copied as NSSet
            for case let device as IOHIDDevice in devices {
                attach(device)
            }
        }
    }

    func stop() {
        buffers.values.forEach { $0.deallocate() }
        buffers.removeAll()
        addresses.removeAll()
        readings.removeAll()
        if let manager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil
    }

    func reading(forAddress address: String?) -> DualSenseHIDBatteryReading? {
        if let address, DeviceIdentity.isConcrete(address) {
            if let id = addresses.first(where: { DeviceIdentity.same($0.value, address) })?.key {
                return readings[id]
            }
        }
        if readings.count == 1 {
            return readings.values.first
        }
        return nil
    }

    private func attach(_ device: IOHIDDevice) {
        let id = ObjectIdentifier(device)
        guard buffers[id] == nil else { return }

        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        buffer.initialize(repeating: 0, count: bufferSize)
        buffers[id] = buffer
        let hidAddress = DeviceIdentity.fromHID(device)
        if DeviceIdentity.isConcrete(hidAddress) {
            addresses[id] = hidAddress
        }

        let pointer = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(
            device,
            buffer,
            bufferSize,
            { context, _, sender, _, reportID, report, length in
                guard let context else { return }
                let reader = Unmanaged<DualSenseHIDBatteryReader>.fromOpaque(context).takeUnretainedValue()
                let deviceID = sender.map { pointer -> ObjectIdentifier in
                    ObjectIdentifier(Unmanaged<IOHIDDevice>.fromOpaque(pointer).takeUnretainedValue())
                }
                reader.parse(deviceID: deviceID, report: report, length: length, reportID: reportID)
            },
            pointer
        )
    }

    private func detach(_ device: IOHIDDevice) {
        let id = ObjectIdentifier(device)
        if let buffer = buffers.removeValue(forKey: id) {
            buffer.deallocate()
        }
        addresses[id] = nil
        readings[id] = nil
    }

    private func parse(
        deviceID: ObjectIdentifier?,
        report: UnsafePointer<UInt8>,
        length: CFIndex,
        reportID: UInt32
    ) {
        let count = Int(length)
        guard count > 0 else { return }
        let bytes = UnsafeBufferPointer(start: report, count: count)
        let first = bytes[0]
        let id = first == 0x01 || first == 0x31 ? first : UInt8(truncatingIfNeeded: reportID)

        let candidates: [Int]
        if id == 0x31 {
            candidates = [54, 55, 53]
        } else if id == 0x01 {
            candidates = [53, 54]
        } else {
            candidates = [53, 54, 55]
        }

        for offset in candidates where offset < count {
            let raw = bytes[offset]
            let level = Int(raw & 0x0F)
            guard level <= 10 else { continue }
            let reading = DualSenseHIDBatteryReading(
                percent: min(level * 10, 100),
                isCharging: (raw & 0x10) != 0,
                isFull: (raw & 0x20) != 0 || level >= 10
            )
            if let deviceID {
                readings[deviceID] = reading
            }
            return
        }
    }
}
