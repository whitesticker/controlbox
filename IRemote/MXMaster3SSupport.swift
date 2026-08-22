import Foundation

/// MX Master 3S is a separate device from 3 and 4. HID++ is not opened here yet.
enum MXMaster3SSupport {
    static let productIDs: Set<Int> = [0xB034, 0xB043]
    static let hidppUsagePage = 0xFF43
    static let gestureCID: UInt16 = 0x00C3
}
