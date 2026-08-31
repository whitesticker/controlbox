import Foundation

/// MX Master 4 HID++ / native-haptic profile. Do not reuse these CIDs on 3S.
enum MXMaster4Support {
    /// `0xB366` is MX Mechanical, not this mouse. Keep it off this matcher.
    static let productIDs: Set<Int> = [0xB042, 0x4069]
    static let hidppUsagePage = 0xFF00
    static let hidppUsagePageBLE = 0xFF43
    static let nativeHapticButtonBit: UInt8 = 0x40
    static let hapticCID: UInt16 = 0x01A0
    static let gestureButtonCID: UInt16 = 0x00C3
    static let forceSensingFeature: UInt16 = 0x19C0
    static let forceThreshold: UInt16 = 0x15A3
    static let extraButtonCIDs: Set<UInt16> = [
        0x0053, 0x0054, 0x0056, 0x00C3, 0x00C4, 0x00D0, 0x00ED, 0x00FD
    ]

    static let model = MXMasterHIDModel(
        kind: .logitechMXMaster4,
        acceptedKinds: [.logitechMXMaster4, .logitechMXMaster],
        productIDs: productIDs,
        hidppUsagePages: [hidppUsagePage, hidppUsagePageBLE],
        gestureCID: hapticCID,
        extraButtonCIDs: extraButtonCIDs,
        nativeHapticButtonBit: nativeHapticButtonBit,
        nativeMouseButtonBytes: 1,
        forceSensingFeature: forceSensingFeature,
        forceThreshold: forceThreshold,
        analyticsReportingFlags: 0x03,
        tryShortHIDPPReport: true,
        gestureControlTitle: "Haptic",
        lookingStatus: "Looking for an MX Master 4…"
    )
}
