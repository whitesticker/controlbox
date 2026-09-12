import Foundation

/// Stable Game Controller catalog ids. GameController has no public serial,
/// so same-name pads get ordinals (`gc:Name`, `gc:Name#2`). A HID MAC is only
/// used as the *address* when exactly one HID pad and one GC pad of that kind
/// are present.
public enum GamepadCatalogID {
    public static func make(name: String, ordinal: Int) -> String {
        let base = normalizedName(name)
        if ordinal <= 1 { return "gc:\(base)" }
        return "gc:\(base)#\(ordinal)"
    }

    public static func slotAddress(catalogID: String, hidAddress: String?) -> String {
        if let hidAddress, !hidAddress.isEmpty {
            return hidAddress
        }
        return "slot:\(catalogID)"
    }

    public static func uniqueHIDAddress(addresses: [String], gcCount: Int) -> String? {
        let unique = Set(addresses.filter { !$0.isEmpty })
        guard unique.count == 1, gcCount == 1 else { return nil }
        return unique.first
    }

    public static func normalizedName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Game Controller" : trimmed
    }
}
