import Foundation
import IOKit.hid

final class DualSenseHIDBatteryReader {
    private var manager: IOHIDManager?
    private var buffers: [ObjectIdentifier: UnsafeMutablePointer<UInt8>] = [:]
    private let bufferSize = 128

    private(set) var percent: Int?
    private(set) var isCharging = false
    private(set) var isFull = false

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
        if let manager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil
        percent = nil
        isCharging = false
        isFull = false
    }

    private func attach(_ device: IOHIDDevice) {
        let id = ObjectIdentifier(device)
        guard buffers[id] == nil else { return }

        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        buffer.initialize(repeating: 0, count: bufferSize)
        buffers[id] = buffer

        let pointer = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(
            device,
            buffer,
            bufferSize,
            { context, _, _, _, reportID, report, length in
                guard let context else { return }
                Unmanaged<DualSenseHIDBatteryReader>.fromOpaque(context).takeUnretainedValue()
                    .parse(report: report, length: length, reportID: reportID)
            },
            pointer
        )
    }

    private func detach(_ device: IOHIDDevice) {
        let id = ObjectIdentifier(device)
        if let buffer = buffers.removeValue(forKey: id) {
            buffer.deallocate()
        }
    }

    private func parse(report: UnsafePointer<UInt8>, length: CFIndex, reportID: UInt32) {
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
            percent = min(level * 10, 100)
            isCharging = (raw & 0x10) != 0
            isFull = (raw & 0x20) != 0 || level >= 10
            return
        }
    }
}
