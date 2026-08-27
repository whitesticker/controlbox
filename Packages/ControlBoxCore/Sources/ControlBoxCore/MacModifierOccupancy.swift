import CoreGraphics
import Foundation

/// Enabled Mac modifier chords that must not share an exact key set.
public struct MacModifierOccupancy: Sendable {
    public var entries: [(name: String, flags: CGEventFlags)]

    public init(
        moveEnabled: Bool,
        moveFlags: CGEventFlags,
        resizeEnabled: Bool,
        resizeFlags: CGEventFlags,
        throwEnabled: Bool,
        throwFlags: CGEventFlags,
        arrangementEnabled: Bool,
        arrangementFlags: CGEventFlags
    ) {
        var items: [(name: String, flags: CGEventFlags)] = []
        if moveEnabled {
            items.append(("Window Grab move", ModifierChords.normalized(moveFlags)))
        }
        if resizeEnabled {
            items.append(("Window Grab resize", ModifierChords.normalized(resizeFlags)))
        }
        if throwEnabled {
            items.append(("Window Grab throw", ModifierChords.normalized(throwFlags)))
        }
        if arrangementEnabled {
            items.append(("Display Arrangement", ModifierChords.normalized(arrangementFlags)))
        }
        entries = items
    }

    public func occupied(except name: String? = nil) -> [(name: String, flags: CGEventFlags)] {
        entries.filter { $0.name != name }
    }

    public func collision(_ flags: CGEventFlags, except name: String? = nil) -> String? {
        ModifierChords.collision(flags, occupied: occupied(except: name))
    }
}
