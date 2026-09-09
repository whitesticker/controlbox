import XCTest
@testable import ControlBoxCore

final class ControlActionCatalogTests: XCTestCase {
    func testSwitchWheelModeIsInTheButtonCatalog() {
        XCTAssertEqual(ControlAction.switchWheelMode.title, "Switch wheel mode")
        XCTAssertEqual(ControlAction.switchWheelMode.catalogID, "switchWheelMode")
        XCTAssertEqual(ControlAction.fromCatalogID("switchWheelMode"), .switchWheelMode)
        XCTAssertTrue(ControlAction.catalog.contains(where: { $0.action == .switchWheelMode }))
        XCTAssertTrue(ControlAction.switchWheelMode.isDiscreteSwipe)
    }

    func testRatchetModeTogglesBetweenFreeSpinAndRatchet() {
        XCTAssertEqual(MXRatchetMode.ratchet.toggled, .freeSpin)
        XCTAssertEqual(MXRatchetMode.freeSpin.toggled, .ratchet)
    }
}
