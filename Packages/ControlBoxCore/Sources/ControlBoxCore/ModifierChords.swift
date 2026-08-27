import CoreGraphics
import Foundation

public enum ModifierChords {
    public static let bits: CGEventFlags = [
        .maskControl, .maskShift, .maskAlternate, .maskCommand
    ]

    public static func normalized(_ flags: CGEventFlags) -> CGEventFlags {
        flags.intersection(bits)
    }

    public static func normalized(_ flags: UInt64) -> CGEventFlags {
        normalized(CGEventFlags(rawValue: flags))
    }

    public static func count(_ flags: CGEventFlags) -> Int {
        let bits = normalized(flags)
        var total = 0
        if bits.contains(.maskControl) { total += 1 }
        if bits.contains(.maskShift) { total += 1 }
        if bits.contains(.maskAlternate) { total += 1 }
        if bits.contains(.maskCommand) { total += 1 }
        return total
    }

    public static func count(_ flags: UInt64) -> Int {
        count(CGEventFlags(rawValue: flags))
    }

    public static func collides(_ a: CGEventFlags, _ b: CGEventFlags) -> Bool {
        let left = normalized(a)
        let right = normalized(b)
        guard !left.isEmpty, !right.isEmpty else { return false }
        return left == right
    }

    public static func collision(
        _ candidate: CGEventFlags,
        occupied: [(name: String, flags: CGEventFlags)]
    ) -> String? {
        for item in occupied where collides(candidate, item.flags) {
            return item.name
        }
        return nil
    }
}
