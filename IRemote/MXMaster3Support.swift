import Foundation

/// MX Master 3 is a separate device from 3S and 4. HID++ is not opened here yet.
enum MXMaster3Support {
    static let productIDs: Set<Int> = [0xB019, 0xB023, 0x4082]
    static let hidppUsagePage = 0xFF00
}
