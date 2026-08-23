import Foundation
import IRemoteControl

/// One attached family the host can start, poll, and stop.
/// Add a new device by implementing this and registering it on the host.
/// Do not grow `DualSenseMonitor` with another `captureXbox()` path.
@MainActor
protocol DeviceFamilySession: AnyObject {
    var familyID: String { get }
    var kinds: Set<DeviceKind> { get }
    func start()
    func stop()
}

/// Hardware profile inside the Apple TV remote family.
/// Generations differ enough (HID map, clickpad, click wheel, Siri) that
/// each generation is its own type. The session picks one; the host does not.
protocol AppleTVRemoteGeneration {
    var id: String { get }
    var productTitle: String { get }
    var productIDs: Set<Int> { get }
    var usesMultitouchClickpad: Bool { get }
    var usesClickwheel: Bool { get }
}

enum AppleTVRemoteGenerations {
    static let all: [AppleTVRemoteGeneration] = [AppleTVA2540()]

    static var productIDs: Set<Int> {
        Set(all.flatMap(\.productIDs))
    }

    static func generation(forProductID productID: Int) -> AppleTVRemoteGeneration {
        all.first { $0.productIDs.contains(productID) } ?? AppleTVA2540()
    }
}
