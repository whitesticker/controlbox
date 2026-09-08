#!/usr/bin/env swift
import Foundation
import IOKit.hid

/// One-shot HID++ probe: Bolt C548 vendor 0xFF00, then Easy-Switch host features
/// 0x1814 CHANGE_HOST and 0x1815 HOSTS_INFO. Never seizes. Never opens mouse/keyboard.

final class Probe {
    private let vendorID = 0x046D
    private let boltProductID = 0xC548
    private let hidppPage = 0xFF00
    private let softwareID: UInt8 = 0x05
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var buffer: UnsafeMutablePointer<UInt8>?
    private var pending: (([UInt8]?) -> Void)?
    private var pendingSW: UInt8 = 0
    private var pendingFeature: UInt8 = 0
    private var pendingIndex: UInt8 = 0
    private var queue: [() -> Void] = []
    private var busy = false

    func run() {
        listHID()
        guard attachBoltVendor() else {
            log("no C548 vendor HID++ collection")
            CFRunLoopStop(CFRunLoopGetMain())
            return
        }
        log("opened C548 vendor HID++ (no seize)")
        drainThen {
            self.readReceiverThenSlots()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 45) {
            self.log("probe timeout — stopping")
            CFRunLoopStop(CFRunLoopGetMain())
        }
    }

