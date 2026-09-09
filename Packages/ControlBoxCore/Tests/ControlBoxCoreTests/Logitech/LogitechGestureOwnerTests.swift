import XCTest
@testable import ControlBoxCore

final class LogitechGestureOwnerTests: XCTestCase {
    func testStandardMouseButtonCanOwnGestures() {
        var profile = MappingProfile.makeDefault(
            isAppleTVRemote: false,
            isMXMaster: true
        )

        profile.setBinding(.gestures, for: .mxBack)

        XCTAssertEqual(profile.bindings[.mxBack], .gestures)
        XCTAssertNotNil(profile.gestureSet(for: .mxBack))
        XCTAssertTrue(profile.mxGestureOwners.contains(.mxBack))
    }

    func testLegacyMigrationDoesNotRemoveAdditionalGestureOwners() {
        var profile = MappingProfile.makeDefault(
            isAppleTVRemote: false,
            isMXMaster: true
        )
        profile.setBinding(.gestures, for: .mxForward)

        profile.restrictGesturesToHapticPad()

        XCTAssertEqual(profile.bindings[.mxForward], .gestures)
        XCTAssertTrue(profile.mxGestureOwners.contains(.mxForward))
        XCTAssertTrue(profile.mxGestureOwners.contains(.mxHaptic))
    }

    func testDynamicLogitechControlCanOwnGestures() {
        var profile = MappingProfile.makeDefault(
            isAppleTVRemote: false,
            isMXMaster: true
        )

        profile.setBinding(.gestures, for: .mxExtra1)

        XCTAssertTrue(profile.mxGestureOwners.contains(.mxExtra1))
        XCTAssertNotNil(profile.gestureSet(for: .mxExtra1))
    }

    func testPrimaryClicksCannotOwnGestures() {
        var profile = MappingProfile.makeDefault(
            isAppleTVRemote: false,
            isMXMaster: true
        )

        profile.setBinding(.gestures, for: .mxLeft)
        profile.setBinding(.gestures, for: .mxRight)

        XCTAssertNotEqual(profile.bindings[.mxLeft], .gestures)
        XCTAssertNotEqual(profile.bindings[.mxRight], .gestures)
    }

    func testLegacyWindowNavigationDoesNotOverrideNewHapticAction() {
        var profile = MappingProfile.makeDefault(
            isAppleTVRemote: false,
            isMXMaster: true
        )
        profile.bindings[.mxGestureUp] = .missionControl
        profile.bindings[.mxGestureLeft] = .spaceLeft

        profile.setBinding(.browserBack, for: .mxHaptic)

        XCTAssertEqual(profile.bindings[.mxHaptic], .browserBack)
        XCTAssertNil(profile.bindings[.mxGestureUp])
        XCTAssertNil(profile.bindings[.mxGestureLeft])
        XCTAssertFalse(profile.mxGestureOwners.contains(.mxHaptic))
    }

    func testEmptyGestureSetsDoNotInventWindowNavigation() {
        var profile = MappingProfile.makeDefault(
            isAppleTVRemote: false,
            isMXMaster: true
        )
        profile.gestureSets = [:]
        profile.setBinding(.browserBack, for: .mxHaptic)

        XCTAssertNil(profile.gestureSet(for: .mxHaptic))
        XCTAssertFalse(profile.mxGestureOwners.contains(.mxHaptic))
    }

    func testSelectingMediaPresetReplacesWindowNavigation() {
        var profile = MappingProfile.makeDefault(
            isAppleTVRemote: false,
            isMXMaster: true
        )
        profile.selectGesturePreset(.mediaControls, for: .mxHaptic)

        XCTAssertEqual(profile.gestureSet(for: .mxHaptic)?.preset, .mediaControls)
        XCTAssertEqual(profile.gestureSet(for: .mxHaptic)?.click, .mediaPlayPause)
        XCTAssertEqual(profile.gestureSet(for: .mxHaptic)?.left, .mediaPrevious)
    }

    func testLegacyGestureDirectionsMigrateOnceIntoHapticSet() {
        var profile = MappingProfile.makeDefault(
            isAppleTVRemote: false,
            isMXMaster: true
        )
        profile.gestureSets = nil
        profile.bindings[.mxGestureUp] = .missionControl
        profile.bindings[.mxGestureLeft] = .spaceLeft

        profile.restrictGesturesToHapticPad()

        XCTAssertEqual(profile.gestureSet(for: .mxHaptic)?.up, .missionControl)
        XCTAssertEqual(profile.gestureSet(for: .mxHaptic)?.left, .spaceLeft)
        XCTAssertNil(profile.bindings[.mxGestureUp])
        XCTAssertNil(profile.bindings[.mxGestureLeft])
    }

    func testDefaultMXGestureButtonIsGesturesOwner() {
        let profile = MappingProfile.makeDefault(
            isAppleTVRemote: false,
            isMXMaster: true
        )

        XCTAssertEqual(profile.bindings[.mxSide], .gestures)
        XCTAssertTrue(profile.mxGestureOwners.contains(.mxSide))
        XCTAssertEqual(profile.gestureSet(for: .mxSide)?.preset, .windowNavigation)
        XCTAssertEqual(profile.bindings[.mxHaptic], .gestures)
        XCTAssertEqual(DeviceButton.mxSide.title, "Gesture button")
        XCTAssertEqual(DeviceButton.mxHaptic.title, "Haptic button")
    }

    func testEnsureThumbGestureButtonCopiesHapticSetWhenUnset() {
        var profile = MappingProfile.makeDefault(
            isAppleTVRemote: false,
            isMXMaster: true
        )
        profile.bindings[.mxSide] = nil
        profile.gestureSets?[.mxSide] = nil
        profile.selectGesturePreset(.mediaControls, for: .mxHaptic)

        profile.ensureThumbGestureButton()

        XCTAssertEqual(profile.bindings[.mxSide], .gestures)
        XCTAssertEqual(profile.gestureSet(for: .mxSide)?.preset, .mediaControls)
    }

    func testEnsureThumbGestureButtonDoesNotOverwriteExistingBinding() {
        var profile = MappingProfile.makeDefault(
            isAppleTVRemote: false,
            isMXMaster: true
        )
        profile.setBinding(.missionControl, for: .mxSide)

        profile.ensureThumbGestureButton()

        XCTAssertEqual(profile.bindings[.mxSide], .missionControl)
        XCTAssertFalse(profile.mxGestureOwners.contains(.mxSide))
    }
}
