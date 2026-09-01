import Foundation
import IOKit.pwr_mgt

/// Holds idle-sleep and idle-display assertions so the Mac stays awake.
/// Lid close can still sleep a MacBook. Release on stop or deinit.
public final class CaffeinateKeepAwake {
    private var systemID: IOPMAssertionID = 0
    private var displayID: IOPMAssertionID = 0

    public init() {}

    deinit {
        releaseAssertions()
    }

    public var isHeld: Bool {
        systemID != 0 || displayID != 0
    }

    @discardableResult
    public func start() -> Bool {
        stop()
        let reason = "Control Box Caffeinate" as CFString
        guard create(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString, reason, &systemID) else {
            return false
        }
        guard create(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString, reason, &displayID) else {
            releaseAssertions()
            return false
        }
        return true
    }

    public func stop() {
        releaseAssertions()
    }

    private func create(_ type: CFString, _ reason: CFString, _ id: inout IOPMAssertionID) -> Bool {
        IOPMAssertionCreateWithName(
            type,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &id
        ) == kIOReturnSuccess
    }

    private func releaseAssertions() {
        if systemID != 0 {
            IOPMAssertionRelease(systemID)
            systemID = 0
        }
        if displayID != 0 {
            IOPMAssertionRelease(displayID)
            displayID = 0
        }
    }
}
