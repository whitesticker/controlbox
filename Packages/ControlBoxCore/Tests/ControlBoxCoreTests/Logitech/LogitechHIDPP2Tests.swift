import Foundation
import XCTest
@testable import ControlBoxCore

final class LogitechHIDPP2Tests: XCTestCase {
    func testSoftwareIDUsesReservedRangeAndWraps() {
        XCTAssertEqual(LogitechHIDPP2.nextSoftwareID(after: 0x07), 0x08)
        XCTAssertEqual(LogitechHIDPP2.nextSoftwareID(after: 0x0E), 0x0F)
        XCTAssertEqual(LogitechHIDPP2.nextSoftwareID(after: 0x0F), 0x08)
    }

    func testLongReportEncodingMatchesHIDPP20Layout() {
        let report = LogitechHIDPP2.longReport(
            deviceIndex: 0xFF,
            featureIndex: 0x05,
            function: 0x03,
            softwareID: 0x0C,
            parameters: [0x1A, 0x00, 0x33]
        )

        XCTAssertEqual(report.count, 20)
        XCTAssertEqual(Array(report.prefix(7)), [0x11, 0xFF, 0x05, 0x3C, 0x1A, 0x00, 0x33])
        XCTAssertEqual(Array(report.dropFirst(7)), [UInt8](repeating: 0, count: 13))
    }

    func testLongReportTruncatesParametersToSixteenBytes() {
        let parameters = Array(UInt8(0)...UInt8(19))
        let report = LogitechHIDPP2.longReport(
            deviceIndex: 2,
            featureIndex: 7,
            function: 1,
            softwareID: 8,
            parameters: parameters
        )

        XCTAssertEqual(Array(report.dropFirst(4)), Array(parameters.prefix(16)))
    }

    func testShortReportEncodingMatchesHIDPP20Layout() {
        let report = LogitechHIDPP2.shortReport(
            deviceIndex: 0,
            featureIndex: 4,
            function: 2,
            softwareID: 9,
            parameters: [1, 2, 3, 4]
        )

        XCTAssertEqual(report, [0x10, 0x00, 0x04, 0x29, 0x01, 0x02, 0x03])
    }

    func testFeatureLookupUsesBigEndianFeatureID() {
        XCTAssertEqual(LogitechHIDPP2.featureLookupParameters(0x1B04), [0x1B, 0x04])
        XCTAssertEqual(LogitechHIDPP2.featureLookupParameters(0x0001), [0x00, 0x01])
    }

    func testFeatureSetIndicesStartAtOneAndRespectLimit() {
        XCTAssertEqual(LogitechHIDPP2.featureSetIndices(count: 3), [1, 2, 3])
        XCTAssertEqual(LogitechHIDPP2.featureSetIndices(count: 0), [])
        XCTAssertEqual(
            LogitechHIDPP2.featureSetIndices(count: 80),
            Array(UInt8(1)...UInt8(48))
        )
    }

    func testCIDReportingParametersPreserveOptionalHighFlags() {
        XCTAssertEqual(
            LogitechHIDPP2.cidReportingParameters(
                cid: 0x01A0,
                flags: 0x33,
                remap: 0,
                highFlags: 0x03
            ),
            [0x01, 0xA0, 0x33, 0x00, 0x00, 0x03]
        )
        XCTAssertEqual(
            LogitechHIDPP2.cidReportingParameters(cid: 0x00C3, flags: 0x22),
            [0x00, 0xC3, 0x22, 0x00, 0x00]
        )
    }

    func testKnownReceiverProductsAreExcludedFromPeripheralDiscovery() {
        for productID in [
            0xC52B, 0xC52F, 0xC531, 0xC532, 0xC534, 0xC537,
            0xC539, 0xC53A, 0xC53F, 0xC547, 0xC548, 0xC54D
        ] {
            XCTAssertTrue(LogitechHIDPP2.knownReceiverProductIDs.contains(productID))
        }
    }

    func testCIDReportingRestorePreservesOnlyOwnedFields() throws {
        let state = try XCTUnwrap(
            LogitechHIDPPCIDReportingState(
                payload: Data([0x00, 0xC3, 0x55, 0x00, 0xC4, 0x05])
            )
        )

        XCTAssertEqual(state.cid, 0x00C3)
        XCTAssertTrue(state.diverted)
        XCTAssertTrue(state.rawXY)
        XCTAssertEqual(state.remap, 0x00C4)
        XCTAssertTrue(state.analytics)
        XCTAssertEqual(
            state.restoreParameters,
            [0x00, 0xC3, 0x33, 0x00, 0xC4, 0x03]
        )
        XCTAssertEqual(state.restoreParameters[2] & 0xCC, 0)
    }
}

final class LogitechUnifiedBatteryReadingTests: XCTestCase {
    func testMissingPayloadDoesNotProduceReading() {
        XCTAssertNil(LogitechUnifiedBatteryReading(payload: nil))
        XCTAssertNil(LogitechUnifiedBatteryReading(payload: Data()))
    }

    func testChargingStatusesMatchExistingReaders() throws {
        let charging = try XCTUnwrap(
            LogitechUnifiedBatteryReading(payload: Data([42, 0, 1]))
        )
        XCTAssertEqual(charging.percentage, 42)
        XCTAssertTrue(charging.isCharging)
        XCTAssertFalse(charging.isFull)
        XCTAssertEqual(charging.stateDescription, "Charging")

        let slowCharging = try XCTUnwrap(
            LogitechUnifiedBatteryReading(payload: Data([43, 0, 4]))
        )
        XCTAssertTrue(slowCharging.isCharging)
        XCTAssertEqual(slowCharging.stateDescription, "Charging")
    }

    func testFullAndAlmostFullStatusesMatchExistingReaders() throws {
        let almostFull = try XCTUnwrap(
            LogitechUnifiedBatteryReading(payload: Data([94, 0, 2]))
        )
        XCTAssertFalse(almostFull.isFull)
        XCTAssertEqual(almostFull.stateDescription, "Almost full")

        let thresholdFull = try XCTUnwrap(
            LogitechUnifiedBatteryReading(payload: Data([95, 0, 2]))
        )
        XCTAssertTrue(thresholdFull.isFull)
        XCTAssertEqual(thresholdFull.stateDescription, "Almost full")

        let full = try XCTUnwrap(
            LogitechUnifiedBatteryReading(payload: Data([90, 0, 3]))
        )
        XCTAssertTrue(full.isFull)
        XCTAssertEqual(full.stateDescription, "Full")
    }

    func testMissingStatusDefaultsToDischarging() throws {
        let reading = try XCTUnwrap(
            LogitechUnifiedBatteryReading(payload: Data([75]))
        )
        XCTAssertFalse(reading.isCharging)
        XCTAssertFalse(reading.isFull)
        XCTAssertEqual(reading.stateDescription, "Discharging")
    }
}
