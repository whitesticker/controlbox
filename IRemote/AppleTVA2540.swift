import Foundation

/// 2nd-generation Siri Remote (A2540). Clickpad + ring live on MultitouchSupport;
/// face buttons are HID. Older Siri PIDs stay here until they get their own module.
struct AppleTVA2540: AppleTVRemoteGeneration {
    let id = "A2540"
    let productTitle = "Siri Remote A2540"
    let productIDs: Set<Int> = [0x0314, 0x0315, 0x0266, 0x0267]
    let usesMultitouchClickpad = true
    let usesClickwheel = true
}
