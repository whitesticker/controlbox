import AppKit
import CoreGraphics
import Foundation

public enum ModifierChords {
    public static let bits: CGEventFlags = [
        .maskControl, .maskShift, .maskAlternate, .maskCommand, .maskAlphaShift
    ]

    public static func normalized(_ flags: CGEventFlags) -> CGEventFlags {
        flags.intersection(bits)
    }

    public static func normalized(_ flags: UInt64) -> CGEventFlags {
        normalized(CGEventFlags(rawValue: flags))
    }

    /// Hardware modifiers for the current event. Drops lock-state Caps Lock,
    /// then ORs in the Caps Lock mapping while that key is physically held.
    public static func live(_ flags: CGEventFlags) -> CGEventFlags {
        var next = normalized(flags)
        next.remove(.maskAlphaShift)
        if CapsLockModifier.isHeld {
            next.formUnion(normalized(CapsLockModifier.mappedFlags))
        }
        return next
    }

    public static func live(_ flags: UInt64) -> CGEventFlags {
        live(CGEventFlags(rawValue: flags))
    }

    public static func fromAppKit(_ flags: NSEvent.ModifierFlags) -> CGEventFlags {
        var next = CGEventFlags(rawValue: 0)
        if flags.contains(.control) { next.insert(.maskControl) }
        if flags.contains(.shift) { next.insert(.maskShift) }
        if flags.contains(.option) { next.insert(.maskAlternate) }
        if flags.contains(.command) { next.insert(.maskCommand) }
        if CapsLockModifier.isHeld {
            next.formUnion(normalized(CapsLockModifier.mappedFlags))
        }
        return next
    }

    public static func count(_ flags: CGEventFlags) -> Int {
        let bits = normalized(flags)
        var total = 0
        if bits.contains(.maskControl) { total += 1 }
        if bits.contains(.maskShift) { total += 1 }
        if bits.contains(.maskAlternate) { total += 1 }
        if bits.contains(.maskCommand) { total += 1 }
        if bits.contains(.maskAlphaShift) { total += 1 }
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
