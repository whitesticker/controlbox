import Foundation
import IOKit.hid

/// HID++ 1.0 pipe to one Bolt receiver vendor collection (`0xFF00` on `C548`).
/// Reply matching echoes subID, register, and sub-register so stale queued
/// reports cannot satisfy a later read. Never seize.
final class LogiBoltPipe {
    let id: String
    let serial: String
    let productName: String
    private let device: IOHIDDevice
    private var buffer: UnsafeMutablePointer<UInt8>?
    private var opened = false
    private var drainUntil = Date.distantPast
    private var queue: [Pending] = []
    private var pending: Pending?
    private var generation = 0

    var onNotification: (([UInt8]) -> Void)?
    var onRemoved: (() -> Void)?

    private struct Pending {
        let tx: [UInt8]
        let generation: Int
        let completion: (LogiBoltReply) -> Void
    }

    init?(device: IOHIDDevice) {
        guard LogiBoltSupport.isVendorHIDPP(device) else { return nil }
        self.device = device
        id = LogiBoltSupport.identity(of: device)
        serial = LogiBoltSupport.stringProperty(kIOHIDSerialNumberKey as String, device) ?? id
        productName = LogiBoltSupport.stringProperty(kIOHIDProductKey as String, device) ?? "USB Receiver"
    }

    deinit {
        close()
    }

    var isOpen: Bool { opened }

    func isSameDevice(_ other: IOHIDDevice) -> Bool {
        CFEqual(device, other)
    }

    func open() -> Bool {
        guard !opened else { return true }
        let kr = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard kr == kIOReturnSuccess else { return false }
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 128)
        buffer = buf
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(
            device,
            buf,
            128,
            { context, _, _, _, _, report, length in
                guard let context, length > 0 else { return }
                let bytes = Array(UnsafeBufferPointer(start: report, count: length))
                let pipe = Unmanaged<LogiBoltPipe>.fromOpaque(context).takeUnretainedValue()
                if Thread.isMainThread {
                    pipe.handleReport(bytes)
                } else {
                    DispatchQueue.main.async {
                        pipe.handleReport(bytes)
                    }
                }
            },
            pointer
        )
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        opened = true
        drainUntil = Date().addingTimeInterval(0.20)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            self?.pump()
        }
        return true
    }

    func close() {
        generation += 1
        if let pending {
            self.pending = nil
            pending.completion(.timeout)
        }
        let leftover = queue
        queue.removeAll()
        for item in leftover {
            item.completion(.timeout)
        }
        if let buf = buffer {
            IOHIDDeviceRegisterInputReportCallback(device, buf, 128, nil, nil)
            buf.deallocate()
            buffer = nil
        }
        if opened {
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        opened = false
    }

    func request(_ tx: [UInt8], timeout: TimeInterval = 0.45, completion: @escaping (LogiBoltReply) -> Void) {
        guard opened else {
            completion(.timeout)
            return
        }
        queue.append(Pending(tx: tx, generation: generation, completion: completion))
        pump()
        let gen = generation
        let signature = tx
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self, self.generation == gen else { return }
            if let pending = self.pending, pending.tx == signature {
                self.pending = nil
                pending.completion(.timeout)
                self.pump()
            }
        }
    }

    func getRegister(_ register: UInt8, sub: UInt8 = 0, p1: UInt8 = 0, completion: @escaping (LogiBoltReply) -> Void) {
        request([0x10, LogiBoltSupport.receiverIndex, 0x81, register, sub, p1, 0], completion: completion)
    }

    func setRegister(_ register: UInt8, p0: UInt8, p1: UInt8 = 0, p2: UInt8 = 0, completion: @escaping (LogiBoltReply) -> Void) {
        request([0x10, LogiBoltSupport.receiverIndex, 0x80, register, p0, p1, p2], completion: completion)
    }

    func getLongRegister(_ register: UInt8, sub: UInt8, p1: UInt8 = 0, timeout: TimeInterval = 0.9, completion: @escaping (LogiBoltReply) -> Void) {
        request([0x10, LogiBoltSupport.receiverIndex, 0x83, register, sub, p1, 0], timeout: timeout, completion: completion)
    }

    func setLongRegister(_ register: UInt8, payload: [UInt8], completion: @escaping (LogiBoltReply) -> Void) {
        var tx = [UInt8](repeating: 0, count: 20)
        tx[0] = 0x11
        tx[1] = LogiBoltSupport.receiverIndex
        tx[2] = 0x82
        tx[3] = register
        for (offset, byte) in payload.prefix(16).enumerated() {
            tx[4 + offset] = byte
        }
        request(tx, timeout: 1.0, completion: completion)
    }

    func ping(slot: Int, completion: @escaping (LogiBoltReply) -> Void) {
        request([0x10, UInt8(slot), 0x00, 0x1A, 0, 0, 0xAA], timeout: 0.9, completion: completion)
    }

    private func pump() {
        guard pending == nil, opened, Date() >= drainUntil, let next = queue.first else { return }
        queue.removeFirst()
        pending = next
        send(next.tx)
    }

    private func send(_ tx: [UInt8]) {
        guard opened, !tx.isEmpty else { return }
        let reportID = CFIndex(tx[0])
        _ = tx.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return kIOReturnError }
            return IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, reportID, base, tx.count)
        }
    }

    /// HID++ 2.0 to a device slot. Does not wait on the HID++ 1.0 register queue.
    func write(_ tx: [UInt8]) {
        send(tx)
    }

    private func handleReport(_ report: [UInt8]) {
        guard report.count >= 4 else { return }
        var bytes = report
        if bytes[0] != 0x10 && bytes[0] != 0x11 {
            return
        }
        let sub = bytes[2]
        if sub < 0x80 {
            onNotification?(bytes)
        }
        guard Date() >= drainUntil, let pending else { return }
        switch Self.match(bytes, pending.tx) {
        case 1:
            self.pending = nil
            pending.completion(.ok(bytes))
            pump()
        case 2:
            let code = bytes.count > 5 ? bytes[5] : 0
            self.pending = nil
            pending.completion(.error(code))
            pump()
        default:
            break
        }
    }

    /// 1 = success echo, 2 = HID++ error echo, 0 = unrelated (including stale).
    private static func match(_ rx: [UInt8], _ tx: [UInt8]) -> Int {
        guard rx.count >= 5, tx.count >= 4 else { return 0 }
        guard rx[1] == tx[1] else { return 0 }
        if rx[2] == 0x8F || rx[2] == 0xFF {
            return (rx[3] == tx[2] && rx[4] == tx[3]) ? 2 : 0
        }
        guard rx[2] == tx[2], rx[3] == tx[3] else { return 0 }
        let isRegisterRead = tx[2] == 0x81 || tx[2] == 0x83
        if isRegisterRead, rx.count > 4, tx.count > 4, rx[4] != tx[4] {
            return 0
        }
        return 1
    }
}
