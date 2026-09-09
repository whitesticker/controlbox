import XCTest
@testable import ControlBoxCore

final class LogitechHIDPPCapabilitiesTests: XCTestCase {
    func testFeatureCatalogDerivesCapabilitiesWithoutModelIdentity() {
        var catalog = LogitechHIDPPFeatureCatalog()
        catalog[0x1B04] = 5
        catalog[0x2201] = 6
        catalog[0x2150] = 7
        catalog[0x1815] = 8
        catalog[0x1004] = 9

        let capabilities = catalog.capabilities
        XCTAssertTrue(capabilities.reprogrammableControls)
        XCTAssertTrue(capabilities.adjustableDPI)
        XCTAssertTrue(capabilities.thumbWheel)
        XCTAssertTrue(capabilities.easySwitch)
        XCTAssertTrue(capabilities.battery)
        XCTAssertFalse(capabilities.smartShift)
        XCTAssertFalse(capabilities.backlight)
    }

    func testUnimplementedLegacyBatteryAndExtendedDPIDoNotClaimUISupport() {
        let catalog = LogitechHIDPPFeatureCatalog(
            indices: [
                LogitechHIDPPFeatureID.batteryVoltage: 4,
                LogitechHIDPPFeatureID.extendedAdjustableDPI: 5
            ]
        )

        XCTAssertFalse(catalog.capabilities.battery)
        XCTAssertFalse(catalog.capabilities.adjustableDPI)
    }

    func testZeroFeatureIndexRemovesFeature() {
        var catalog = LogitechHIDPPFeatureCatalog(
            indices: [LogitechHIDPPFeatureID.unifiedBattery: 4]
        )
        catalog[LogitechHIDPPFeatureID.unifiedBattery] = 0

        XCTAssertNil(catalog[LogitechHIDPPFeatureID.unifiedBattery])
        XCTAssertFalse(catalog.capabilities.battery)
    }

    func testControlDescriptorDecodesReprogFlags() {
        let gesture = LogitechHIDPPControlDescriptor(
            cid: 0x0053,
            task: 0,
            flagsLow: 0x20,
            flagsHigh: 0x01
        )
        XCTAssertTrue(gesture.isDivertable)
        XCTAssertTrue(gesture.supportsRawXY)
        XCTAssertFalse(gesture.supportsForceRawXY)
        XCTAssertTrue(gesture.canOwnGestures)

        let plain = LogitechHIDPPControlDescriptor(
            cid: 0x0056,
            task: 0,
            flagsLow: 0x20,
            flagsHigh: 0
        )
        XCTAssertTrue(plain.isDivertable)
        XCTAssertFalse(plain.canOwnGestures)
    }
}