    private func listHID() {
        log("HID Logitech devices:")
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(mgr, [kIOHIDVendorIDKey as String: vendorID] as CFDictionary)
        _ = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        defer { IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone)) }
        guard let copied = IOHIDManagerCopyDevices(mgr) else {
            log("  (none)")
            return
        }
        for case let item as IOHIDDevice in (copied as NSSet) {
            let name = string(kIOHIDProductKey, item) ?? "?"
            let pid = int(kIOHIDProductIDKey, item)
            let page = int(kIOHIDPrimaryUsagePageKey, item)
            let usage = int(kIOHIDPrimaryUsageKey, item)
            let out = int(kIOHIDMaxOutputReportSizeKey, item)
            log(String(format: "  %@ pid=%04X page=%04X usage=%04X out=%d", name, pid, page, usage, out))
        }
    }

    private func attachBoltVendor() -> Bool {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(mgr, [
            kIOHIDVendorIDKey as String: vendorID,
            kIOHIDProductIDKey as String: boltProductID,
            kIOHIDDeviceUsagePageKey as String: hidppPage
        ] as CFDictionary)
        _ = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = mgr
        guard let copied = IOHIDManagerCopyDevices(mgr) else { return false }
        var vendor: IOHIDDevice?
        for case let item as IOHIDDevice in (copied as NSSet) {
            let page = int(kIOHIDPrimaryUsagePageKey, item)
            let out = int(kIOHIDMaxOutputReportSizeKey, item)
            if page == hidppPage, out >= 20 {
                vendor = item
                break
            }
        }
        guard let vendor else { return false }
        let kr = IOHIDDeviceOpen(vendor, IOOptionBits(kIOHIDOptionsTypeNone))
        log(String(format: "IOHIDDeviceOpen 0x%08X", kr))
        guard kr == kIOReturnSuccess else { return false }
        device = vendor
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 128)
        buffer = buf
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(vendor, buf, 128, { context, _, _, _, _, report, length in
            guard let context, length > 0 else { return }
            let bytes = Array(UnsafeBufferPointer(start: report, count: length))
            Unmanaged<Probe>.fromOpaque(context).takeUnretainedValue().handle(bytes)
        }, pointer)
        IOHIDDeviceScheduleWithRunLoop(vendor, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        return true
    }

    private func drainThen(_ next: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: next)
    }

    private func readReceiverThenSlots() {
        enableNotifications {
            self.shortGet(0x81, register: 0x02) { reply in
                self.log("short get 0x02 connection: \(self.hex(reply))")
            }
            self.longGet(0xB5, sub: 0x02) { reply in
                guard let reply else {
                    self.log("receiver info timeout")
                    self.finish()
                    return
                }
                self.log("receiver info B5:02 \(self.hex(reply))")
                self.readSlot(1, last: 6)
            }
        }
    }

    private func enableNotifications(then done: @escaping () -> Void) {
        shortGet(0x81, register: 0x00) { flags in
            self.log("receiver flags \(self.hex(flags))")
            guard let flags, flags.count > 6 else {
                done()
                return
            }
            let p0 = flags[4]
            let p1 = flags[5] | 0x08 | 0x01
            let p2 = flags[6]
            self.sendShort([0x10, 0xFF, 0x80, 0x00, p0, p1, p2], matchIndex: 0xFF, matchFeature: 0x80) { set in
                self.log("set flags \(self.hex(set)) p1=\(String(format: "%02X", p1))")
                done()
            }
        }
    }

    private func readSlot(_ slot: Int, last: Int) {
        if slot > last {
            finish()
            return
        }
        longGet(0xB5, sub: UInt8(0x50 + slot)) { record in
            if record == nil {
                self.log("slot \(slot) pairing timeout/empty")
                self.readSlot(slot + 1, last: last)
                return
            }
            let payload = Array(record!.dropFirst(4))
            let wpid = payload.count >= 3 ? Int(payload[1]) | (Int(payload[2]) << 8) : 0
            if wpid == 0 {
                self.log("slot \(slot) empty")
                self.readSlot(slot + 1, last: last)
                return
            }
            self.longGet(0xB5, sub: UInt8(0x60 + slot), p1: 0x01) { nameReply in
                let name = self.slotName(nameReply)
                self.log(String(format: "slot %d WPID %04X name=%@", slot, wpid, name))
                self.ping(slot: slot) { online in
                    if online {
                        self.log("slot \(slot) ping online")
                        self.probeHosts(slot: UInt8(slot), name: name) {
                            self.readSlot(slot + 1, last: last)
                        }
                        return
                    }
                    self.hidpp20(slot: UInt8(slot), feature: 0, function: 1, params: [0, 0, 0]) { ping in
                        let longOnline = ping != nil
                        self.log("slot \(slot) short ping failed; long ping \(longOnline ? "online" : "offline") \(self.hex(ping))")
                        guard longOnline else {
                            self.readSlot(slot + 1, last: last)
                            return
                        }
                        self.probeHosts(slot: UInt8(slot), name: name) {
                            self.readSlot(slot + 1, last: last)
                        }
                    }
                }
            }
        }
    }

    private func probeHosts(slot: UInt8, name: String, done: @escaping () -> Void) {
        log("— HID++ 2.0 hosts on slot \(slot) (\(name)) —")
        hidpp20(slot: slot, feature: 0, function: 0, params: [0x00, 0x01]) { root in
            self.log("  IRoot/FeatureSet \(self.hex(root))")
            self.lookup(slot: slot, id: 0x1814) { changeHost in
                self.log("  GetFeature 0x1814 CHANGE_HOST index=\(changeHost.map { String(format: "%02X", $0) } ?? "nil")")
                self.lookup(slot: slot, id: 0x1815) { hostsInfo in
                    self.log("  GetFeature 0x1815 HOSTS_INFO index=\(hostsInfo.map { String(format: "%02X", $0) } ?? "nil")")
                    self.dumpChangeHost(slot: slot, index: changeHost) {
                        self.dumpHostsInfo(slot: slot, index: hostsInfo) {
                            self.dumpHostsInfo(slot: slot, index: hostsInfo, done: done)
                        }
                    }
                }
            }
        }
    }

    private func dumpChangeHost(slot: UInt8, index: UInt8?, done: @escaping () -> Void) {
        guard let index, index != 0 else {
            done()
            return
        }
        hidpp20(slot: slot, feature: index, function: 0, params: []) { info in
            self.log("  CHANGE_HOST fn0 \(self.hex(info))")
            if let info, info.count >= 2 {
                self.log("    hostCount=\(info[0]) current=\(info[1]) caps=\(info.count > 2 ? String(format: "%02X", info[2]) : "--")")
            }
            done()
        }
    }

    private func dumpHostsInfo(slot: UInt8, index: UInt8?, done: @escaping () -> Void) {
        guard let index, index != 0 else {
            done()
            return
        }
        hidpp20(slot: slot, feature: index, function: 0, params: []) { info in
            self.log("  HOSTS_INFO fn0 \(self.hex(info))")
            let hostCount: Int
            if let info, info.count >= 4 {
                let flags = info[0]
                hostCount = Int(info[2])
                let current = Int(info[3])
                self.log("    flags=\(String(format: "%02X", flags)) desc=\(String(format: "%02X", info[1])) count=\(hostCount) current=\(current)")
            } else {
                self.log("    fn0 failed — still asking hosts 0-2")
                hostCount = 3
            }
            self.dumpHost(slot: slot, feature: index, host: 0, last: max(hostCount - 1, 0), done: done)
        }
    }

    private func dumpHost(slot: UInt8, feature: UInt8, host: Int, last: Int, done: @escaping () -> Void) {
        if host > last {
            done()
            return
        }
        hidpp20(slot: slot, feature: feature, function: 1, params: [UInt8(host)]) { info in
            self.log("  HOSTS_INFO fn1 host \(host) \(self.hex(info))")
            var nameLen = 0
            if let info, info.count >= 5 {
                let status = info.count > 1 ? info[1] : 0
                let bus = info.count > 2 ? info[2] : 0
                nameLen = Int(info[4])
                self.log("    status=\(status) bus=\(bus) nameLen=\(nameLen) max=\(info.count > 5 ? Int(info[5]) : -1)")
            }
            self.readName(slot: slot, feature: feature, host: host, offset: 0, remaining: nameLen, assembled: "") {
                self.hidpp20(slot: slot, feature: feature, function: 2, params: [UInt8(host), 0]) { desc in
                    self.log("  HOSTS_INFO fn2 host \(host) page0 \(self.hex(desc))")
                    self.dumpHost(slot: slot, feature: feature, host: host + 1, last: last, done: done)
                }
            }
        }
    }

    private func readName(
        slot: UInt8,
        feature: UInt8,
        host: Int,
        offset: Int,
        remaining: Int,
        assembled: String,
        done: @escaping () -> Void
    ) {
        if remaining <= 0 {
            self.log("    name fn3=\(assembled.isEmpty ? "(empty)" : assembled)")
            done()
            return
        }
        hidpp20(slot: slot, feature: feature, function: 3, params: [UInt8(host), UInt8(offset)]) { chunk in
            self.log("  HOSTS_INFO fn3 host \(host) off \(offset) \(self.hex(chunk))")
            var next = assembled
            if let chunk, chunk.count >= 3 {
                let take = min(remaining, 14, max(0, chunk.count - 2))
                let piece = Array(chunk.dropFirst(2).prefix(take)).filter { $0 != 0 }
                next += String(bytes: piece, encoding: .utf8) ?? self.ascii(piece)
            }
            let consumed = min(remaining, 14)
            if chunk == nil {
                self.log("    name fn3=\(next.isEmpty ? "(empty/timeout)" : next)")
                done()
                return
            }
            self.readName(
                slot: slot,
                feature: feature,
                host: host,
                offset: offset + consumed,
                remaining: remaining - consumed,
                assembled: next,
                done: done
            )
        }
    }

    private func lookup(slot: UInt8, id: UInt16, completion: @escaping (UInt8?) -> Void) {
        hidpp20(slot: slot, feature: 0, function: 0, params: [UInt8(id >> 8), UInt8(id & 0xFF)]) { data in
            guard let data, let index = data.first, index != 0 else {
                completion(nil)
                return
            }
            completion(index)
        }
    }

    private func ping(slot: Int, completion: @escaping (Bool) -> Void) {
        sendShort([0x10, UInt8(slot), 0x00, 0x1A, 0, 0, 0xAA], matchIndex: UInt8(slot), matchFeature: 0x00, timeout: 2.0) { reply in
            completion(reply != nil)
        }
    }

    private func shortGet(_ subID: UInt8, register: UInt8, completion: @escaping ([UInt8]?) -> Void) {
        sendShort([0x10, 0xFF, subID, register, 0, 0, 0], matchIndex: 0xFF, matchFeature: subID, completion: completion)
    }

    private func longGet(_ register: UInt8, sub: UInt8, p1: UInt8 = 0, completion: @escaping ([UInt8]?) -> Void) {
        sendShort([0x10, 0xFF, 0x83, register, sub, p1, 0], matchIndex: 0xFF, matchFeature: 0x83, timeout: 1.0, completion: completion)
    }

    private func hidpp20(slot: UInt8, feature: UInt8, function: UInt8, params: [UInt8], completion: @escaping ([UInt8]?) -> Void) {
        var report = [UInt8](repeating: 0, count: 20)
        report[0] = 0x11
        report[1] = slot
        report[2] = feature
        report[3] = (function << 4) | (softwareID & 0x0F)
        for (offset, byte) in params.prefix(16).enumerated() {
            report[4 + offset] = byte
        }
        enqueue {
            self.pendingSW = self.softwareID
            self.pendingFeature = feature
            self.pendingIndex = slot
            self.pending = { reply in
                if let reply, reply.count >= 4 {
                    completion(Array(reply.dropFirst(4)))
                } else {
                    completion(reply)
                }
            }
            self.write(report)
            self.log("TX \(self.hex(report))")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                guard self.busy, self.pending != nil else { return }
                self.log("  timeout waiting for slot \(slot) feat \(String(format: "%02X", feature)) fn\(function)")
                let cb = self.pending
                self.pending = nil
                self.busy = false
                cb?(nil)
                self.pump()
            }
        }
    }

    private func sendShort(
        _ tx: [UInt8],
        matchIndex: UInt8,
        matchFeature: UInt8,
        timeout: TimeInterval = 0.8,
        completion: @escaping ([UInt8]?) -> Void
    ) {
        enqueue {
            self.pendingSW = 0
            self.pendingFeature = matchFeature
            self.pendingIndex = matchIndex
            self.pending = completion
            self.write(tx)
            self.log("TX \(self.hex(tx))")
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                guard self.busy, self.pending != nil else { return }
                let cb = self.pending
                self.pending = nil
                self.busy = false
                cb?(nil)
                self.pump()
            }
        }
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

    private func handle(_ report: [UInt8]) {
        guard let first = report.first, first == 0x10 || first == 0x11 else { return }
        let bytes = report
        if bytes.count < 4 { return }
        log("RX* \(hex(bytes))")
        if pending == nil { return }
        if bytes[1] != pendingIndex { return }
        if pendingSW != 0 {
            if bytes[2] == 0x8F {
                let failedFeature = bytes.count > 3 ? bytes[3] : 0
                let sw = bytes.count > 4 ? bytes[4] & 0x0F : 0
                if failedFeature != pendingFeature || sw != pendingSW { return }
                log("RX \(hex(bytes))")
                let cb = pending
                pending = nil
                busy = false
                log("  HID++ error \(hex(bytes))")
                cb?(nil)
                pump()
                return
            }
            let sw = bytes[3] & 0x0F
            if bytes[2] != pendingFeature || sw != pendingSW { return }
            log("RX \(hex(bytes))")
            let cb = pending
            pending = nil
            busy = false
            cb?(bytes)
            pump()
            return
        }
        if bytes[2] == pendingFeature || bytes[2] == 0x8F {
            log("RX \(hex(bytes))")
            let cb = pending
            pending = nil
            busy = false
            cb?(bytes[2] == 0x8F ? nil : bytes)
            pump()
        }
    }

    private func slotName(_ reply: [UInt8]?) -> String {
        guard let reply, reply.count > 7 else { return "" }
        let length = Int(reply[6])
        let bytes = Array(reply.dropFirst(7).prefix(max(length, 0)))
        return ascii(bytes)
    }

    private func finish() {
        log("Bolt walk finished — probing BLE MX Master 3S")
        probeBLE3S {
            self.log("done")
            CFRunLoopStop(CFRunLoopGetMain())
        }
    }

    private var bleDevice: IOHIDDevice?
    private var bleBuffer: UnsafeMutablePointer<UInt8>?

    private func probeBLE3S(done: @escaping () -> Void) {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(mgr, [
            kIOHIDVendorIDKey as String: vendorID,
            kIOHIDProductIDKey as String: 0xB034,
            kIOHIDDeviceUsagePageKey as String: 0xFF43
        ] as CFDictionary)
        _ = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        var copied = IOHIDManagerCopyDevices(mgr)
        if copied == nil {
            IOHIDManagerSetDeviceMatching(mgr, [
                kIOHIDVendorIDKey as String: vendorID,
                kIOHIDProductIDKey as String: 0xB034
            ] as CFDictionary)
            copied = IOHIDManagerCopyDevices(mgr)
        }
        guard let copied else {
            log("no BLE B034")
            done()
            return
        }
        var hidpp: IOHIDDevice?
        for case let item as IOHIDDevice in (copied as NSSet) {
            let page = int(kIOHIDPrimaryUsagePageKey, item)
            let out = int(kIOHIDMaxOutputReportSizeKey, item)
            let name = string(kIOHIDProductKey, item) ?? "?"
            log(String(format: "  BLE B034 %@ page=%04X out=%d", name, page, out))
            if out >= 20, hidpp == nil || page == 0xFF43 {
                hidpp = item
            }
        }
        guard let hidpp else {
            log("no BLE 3S collection with output reports")
            done()
            return
        }
        let kr = IOHIDDeviceOpen(hidpp, IOOptionBits(kIOHIDOptionsTypeNone))
        log(String(format: "BLE open 0x%08X page=%04X", kr, int(kIOHIDPrimaryUsagePageKey, hidpp)))
        guard kr == kIOReturnSuccess else {
            done()
            return
        }
        bleDevice = hidpp
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 128)
        bleBuffer = buf
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(hidpp, buf, 128, { context, _, _, _, _, report, length in
            guard let context, length > 0 else { return }
            let bytes = Array(UnsafeBufferPointer(start: report, count: length))
            Unmanaged<Probe>.fromOpaque(context).takeUnretainedValue().handle(bytes)
        }, pointer)
        IOHIDDeviceScheduleWithRunLoop(hidpp, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        device = hidpp
        probeHosts(slot: 0xFF, name: "MX Master 3S BLE") {
            done()
        }
    }

    private func log(_ line: String) {
        FileHandle.standardError.write(Data("\(line)\n".utf8))
        fflush(stderr)
    }

    private func hex(_ data: [UInt8]?) -> String {
        guard let data else { return "(nil)" }
        return data.prefix(20).map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private func ascii(_ bytes: [UInt8]) -> String {
        String(bytes.compactMap { byte -> Character? in
            guard byte >= 32, byte < 127, let scalar = UnicodeScalar(UInt32(byte)) else { return nil }
            return Character(scalar)
        })
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
