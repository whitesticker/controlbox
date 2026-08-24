// Derived from MonitorControl (MIT).
// Copyright © MonitorControl. @JoniVR, @theOneyouseek, @waydabber and others
// https://github.com/MonitorControl/MonitorControl
//
// Matching, dummy detection, and DDC/CI packet format follow that project.
// IOAVService is loaded from IOKit (not a public Swift type).

import CoreGraphics
import Darwin
import Foundation
import IOKit

enum Arm64DDC {
    static let i2cAddress: UInt8 = 0x37
    static let i2cDataAddress: UInt8 = 0x51
    static let maxMatchScore = 20
    private static let i2cLock = NSLock()

    struct IORegService {
        var edidUUID = ""
        var manufacturerID = ""
        var productName = ""
        var serialNumber: Int64 = 0
        var alphanumericSerialNumber = ""
        var location = ""
        var ioDisplayLocation = ""
        var service: OpaquePointer?
        var serviceLocation = 0
    }

    struct Match {
        var displayID: CGDirectDisplayID
        var service: OpaquePointer?
        var serviceLocation: Int
        var dummy: Bool
        var details: IORegService
        var matchScore: Int
    }

    static func serviceMatches(for displayIDs: [CGDirectDisplayID]) -> [Match] {
        let candidates = ioregServicesForMatching()
        var scored: [Int: [Match]] = [:]
        for displayID in displayIDs {
            for candidate in candidates {
                let score = matchScore(
                    displayID: displayID,
                    edidUUID: candidate.edidUUID,
                    ioDisplayLocation: candidate.ioDisplayLocation,
                    productName: candidate.productName,
                    serialNumber: candidate.serialNumber
                )
                scored[score, default: []].append(
                    Match(
                        displayID: displayID,
                        service: candidate.service,
                        serviceLocation: candidate.serviceLocation,
                        dummy: isDummy(candidate),
                        details: candidate,
                        matchScore: score
                    )
                )
            }
        }
        var takenLocations: [Int] = []
        var takenDisplays: [CGDirectDisplayID] = []
        var result: [Match] = []
        for score in stride(from: maxMatchScore, through: 1, by: -1) {
            for candidate in scored[score] ?? [] {
                if takenDisplays.contains(candidate.displayID) || takenLocations.contains(candidate.serviceLocation) {
                    continue
                }
                takenDisplays.append(candidate.displayID)
                takenLocations.append(candidate.serviceLocation)
                result.append(candidate)
            }
        }
        return result
    }

    static func read(service: OpaquePointer?, command: UInt8) -> (current: UInt16, max: UInt16)? {
        var send: [UInt8] = [command]
        var reply = [UInt8](repeating: 0, count: 11)
        guard transact(service: service, send: &send, reply: &reply) else { return nil }
        let max = UInt16(reply[6]) * 256 + UInt16(reply[7])
        let current = UInt16(reply[8]) * 256 + UInt16(reply[9])
        return (current, max)
    }

    static func write(service: OpaquePointer?, command: UInt8, value: UInt16) -> Bool {
        var send: [UInt8] = [command, UInt8(value >> 8), UInt8(value & 255)]
        var reply: [UInt8] = []
        return transact(service: service, send: &send, reply: &reply)
    }

    /// MonitorControl dummy EDID (AOC 28E850) plus BetterDisplay dummies.
    static func isDummy(_ service: IORegService) -> Bool {
        if service.manufacturerID == "AOC", service.productName == "28E850" { return true }
        if service.productName.lowercased().contains("dummy") { return true }
        return false
    }

    static func isDummyScreen(name: String, displayID: CGDirectDisplayID) -> Bool {
        if name.lowercased().contains("dummy") { return true }
        if isVirtual(displayID), CGDisplayVendorNumber(displayID) == 0xF0F0 { return true }
        return false
    }

    static func isVirtual(_ displayID: CGDirectDisplayID) -> Bool {
        guard let dictionary = CoreDisplayInfo.dictionary(displayID) else { return false }
        let virtual = dictionary["kCGDisplayIsVirtualDevice"] as? Bool
        let airPlay = dictionary["kCGDisplayIsAirPlay"] as? Bool
        return virtual ?? airPlay ?? false
    }

    private static func transact(
        service: OpaquePointer?,
        send: inout [UInt8],
        reply: inout [UInt8]
    ) -> Bool {
        guard service != nil else { return false }
        i2cLock.lock()
        defer { i2cLock.unlock() }
        var packet: [UInt8] = [UInt8(0x80 | (send.count + 1)), UInt8(send.count)] + send + [0]
        packet[packet.count - 1] = checksum(
            seed: send.count == 1 ? i2cAddress << 1 : i2cAddress << 1 ^ i2cDataAddress,
            bytes: packet,
            start: 0,
            end: packet.count - 2
        )
        for attempt in 0..<(4 + 1) {
            if attempt > 0 { usleep(20_000) }
            var ok = false
            for _ in 0..<2 {
                usleep(10_000)
                ok = packet.withUnsafeMutableBytes { buffer in
                    AVService.write(
                        service,
                        UInt32(i2cAddress),
                        UInt32(i2cDataAddress),
                        buffer.baseAddress,
                        UInt32(buffer.count)
                    )
                } == KERN_SUCCESS
            }
            if !reply.isEmpty {
                usleep(50_000)
                let readOK = reply.withUnsafeMutableBytes { buffer in
                    AVService.read(service, UInt32(i2cAddress), 0, buffer.baseAddress, UInt32(buffer.count))
                } == KERN_SUCCESS
                ok = readOK && checksum(seed: 0x50, bytes: reply, start: 0, end: reply.count - 2) == reply[reply.count - 1]
            }
            if ok { return true }
        }
        return false
    }

