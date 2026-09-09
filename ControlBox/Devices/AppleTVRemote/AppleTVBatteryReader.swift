import CoreBluetooth
import Foundation
import IOKit

/// BLE Battery Service first; IORegistry only as a throttled fallback.
/// Do not walk the registry on the 120 Hz device poll — that pegs a core.
final class AppleTVBatteryReader: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var central: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private let lock = NSLock()
    private let registryQueue = DispatchQueue(label: "controlbox.appletv-battery")
    private var blePercent: Int?
    private var registryPercent: Int?
    private var lastBLERefresh = Date.distantPast
    private var lastRegistryProbe = Date.distantPast
    private var lastSerial = ""
    private var lastAddress = ""
    private var registryProbeInFlight = false
    private var stopped = true

    private static let bleRefreshInterval: TimeInterval = 8
    private static let registryInterval: TimeInterval = 15

    func start() {
        lock.lock()
        stopped = false
        lock.unlock()
        central = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionShowPowerAlertKey: false]
        )
    }

    func stop() {
        lock.lock()
        stopped = true
        blePercent = nil
        registryPercent = nil
        lastBLERefresh = .distantPast
        lastRegistryProbe = .distantPast
        lastSerial = ""
        lastAddress = ""
        registryProbeInFlight = false
        lock.unlock()
        central = nil
        peripherals.removeAll()
    }

    func percent(serial: String, address: String) -> Int? {
        lock.lock()
        let live = !stopped
        lock.unlock()
        guard live else { return nil }
        refreshBLEIfNeeded()
        scheduleRegistryProbe(serial: serial, address: address)
        lock.lock()
        defer { lock.unlock() }
        return blePercent ?? registryPercent
    }

    func refresh() {
        lock.lock()
        let live = !stopped
        lock.unlock()
        guard live, let central, central.state == .poweredOn else { return }
        let battery = CBUUID(string: "180F")
        let found = central.retrieveConnectedPeripherals(withServices: [battery])
            + central.retrieveConnectedPeripherals(withServices: [CBUUID(string: "180A")])
        for peripheral in found {
            peripherals[peripheral.identifier] = peripheral
            peripheral.delegate = self
            peripheral.discoverServices([battery])
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            refresh()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else { return }
        for service in peripheral.services ?? [] where service.uuid == CBUUID(string: "180F") {
            peripheral.discoverCharacteristics([CBUUID(string: "2A19")], for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard error == nil else { return }
        for characteristic in service.characteristics ?? [] where characteristic.uuid == CBUUID(string: "2A19") {
            peripheral.readValue(for: characteristic)
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil, characteristic.uuid == CBUUID(string: "2A19"),
              let data = characteristic.value, let byte = data.first else { return }
        let value = Int(byte)
        guard (0...100).contains(value) else { return }
        lock.lock()
        blePercent = value
        lock.unlock()
    }

    private func refreshBLEIfNeeded() {
        lock.lock()
        let due = Date().timeIntervalSince(lastBLERefresh) >= Self.bleRefreshInterval
        if due { lastBLERefresh = Date() }
        lock.unlock()
        guard due else { return }
        if Thread.isMainThread {
            refresh()
        } else {
            DispatchQueue.main.async { [weak self] in self?.refresh() }
        }
    }

    private func scheduleRegistryProbe(serial: String, address: String) {
        lock.lock()
        if serial != lastSerial || address != lastAddress {
            lastSerial = serial
            lastAddress = address
            lastRegistryProbe = .distantPast
            registryPercent = nil
        }
        let ble = blePercent
        let due = Date().timeIntervalSince(lastRegistryProbe) >= Self.registryInterval
        let shouldScan = !stopped
            && ble == nil
            && due
            && !registryProbeInFlight
            && (!serial.isEmpty || !address.isEmpty)
        if shouldScan {
            registryProbeInFlight = true
            lastRegistryProbe = Date()
        }
        lock.unlock()
        guard shouldScan else { return }

        registryQueue.async { [weak self] in
            guard let self else { return }
            let value = Self.scanRegistry(serial: serial, address: address)
            self.lock.lock()
            self.registryProbeInFlight = false
            if !self.stopped, self.lastSerial == serial, self.lastAddress == address {
                self.registryPercent = value
            }
            self.lock.unlock()
        }
    }

    private static func scanRegistry(serial: String, address: String) -> Int? {
        let needleSerial = serial.uppercased()
        let needleAddress = address
            .uppercased()
            .replacingOccurrences(of: ":", with: "-")
        guard !needleSerial.isEmpty || !needleAddress.isEmpty else { return nil }

        var iterator = io_iterator_t()
        let options = IOOptionBits(kIORegistryIterateRecursively)
        guard IORegistryCreateIterator(kIOMainPortDefault, kIOServicePlane, options, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var object = IOIteratorNext(iterator)
        while object != 0 {
            defer {
                IOObjectRelease(object)
                object = IOIteratorNext(iterator)
            }

            let product = stringProperty("Product", object)
                ?? stringProperty("Bluetooth Product Name", object)
                ?? ""
            let serialValue = stringProperty("SerialNumber", object) ?? ""
            let deviceAddress = (stringProperty("DeviceAddress", object) ?? "")
                .uppercased()
                .replacingOccurrences(of: ":", with: "-")

            let matchesName = !needleSerial.isEmpty
                && (product.uppercased() == needleSerial || serialValue.uppercased() == needleSerial)
            let matchesAddress = !needleAddress.isEmpty && deviceAddress == needleAddress
            guard matchesName || matchesAddress else { continue }

            if let percent = intProperty("BatteryPercent", object) ?? intProperty("BatteryLevel", object) {
                if (0...100).contains(percent) { return percent }
            }
        }
        return nil
    }

    private static func stringProperty(_ key: String, _ object: io_object_t) -> String? {
        guard let unmanaged = IORegistryEntryCreateCFProperty(object, key as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }
        return unmanaged.takeRetainedValue() as? String
    }

    private static func intProperty(_ key: String, _ object: io_object_t) -> Int? {
        guard let unmanaged = IORegistryEntryCreateCFProperty(object, key as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }
        let value = unmanaged.takeRetainedValue()
        if let number = value as? NSNumber { return number.intValue }
        if let number = value as? Int { return number }
        return nil
    }
}
