import CoreBluetooth
import Foundation
import IOKit

final class AppleTVBatteryReader: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var central: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private let lock = NSLock()
    private var blePercent: Int?

    func start() {
        central = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionShowPowerAlertKey: false]
        )
    }

    func stop() {
        central = nil
        peripherals.removeAll()
        lock.lock()
        blePercent = nil
        lock.unlock()
    }

    func percent(serial: String, address: String) -> Int? {
        lock.lock()
        let ble = blePercent
        lock.unlock()
        if let ble { return ble }
        return registryPercent(serial: serial, address: address)
    }

    func refresh() {
        guard let central, central.state == .poweredOn else { return }
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

    private func registryPercent(serial: String, address: String) -> Int? {
        var iterator = io_iterator_t()
        let options = IOOptionBits(kIORegistryIterateRecursively)
        guard IORegistryCreateIterator(kIOMainPortDefault, kIOServicePlane, options, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        let needleSerial = serial.uppercased()
        let needleAddress = address
            .uppercased()
            .replacingOccurrences(of: ":", with: "-")

        var object = IOIteratorNext(iterator)
        while object != 0 {
            defer {
                IOObjectRelease(object)
                object = IOIteratorNext(iterator)
            }

            let product = stringProperty("Product", object) ?? stringProperty("Bluetooth Product Name", object) ?? ""
            let serialValue = stringProperty("SerialNumber", object) ?? ""
            let deviceAddress = (stringProperty("DeviceAddress", object) ?? "")
                .uppercased()
                .replacingOccurrences(of: ":", with: "-")

            let matchesName = product.uppercased() == needleSerial || serialValue.uppercased() == needleSerial
            let matchesAddress = !needleAddress.isEmpty && deviceAddress == needleAddress
            guard matchesName || matchesAddress else { continue }

            if let percent = intProperty("BatteryPercent", object) ?? intProperty("BatteryLevel", object) {
                if (0...100).contains(percent) { return percent }
            }
        }
        return nil
    }

    private func stringProperty(_ key: String, _ object: io_object_t) -> String? {
        guard let unmanaged = IORegistryEntryCreateCFProperty(object, key as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }
        return unmanaged.takeRetainedValue() as? String
    }

    private func intProperty(_ key: String, _ object: io_object_t) -> Int? {
        guard let unmanaged = IORegistryEntryCreateCFProperty(object, key as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }
        let value = unmanaged.takeRetainedValue()
        if let number = value as? NSNumber { return number.intValue }
        if let number = value as? Int { return number }
        return nil
    }
}
