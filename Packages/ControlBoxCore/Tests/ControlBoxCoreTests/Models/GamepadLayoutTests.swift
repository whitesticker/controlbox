import XCTest
@testable import ControlBoxCore

final class GamepadLayoutTests: XCTestCase {
    func testSonyLabelsMatchDualSenseTitles() {
        let layout = GamepadLayout.sony
        XCTAssertEqual(layout.label(for: .cross), "Cross")
        XCTAssertEqual(layout.label(for: .circle), "Circle")
        XCTAssertEqual(layout.label(for: .square), "Square")
        XCTAssertEqual(layout.label(for: .triangle), "Triangle")
        XCTAssertEqual(layout.label(for: .create), "Create")
        XCTAssertEqual(layout.label(for: .options), "Options")
        XCTAssertEqual(layout.label(for: .ps), "PS")
        XCTAssertEqual(layout.label(for: .l1), "L1")
        XCTAssertEqual(layout.label(for: .r1), "R1")
        XCTAssertEqual(layout.label(for: .l2), "L2")
        XCTAssertEqual(layout.label(for: .r2), "R2")
        XCTAssertEqual(layout.label(for: .l3), "Left stick click")
        XCTAssertEqual(layout.label(for: .r3), "Right stick click")
        XCTAssertEqual(layout.homeButtonName, "PS")
        XCTAssertEqual(layout.title, "DualSense")
        XCTAssertEqual(layout.brand, "Sony")
    }

    func testXboxLabels() {
        let layout = GamepadLayout.xbox
        XCTAssertEqual(layout.label(for: .cross), "A")
        XCTAssertEqual(layout.label(for: .circle), "B")
        XCTAssertEqual(layout.label(for: .square), "X")
        XCTAssertEqual(layout.label(for: .triangle), "Y")
        XCTAssertEqual(layout.label(for: .create), "View")
        XCTAssertEqual(layout.label(for: .options), "Menu")
        XCTAssertEqual(layout.label(for: .ps), "Xbox")
        XCTAssertEqual(layout.label(for: .l1), "LB")
        XCTAssertEqual(layout.label(for: .r1), "RB")
        XCTAssertEqual(layout.label(for: .l2), "LT")
        XCTAssertEqual(layout.label(for: .r2), "RT")
        XCTAssertEqual(layout.homeButtonName, "Xbox")
        XCTAssertEqual(layout.brand, "Microsoft")
    }

    func testNintendoLabels() {
        let layout = GamepadLayout.nintendo
        XCTAssertEqual(layout.label(for: .cross), "B")
        XCTAssertEqual(layout.label(for: .circle), "A")
        XCTAssertEqual(layout.label(for: .square), "Y")
        XCTAssertEqual(layout.label(for: .triangle), "X")
        XCTAssertEqual(layout.label(for: .create), "−")
        XCTAssertEqual(layout.label(for: .options), "+")
        XCTAssertEqual(layout.label(for: .ps), "Home")
        XCTAssertEqual(layout.label(for: .l1), "L")
        XCTAssertEqual(layout.label(for: .r1), "R")
        XCTAssertEqual(layout.label(for: .l2), "ZL")
        XCTAssertEqual(layout.label(for: .r2), "ZR")
        XCTAssertEqual(layout.homeButtonName, "Home")
        XCTAssertEqual(layout.brand, "Nintendo")
    }

    func testGenericLabels() {
        let layout = GamepadLayout.generic
        XCTAssertEqual(layout.label(for: .cross), "A")
        XCTAssertEqual(layout.label(for: .circle), "B")
        XCTAssertEqual(layout.label(for: .square), "X")
        XCTAssertEqual(layout.label(for: .triangle), "Y")
        XCTAssertEqual(layout.label(for: .create), "Select")
        XCTAssertEqual(layout.label(for: .options), "Start")
        XCTAssertEqual(layout.label(for: .ps), "Home")
        XCTAssertEqual(layout.label(for: .l1), "L1")
        XCTAssertEqual(layout.label(for: .r2), "R2")
        XCTAssertEqual(layout.homeButtonName, "Home")
        XCTAssertEqual(layout.brand, "Other")
    }

