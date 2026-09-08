#!/usr/bin/env swift
import Foundation
import IOKit.hid

/// BLE MX Master 4 Easy-Switch probe. Nested HID++ report 0x11, no seize.
/// Prefer usage page FF43, then FF00. Device index FF then 00.

final class Probe {
    private let vendorID = 0x046D
    private let productID = 0xB042
    private let softwareID: UInt8 = 0x05
    private var device: IOHIDDevice?
    private var buffer: UnsafeMutablePointer<UInt8>?
    private var pending: (([UInt8]?) -> Void)?
    private var pendingSW: UInt8 = 0
    private var pendingFeature: UInt8 = 0
    private var pendingIndex: UInt8 = 0
    private var deviceIndex: UInt8 = 0xFF
    private var queue: [() -> Void] = []
    private var busy = false

    func run() {
        log("HID MX Master 4 (B042):")
        let listed = listB042()
        guard let target = pickHIDPP(listed) else {
            log("no B042 collection with output reports")
            stop()
            return
        }
        let page = int(kIOHIDPrimaryUsagePageKey, target)
        let usage = int(kIOHIDPrimaryUsageKey, target)
        let name = string(kIOHIDProductKey, target) ?? "?"
        log(String(format: "opening %@ page=%04X usage=%04X (no seize)", name, page, usage))
        let kr = IOHIDDeviceOpen(target, IOOptionBits(kIOHIDOptionsTypeNone))
        log(String(format: "IOHIDDeviceOpen 0x%08X", kr))
        guard kr == kIOReturnSuccess else {
            stop()
            return
        }
        device = target
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 128)
        buffer = buf
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(target, buf, 128, { context, _, _, _, _, report, length in
            guard let context, length > 0 else { return }
            let bytes = Array(UnsafeBufferPointer(start: report, count: length))
            Unmanaged<Probe>.fromOpaque(context).takeUnretainedValue().handle(bytes)
        }, pointer)
        IOHIDDeviceScheduleWithRunLoop(target, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.probeIndices([0xFF, 0x00])
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
            self.log("probe timeout")
            self.stop()
        }
    }

    private func listB042() -> [IOHIDDevice] {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(mgr, [
            kIOHIDVendorIDKey as String: vendorID,
            kIOHIDProductIDKey as String: productID
        ] as CFDictionary)
        _ = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let copied = IOHIDManagerCopyDevices(mgr) else { return [] }
        var items: [IOHIDDevice] = []
        for case let item as IOHIDDevice in (copied as NSSet) {
            let name = string(kIOHIDProductKey, item) ?? "?"
            let page = int(kIOHIDPrimaryUsagePageKey, item)
            let usage = int(kIOHIDPrimaryUsageKey, item)
            let out = int(kIOHIDMaxOutputReportSizeKey, item)
            log(String(format: "  %@ page=%04X usage=%04X out=%d", name, page, usage, out))
            items.append(item)
        }
        return items
    }

    private func pickHIDPP(_ items: [IOHIDDevice]) -> IOHIDDevice? {
        let scored = items.compactMap { item -> (IOHIDDevice, Int)? in
            let page = int(kIOHIDPrimaryUsagePageKey, item)
            let out = int(kIOHIDMaxOutputReportSizeKey, item)
            guard out >= 20 else { return nil }
            let score: Int
            switch page {
            case 0xFF43: score = 3
            case 0xFF00: score = 2
            default: score = 1
            }
            return (item, score)
        }
        return scored.max(by: { $0.1 < $1.1 })?.0
    }

    private func probeIndices(_ indices: [UInt8]) {
        guard let index = indices.first else {
            log("no HID++ reply from MX4 BLE")
            stop()
            return
        }
        deviceIndex = index
        log(String(format: "trying device index %02X", index))
        call(feature: 0, function: 0, params: [0x00, 0x01]) { data in
            if data != nil {
                self.log("IRoot ok at index \(String(format: "%02X", index)) \(self.hex(data))")
                self.readHosts()
                return
            }
            self.probeIndices(Array(indices.dropFirst()))
        }
    }

    private func readHosts() {
        lookup(0x1814) { changeHost in
            self.log("CHANGE_HOST 0x1814 index=\(changeHost.map { String(format: "%02X", $0) } ?? "nil")")
            self.lookup(0x1815) { hostsInfo in
                self.log("HOSTS_INFO 0x1815 index=\(hostsInfo.map { String(format: "%02X", $0) } ?? "nil")")
                self.dumpChangeHost(changeHost) {
                    self.dumpHostsInfo(hostsInfo) {
                        self.log("done")
                        self.stop()
                    }
                }
            }
        }
    }

    private func dumpChangeHost(_ index: UInt8?, done: @escaping () -> Void) {
        guard let index, index != 0 else {
            done()
            return
        }
        call(feature: index, function: 0, params: []) { data in
            self.log("CHANGE_HOST fn0 \(self.hex(data))")
            if let data, data.count >= 2 {
                self.log("  hostCount=\(data[0]) current=\(data[1])")
            }
            done()
        }
    }

    private func dumpHostsInfo(_ index: UInt8?, done: @escaping () -> Void) {
        guard let index, index != 0 else {
            done()
            return
        }
        call(feature: index, function: 0, params: []) { data in
            self.log("HOSTS_INFO fn0 \(self.hex(data))")
            let count: Int
            if let data, data.count >= 4 {
                self.log(String(
                    format: "  flags=%02X desc=%02X count=%d current=%d",
                    data[0], data[1], data[2], data[3]
                ))
                count = Int(data[2])
            } else {
                count = 3
            }
            self.dumpHost(feature: index, host: 0, last: max(count - 1, 0), done: done)
        }
    }

    private func dumpHost(feature: UInt8, host: Int, last: Int, done: @escaping () -> Void) {
        if host > last {
            done()
            return
        }
        call(feature: feature, function: 1, params: [UInt8(host)]) { data in
            self.log("HOSTS_INFO fn1 host \(host) \(self.hex(data))")
            var nameLen = 0
            if let data, data.count >= 5 {
                let status = data.count > 1 ? data[1] : 0
                let bus = data.count > 2 ? data[2] : 0
                nameLen = Int(data[4])
                self.log("  status=\(status) bus=\(bus) nameLen=\(nameLen)")
            }
            self.readName(feature: feature, host: host, offset: 0, remaining: nameLen, assembled: "") {
                self.dumpHost(feature: feature, host: host + 1, last: last, done: done)
            }
        }
    }

    private func readName(
        feature: UInt8,
        host: Int,
        offset: Int,
        remaining: Int,
        assembled: String,
        done: @escaping () -> Void
    ) {
        if remaining <= 0 {
            self.log("  name=\(assembled.isEmpty ? "(empty)" : assembled)")
            done()
            return
        }
        call(feature: feature, function: 3, params: [UInt8(host), UInt8(offset)]) { data in
            self.log("HOSTS_INFO fn3 host \(host) off \(offset) \(self.hex(data))")
            var next = assembled
            if let data, data.count >= 3 {
                let take = min(remaining, 14, data.count - 2)
                var bytes = Array(data.dropFirst(2).prefix(take))
                while bytes.last == 0 { bytes.removeLast() }
                next += String(bytes: bytes, encoding: .utf8) ?? String(bytes.compactMap { byte -> Character? in
                    guard byte >= 32, byte < 127, let scalar = UnicodeScalar(UInt32(byte)) else { return nil }
                    return Character(scalar)
                })
            }
            let consumed = min(remaining, 14)
            if data == nil {
                self.log("  name=\(next.isEmpty ? "(empty/timeout)" : next)")
                done()
                return
            }
            self.readName(
                feature: feature,
                host: host,
                offset: offset + consumed,
                remaining: remaining - consumed,
                assembled: next,
                done: done
            )
        }
    }

    private func lookup(_ id: UInt16, completion: @escaping (UInt8?) -> Void) {
        call(feature: 0, function: 0, params: [UInt8(id >> 8), UInt8(id & 0xFF)]) { data in
            guard let data, let index = data.first, index != 0 else {
                completion(nil)
                return
            }
            completion(index)
        }
    }

    private func call(feature: UInt8, function: UInt8, params: [UInt8], completion: @escaping ([UInt8]?) -> Void) {
        enqueue {
            var report = [UInt8](repeating: 0, count: 20)
            report[0] = 0x11
            report[1] = self.deviceIndex
            report[2] = feature
            report[3] = (function << 4) | (self.softwareID & 0x0F)
            for (offset, byte) in params.prefix(16).enumerated() {
                report[4 + offset] = byte
            }
            self.pendingSW = self.softwareID
            self.pendingFeature = feature
            self.pendingIndex = self.deviceIndex
            self.pending = { reply in
                if let reply, reply.count >= 4 {
                    completion(Array(reply.dropFirst(4)))
                } else {
                    completion(reply)
                }
            }
            self.log("TX \(self.hex(report))")
            self.write(report)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                guard self.busy, self.pending != nil else { return }
                self.log(String(format: "timeout feat %02X fn%d", feature, function))
                let cb = self.pending
                self.pending = nil
                self.busy = false
                cb?(nil)
                self.pump()
            }
        }
    }

    private func handle(_ report: [UInt8]) {
        guard report.count >= 4 else { return }
        guard report[0] == 0x10 || report[0] == 0x11 else { return }
        log("RX* \(hex(report))")
        guard pending != nil, report[1] == pendingIndex else { return }
        if report[2] == 0x8F {
            let failed = report.count > 3 ? report[3] : 0
            let sw = report.count > 4 ? report[4] & 0x0F : 0
            if failed != pendingFeature || sw != pendingSW { return }
            log("HID++ error \(hex(report))")
            let cb = pending
            pending = nil
            busy = false
            cb?(nil)
            pump()
            return
        }
        let sw = report[3] & 0x0F
        if report[2] != pendingFeature || sw != pendingSW { return }
        let cb = pending
        pending = nil
        busy = false
        cb?(report)
        pump()
    }

    private func enqueue(_ work: @escaping () -> Void) {
        queue.append(work)
        pump()
    }

    private func pump() {
        guard !busy, let next = queue.first else { return }
        queue.removeFirst()
        busy = true
        next()
    }

    private func write(_ tx: [UInt8]) {
        guard let device, !tx.isEmpty else { return }
        _ = tx.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return kIOReturnError }
            return IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(tx[0]), base, tx.count)
        }
    }

    private func stop() {
        CFRunLoopStop(CFRunLoopGetMain())
    }

    private func log(_ line: String) {
        FileHandle.standardError.write(Data("\(line)\n".utf8))
        fflush(stderr)
    }

    private func hex(_ data: [UInt8]?) -> String {
        guard let data else { return "(nil)" }
        return data.prefix(20).map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private func string(_ key: String, _ device: IOHIDDevice) -> String? {
        IOHIDDeviceGetProperty(device, key as CFString) as? String
    }

    private func int(_ key: String, _ device: IOHIDDevice) -> Int {
        (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? 0
    }
}

let probe = Probe()
probe.run()
CFRunLoopRun()
