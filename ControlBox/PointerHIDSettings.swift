import Foundation
import IOKit.hid
import ControlBoxCore

/// Applies MX pointer speed the way LinearMouse / Mac Mouse Fix do:
/// `HIDPointerResolution` (lower = faster) plus `HIDMouseAcceleration`
/// (System Settings tracking speed). The acceleration curve is not a
/// separate control; it is how macOS implements pointer speed.
enum PointerHIDSettings {
    static func apply(to device: IOHIDDevice, dpi: Int, pointerSpeed: Double) {
        let slider = min(max(pointerSpeed, 0), 1)
        let resolutionFixed = ioFixed(resolution(slider: slider, dpi: dpi))
        let accelerationFixed = ioFixed(acceleration(slider: slider, dpi: dpi))
        IOHIDDeviceSetProperty(device, kIOHIDPointerResolutionKey as CFString, NSNumber(value: resolutionFixed))
        IOHIDDeviceSetProperty(device, kIOHIDPointerAccelerationKey as CFString, NSNumber(value: accelerationFixed))
        IOHIDDeviceSetProperty(device, kIOHIDMouseAccelerationTypeKey as CFString, NSNumber(value: accelerationFixed))
        applyToMatchingServices(
            device: device,
            resolutionFixed: resolutionFixed,
            accelerationFixed: accelerationFixed
        )
    }

    /// Lower resolution is faster. 400 is the macOS default at 1× / 1000 DPI.
    /// Do not clamp to LinearMouse’s 1995 ceiling — that left high DPI too fast.
    private static func resolution(slider: Double, dpi: Int) -> Double {
        let factor = MappingProfile.pointerSpeedFactor(slider: slider, dpi: dpi)
        return min(max(400.0 / max(factor, 0.002), 10), 30_000)
    }

    /// Tracking speed follows the same factor. ~0.69 is the macOS default at 1×.
    private static func acceleration(slider: Double, dpi: Int) -> Double {
        let factor = MappingProfile.pointerSpeedFactor(slider: slider, dpi: dpi)
        return min(max(0.6875 * factor, 0), 3)
    }

    private static func applyToMatchingServices(
        device: IOHIDDevice,
        resolutionFixed: Int32,
        accelerationFixed: Int32
    ) {
        let vendor = (IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? NSNumber)?.intValue
        let product = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue
        let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        guard let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] else { return }
        for service in services {
            guard matchesMX4PointerService(service, vendor: vendor, product: product) else { continue }
            IOHIDServiceClientSetProperty(service, kIOHIDPointerResolutionKey as CFString, NSNumber(value: resolutionFixed))
            let accelerationKey = accelerationKey(for: service)
            IOHIDServiceClientSetProperty(service, accelerationKey as CFString, NSNumber(value: accelerationFixed))
            if accelerationKey != kIOHIDPointerAccelerationKey {
                IOHIDServiceClientSetProperty(
                    service,
                    kIOHIDPointerAccelerationKey as CFString,
                    NSNumber(value: accelerationFixed)
                )
            }
            if accelerationKey != kIOHIDMouseAccelerationTypeKey {
                IOHIDServiceClientSetProperty(
                    service,
                    kIOHIDMouseAccelerationTypeKey as CFString,
                    NSNumber(value: accelerationFixed)
                )
            }
        }
    }

    private static func matchesMX4PointerService(
        _ service: IOHIDServiceClient,
        vendor: Int?,
        product: Int?
    ) -> Bool {
        let serviceVendor = (IOHIDServiceClientCopyProperty(service, kIOHIDVendorIDKey as CFString) as? NSNumber)?.intValue
        let serviceProduct = (IOHIDServiceClientCopyProperty(service, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue
        if let serviceVendor, let serviceProduct, MXMaster4Support.productIDs.contains(serviceProduct) {
            return serviceVendor == 0x046D
        }
        if let vendor, let product, serviceVendor == vendor, serviceProduct == product {
            return true
        }
        return false
    }

    private static func accelerationKey(for service: IOHIDServiceClient) -> String {
        if let type = IOHIDServiceClientCopyProperty(service, kIOHIDPointerAccelerationTypeKey as CFString) as? String {
            return type
        }
        if IOHIDServiceClientCopyProperty(service, kIOHIDPointerAccelerationKey as CFString) != nil {
            return kIOHIDPointerAccelerationKey
        }
        return kIOHIDMouseAccelerationTypeKey
    }

    private static func ioFixed(_ value: Double) -> Int32 {
        Int32((value * 65_536).rounded())
    }
}