    func testLayoutCodableRoundTrip() throws {
        for layout in GamepadLayout.allCases {
            let data = try JSONEncoder().encode(layout)
            let decoded = try JSONDecoder().decode(GamepadLayout.self, from: data)
            XCTAssertEqual(decoded, layout)
        }
        XCTAssertEqual(
            String(data: try JSONEncoder().encode(GamepadLayout.sony), encoding: .utf8),
            "\"sony\""
        )
    }

    func testCapabilitiesDefaultOffAndCodable() throws {
        let empty = GamepadCapabilities()
        XCTAssertFalse(empty.touchpad)
        XCTAssertFalse(empty.motion)
        XCTAssertFalse(empty.haptics)
        XCTAssertFalse(empty.battery)

        let dual = GamepadCapabilities.dualSense
        let data = try JSONEncoder().encode(dual)
        let decoded = try JSONDecoder().decode(GamepadCapabilities.self, from: data)
        XCTAssertEqual(decoded, dual)
        XCTAssertTrue(decoded.touchpad)
        XCTAssertTrue(decoded.motion)
        XCTAssertTrue(decoded.haptics)
        XCTAssertTrue(decoded.battery)
    }

    func testGamepadGroupsHideTouchpadWhenAsked() {
        let withPad = DeviceButton.gamepadGroups(hasTouchpad: true)
        let withoutPad = DeviceButton.gamepadGroups(hasTouchpad: false)
        XCTAssertEqual(withPad.map(\.id), withoutPad.map(\.id))
        XCTAssertTrue(withPad.first { $0.id == "system" }?.buttons.contains(.touchpadClick) == true)
        XCTAssertFalse(withoutPad.first { $0.id == "system" }?.buttons.contains(.touchpadClick) == true)
        XCTAssertEqual(DeviceButton.dualSenseGroups, withPad)

        let withPadButtons = DeviceButton.gamepadButtons(hasTouchpad: true)
        let withoutPadButtons = DeviceButton.gamepadButtons(hasTouchpad: false)
        XCTAssertTrue(withPadButtons.contains(.touchpadOneFinger))
        XCTAssertTrue(withPadButtons.contains(.touchpadTwoFinger))
        XCTAssertFalse(withoutPadButtons.contains(.touchpadOneFinger))
        XCTAssertFalse(withoutPadButtons.contains(.touchpadClick))
        XCTAssertEqual(DeviceButton.dualSenseButtons, withPadButtons)
    }

    func testCatalogIDUsesNameOrdinals() {
        XCTAssertEqual(GamepadCatalogID.make(name: "Xbox Wireless Controller", ordinal: 1), "gc:Xbox Wireless Controller")
        XCTAssertEqual(GamepadCatalogID.make(name: "Xbox Wireless Controller", ordinal: 2), "gc:Xbox Wireless Controller#2")
        XCTAssertEqual(GamepadCatalogID.make(name: "  ", ordinal: 1), "gc:Game Controller")
    }

    func testUniqueHIDAddressOnlyWhenOnePadEach() {
        XCTAssertEqual(
            GamepadCatalogID.uniqueHIDAddress(addresses: ["AA:BB:CC:DD:EE:FF"], gcCount: 1),
            "AA:BB:CC:DD:EE:FF"
        )
        XCTAssertNil(GamepadCatalogID.uniqueHIDAddress(addresses: ["AA:BB:CC:DD:EE:FF"], gcCount: 2))
        XCTAssertNil(
            GamepadCatalogID.uniqueHIDAddress(
                addresses: ["AA:BB:CC:DD:EE:FF", "11:22:33:44:55:66"],
                gcCount: 1
            )
        )
        XCTAssertNil(GamepadCatalogID.uniqueHIDAddress(addresses: [], gcCount: 1))
    }

    func testSlotAddressPrefersHIDThenOrdinalSlot() {
        XCTAssertEqual(
            GamepadCatalogID.slotAddress(catalogID: "gc:Xbox Wireless Controller", hidAddress: "AA:BB:CC:DD:EE:FF"),
            "AA:BB:CC:DD:EE:FF"
        )
        XCTAssertEqual(
            GamepadCatalogID.slotAddress(catalogID: "gc:Xbox Wireless Controller#2", hidAddress: nil),
            "slot:gc:Xbox Wireless Controller#2"
        )
    }
}