    private static func checksum(seed: UInt8, bytes: [UInt8], start: Int, end: Int) -> UInt8 {
        var value = seed
        for i in start...end { value ^= bytes[i] }
        return value
    }

    private static func matchScore(
        displayID: CGDirectDisplayID,
        edidUUID: String,
        ioDisplayLocation: String,
        productName: String,
        serialNumber: Int64
    ) -> Int {
        guard let dictionary = CoreDisplayInfo.dictionary(displayID) else { return 0 }
        var score = 0
        if let vendor = int64(dictionary, ["DisplayVendorID", "kDisplayVendorID"]),
           let product = int64(dictionary, ["DisplayProductID", "kDisplayProductID"]),
           let year = int64(dictionary, ["DisplayYearOfManufacture", "kDisplayYearOfManufacture"]),
           let week = int64(dictionary, ["DisplayWeekOfManufacture", "kDisplayWeekOfManufacture"]),
           let height = int64(dictionary, ["DisplayVerticalImageSize", "kDisplayVerticalImageSize"]),
           let width = int64(dictionary, ["DisplayHorizontalImageSize", "kDisplayHorizontalImageSize"]) {
            struct Needle { var key: String; var loc: Int }
            let clampedVendor = UInt16(max(0, min(vendor, 256 * 256 - 1)))
            let clampedProduct = UInt16(max(0, min(product, 256 * 256 - 1)))
            let needles = [
                Needle(key: String(format: "%04x", clampedVendor).uppercased(), loc: 0),
                Needle(
                    key: String(format: "%02x", UInt8((clampedProduct >> 0) & 0xFF))
                        + String(format: "%02x", UInt8((clampedProduct >> 8) & 0xFF)),
                    loc: 4
                ),
                Needle(
                    key: String(format: "%02x", UInt8(max(0, min(week, 255))))
                        + String(format: "%02x", UInt8(max(0, min(year - 1990, 255)))),
                    loc: 19
                ),
                Needle(
                    key: String(format: "%02x", UInt8(max(0, min(width / 10, 255))))
                        + String(format: "%02x", UInt8(max(0, min(height / 10, 255)))),
                    loc: 30
                )
            ]
            for needle in needles where needle.key != "0000"
                && needle.key == edidUUID.prefix(needle.loc + 4).suffix(4).uppercased() {
                score += 1
            }
        }
        if !ioDisplayLocation.isEmpty,
           let location = dictionary["IODisplayLocation"] as? String,
           location == ioDisplayLocation {
            score += 10
        }
        if !productName.isEmpty,
           let names = dictionary["DisplayProductName"] as? [String: String],
           let name = names["en_US"] ?? names.first?.value,
           name.lowercased() == productName.lowercased() {
            score += 1
        }
        if serialNumber != 0,
           let serial = int64(dictionary, ["DisplaySerialNumber", "kDisplaySerialNumber"]),
           serial == serialNumber {
            score += 1
        }
        return score
    }

    private static func int64(_ dictionary: NSDictionary, _ keys: [String]) -> Int64? {
        for key in keys {
            if let value = dictionary[key] as? Int64 { return value }
            if let value = dictionary[key] as? Int { return Int64(value) }
            if let value = dictionary[key] as? NSNumber { return value.int64Value }
        }
        return nil
    }

    private static func ioregServicesForMatching() -> [IORegService] {
        var serviceLocation = 0
        var collected: [IORegService] = []
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != 0 else { return [] }
        defer { IOObjectRelease(root) }
        var iterator: io_iterator_t = 0
        guard IORegistryEntryCreateIterator(
            root,
            kIOServicePlane,
            IOOptionBits(kIORegistryIterateRecursively),
            &iterator
        ) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var current = IORegService()
        let framebufferNames = ["AppleCLCD2", "IOMobileFramebufferShim"]
        while let hit = nextObject(in: &iterator, names: ["DCPAVServiceProxy"] + framebufferNames) {
            defer { IOObjectRelease(hit.entry) }
            if framebufferNames.contains(hit.name) {
                current = framebufferProperties(hit.entry)
                serviceLocation += 1
                current.serviceLocation = serviceLocation
            } else if hit.name == "DCPAVServiceProxy" {
                attachAVService(hit.entry, to: &current)
                collected.append(current)
            }
        }
        return collected
    }

