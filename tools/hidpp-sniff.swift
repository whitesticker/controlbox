import Foundation
import IOKit.hid

final class BLESniffer: NSObject {
    private var manager: IOHIDManager?
    private var devices: [IOHIDDevice] = []
    private var buffers: [ObjectIdentifier: UnsafeMutablePointer<UInt8>] = [:]
    private let started = Date()

    func start() {
        log("watching MX Master 4 BLE (no seize)")
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatchingMultiple(mgr, [[
            kIOHIDVendorIDKey as String: 0x046D,
            kIOHIDProductIDKey as String: 0xB042
        ]] as CFArray)
        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        _ = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = mgr
        guard let copied = IOHIDManagerCopyDevices(mgr) else {
            log("no B042 devices")
            return
        }
        var seen: [IOHIDDevice] = []
        for case let item as IOHIDDevice in (copied as NSSet) {
            let name = (IOHIDDeviceGetProperty(item, kIOHIDProductKey as CFString) as? String) ?? "?"
            let page = (IOHIDDeviceGetProperty(item, kIOHIDPrimaryUsagePageKey as CFString) as? NSNumber)?.intValue ?? 0
            let usage = (IOHIDDeviceGetProperty(item, kIOHIDPrimaryUsageKey as CFString) as? NSNumber)?.intValue ?? 0
            log(String(format: "  %@ page=%04X usage=%04X", name, page, usage))
            seen.append(item)
        }
        if let first = seen.first {
            attach(first)
        }
        log("READY — press haptic, then back/forward, then hold haptic and move")
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { CFRunLoopStop(CFRunLoopGetMain()) }
    }

    private func attach(_ device: IOHIDDevice) {
        if devices.contains(where: { CFEqual($0, device) }) { return }
        let kr = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        log(String(format: "open 0x%08X", kr))
        guard kr == kIOReturnSuccess else { return }
        devices.append(device)
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
        buffers[ObjectIdentifier(device)] = buffer
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, { context, _, _, _, _, report, length in
            guard let context else { return }
            let bytes = Array(UnsafeBufferPointer(start: report, count: length))
            Unmanaged<BLESniffer>.fromOpaque(context).takeUnretainedValue().handle(bytes)
        }, pointer)
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        ping(device)
    }

    private func ping(_ device: IOHIDDevice) {
        // HID++ long report on report ID 0x11, device index FF then 00.
        for index in [UInt8(0xFF), 0x00] {
            var report: [UInt8] = [0x11, index, 0x00, 0x09, 0x00, 0x01]
            report += [UInt8](repeating: 0, count: 20 - report.count)
            _ = report.withUnsafeBufferPointer { buf in
                IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0x11, buf.baseAddress!, 20)
            }
            log("TX \(hex(report))")
        }
    }

    private func handle(_ report: [UInt8]) {
        guard let id = report.first else { return }
        if id == 0x02, report.count >= 2 {
            let buttons = report[1]
            let names = (0..<7).compactMap { buttons & (1 << $0) != 0 ? "b\($0 + 1)" : nil }
            let down = names.isEmpty ? "up" : names.joined(separator: "+")
            if buttons != 0 || lastButtons != 0 {
                log(String(format: "MOUSE buttons %02X [%@]  %@", buttons, down, hex(report)))
            }
            lastButtons = buttons
            return
        }
        log("HID \(hex(report))")
    }

    private var lastButtons: UInt8 = 0

    private func log(_ line: String) {
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        FileHandle.standardError.write(Data(String(format: "[%5d] %@\n", ms, line).utf8))
        fflush(stderr)
    }

    private func hex(_ data: [UInt8]) -> String {
        data.prefix(20).map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

let sniffer = BLESniffer()
sniffer.start()
CFRunLoopRun()
