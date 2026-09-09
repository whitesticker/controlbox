import CoreGraphics
import XCTest
@testable import ControlBoxCore

final class LogitechGestureMotionTests: XCTestCase {
    func testHIDRawXYWinsOverNativeFallback() {
        let hid = CGSize(width: 40, height: -8)
        let pointer = CGSize(width: 400, height: 200)
        XCTAssertEqual(
            LogitechGestureMotion.liveDelta(hid: hid, pointer: pointer),
            hid
        )
    }

    func testNativePointerIsFallbackWhenHIDIsEmpty() {
        let pointer = CGSize(width: 12, height: 4)
        XCTAssertEqual(
            LogitechGestureMotion.liveDelta(hid: .zero, pointer: pointer),
            pointer
        )
    }
}

final class HoldGestureSetTests: XCTestCase {
    func testBeginReplacesActiveSet() {
        var gesture = HoldGesture()
        gesture.begin(owner: .mxHaptic, set: .named(.windowNavigation))
        XCTAssertEqual(gesture.activeSet?.preset, .windowNavigation)

        gesture.begin(owner: .mxHaptic, set: .named(.mediaControls))
        XCTAssertEqual(gesture.activeSet?.preset, .mediaControls)
        XCTAssertEqual(gesture.activeSet?.click, .mediaPlayPause)
    }
}
