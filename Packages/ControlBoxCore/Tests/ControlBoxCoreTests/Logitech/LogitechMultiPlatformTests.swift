import XCTest
@testable import ControlBoxCore

final class LogitechMultiPlatformTests: XCTestCase {
    /// MX Mechanical Mini over Bolt, 2026-10-05.
    func testParsesMXMechanicalMiniReplies() {
        let info = LogitechMultiPlatform.info(payload: Data([0x03, 0x00, 0x03, 0x03, 0x03, 0x01, 0x00, 0x00]))
        XCTAssertEqual(info, .init(canSetPlatform: true, descriptorCount: 3, currentPlatform: 0))

        let descriptors = [
            Data([0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00]),
            Data([0x01, 0x01, 0x20, 0x00, 0x00, 0x00, 0x00, 0x00]),
            Data([0x02, 0x02, 0x40, 0x00, 0x00, 0x00, 0x00, 0x00])
        ].compactMap(LogitechMultiPlatform.descriptor(payload:))
        XCTAssertEqual(
            LogitechMultiPlatform.options(from: descriptors),
            [
                LogitechPlatformOption(platformIndex: 1, os: .macOS),
                LogitechPlatformOption(platformIndex: 0, os: .windows),
                LogitechPlatformOption(platformIndex: 2, os: .iOS)
            ]
        )
    }

    func testSharedDescriptorIsNamedOnce() {
        let descriptors = [
            LogitechMultiPlatform.Descriptor(platformIndex: 0, osMask: 0x0100 | 0x0400 | 0x1000),
            LogitechMultiPlatform.Descriptor(platformIndex: 1, osMask: 0x2000 | 0x4000)
        ]
        XCTAssertEqual(
            LogitechMultiPlatform.options(from: descriptors),
            [
                LogitechPlatformOption(platformIndex: 1, os: .macOS),
                LogitechPlatformOption(platformIndex: 0, os: .windows)
            ]
        )
    }

    func testCannotSetPlatform() {
        let info = LogitechMultiPlatform.info(payload: Data([0x01, 0x00, 0x02, 0x02, 0x03, 0x00, 0x01]))
        XCTAssertEqual(info?.canSetPlatform, false)
    }

    func testSetTargetsCurrentHost() {
        XCTAssertEqual(LogitechMultiPlatform.setHostPlatformParameters(1), [0xFF, 0x01])
    }
}