    private static func nextObject(
        in iterator: inout io_iterator_t,
        names: [String]
    ) -> (name: String, entry: io_service_t)? {
        while true {
            let entry = IOIteratorNext(iterator)
            if entry == 0 { return nil }
            let name = registryName(entry)
            if names.contains(where: { name.contains($0) }) {
                return (name, entry)
            }
            IOObjectRelease(entry)
        }
    }

    private static func framebufferProperties(_ entry: io_service_t) -> IORegService {
        var service = IORegService()
        if let uuid = IORegistryEntryCreateCFProperty(
            entry,
            "EDID UUID" as CFString,
            kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively)
        )?.takeRetainedValue() as? String {
            service.edidUUID = uuid
        }
        service.ioDisplayLocation = registryPath(entry)
        if let attributes = dictionaryProperty(entry, "DisplayAttributes") {
            let product = (attributes["ProductAttributes"] as? [String: Any]) ?? [:]
            service.manufacturerID = (product["ManufacturerID"] as? String) ?? ""
            service.productName = (product["ProductName"] as? String)
                ?? (attributes["ProductName"] as? String)
                ?? ""
            service.serialNumber = Int64(intValue(product["SerialNumber"]))
            service.alphanumericSerialNumber = (product["AlphanumericSerialNumber"] as? String) ?? ""
        }
        return service
    }

    private static func attachAVService(_ entry: io_service_t, to service: inout IORegService) {
        let location = IORegistryEntryCreateCFProperty(
            entry,
            "Location" as CFString,
            kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively)
        )?.takeRetainedValue() as? String ?? ""
        service.location = location
        if location == "External" {
            service.service = AVService.create(kCFAllocatorDefault, entry)
        }
    }

    private static func dictionaryProperty(_ entry: io_service_t, _ key: String) -> [String: Any]? {
        IORegistryEntryCreateCFProperty(
            entry,
            key as CFString,
            kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively)
        )?.takeRetainedValue() as? [String: Any]
    }

    private static func intValue(_ value: Any?) -> Int {
        (value as? NSNumber)?.intValue ?? (value as? Int) ?? 0
    }

    private static func registryName(_ entry: io_registry_entry_t) -> String {
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: 128)
        defer { buffer.deallocate() }
        buffer.initialize(repeating: 0, count: 128)
        guard IORegistryEntryGetName(entry, buffer) == KERN_SUCCESS else { return "" }
        return String(cString: buffer)
    }

    private static func registryPath(_ entry: io_registry_entry_t) -> String {
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: 512)
        defer { buffer.deallocate() }
        buffer.initialize(repeating: 0, count: 512)
        guard IORegistryEntryGetPath(entry, kIOServicePlane, buffer) == KERN_SUCCESS else { return "" }
        return String(cString: buffer)
    }
}

private enum AVService {
    typealias Create = @convention(c) (CFAllocator?, io_service_t) -> OpaquePointer?
    typealias I2C = @convention(c) (OpaquePointer?, UInt32, UInt32, UnsafeMutableRawPointer?, UInt32) -> kern_return_t

    private static let createSymbol: Create? = load("IOAVServiceCreateWithService")
    private static let writeSymbol: I2C? = load("IOAVServiceWriteI2C")
    private static let readSymbol: I2C? = load("IOAVServiceReadI2C")

    static func create(_ allocator: CFAllocator?, _ service: io_service_t) -> OpaquePointer? {
        createSymbol?(allocator, service)
    }

    static func write(
        _ av: OpaquePointer?,
        _ chip: UInt32,
        _ dataAddress: UInt32,
        _ buffer: UnsafeMutableRawPointer?,
        _ length: UInt32
    ) -> kern_return_t {
        writeSymbol?(av, chip, dataAddress, buffer, length) ?? KERN_FAILURE
    }

    static func read(
        _ av: OpaquePointer?,
        _ chip: UInt32,
        _ dataAddress: UInt32,
        _ buffer: UnsafeMutableRawPointer?,
        _ length: UInt32
    ) -> kern_return_t {
        readSymbol?(av, chip, dataAddress, buffer, length) ?? KERN_FAILURE
    }

    private static func load<T>(_ name: String) -> T? {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY),
              let symbol = dlsym(handle, name) else {
            return nil
        }
        return unsafeBitCast(symbol, to: T.self)
    }
}

private enum CoreDisplayInfo {
    typealias Info = @convention(c) (CGDirectDisplayID) -> Unmanaged<CFDictionary>?
    private static let create: Info? = load("CoreDisplay_DisplayCreateInfoDictionary")

    static func dictionary(_ displayID: CGDirectDisplayID) -> NSDictionary? {
        create?(displayID)?.takeRetainedValue() as NSDictionary?
    }

    private static func load<T>(_ name: String) -> T? {
        guard let handle = dlopen(
            "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay",
            RTLD_LAZY
        ), let symbol = dlsym(handle, name) else {
            return nil
        }
        return unsafeBitCast(symbol, to: T.self)
    }
}
