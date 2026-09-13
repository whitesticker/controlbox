import AppKit
import CoreGraphics
import Darwin
import Foundation

/// Switch a display to the Space that owns a window.
///
/// DockSwipe follows the display under the pointer. Same-monitor clicks already
/// land. Other-monitor hops to the nearest edge of that display, posts the
/// swipe, then puts the pointer back as soon as the slide starts.
enum WindowSpaces {
    private static let lock = NSLock()
    private static var switchTask: Task<Void, Never>?

    static func cancel() {
        lock.lock()
        switchTask?.cancel()
        switchTask = nil
        lock.unlock()
    }

    /// True if a switch was started or the Space is already current.
    static func reveal(
        windowID: CGWindowID,
        pid: pid_t,
        pids: Set<pid_t>,
        bounds: CGRect
    ) -> Bool {
        guard let cid = connectionID() else { return false }
        let query = Query(windowID: windowID, pid: pid, pids: pids, bounds: bounds)
        guard snapshot(query, from: CGEvent(source: nil)?.location ?? .zero, cid: cid) != nil else {
            return false
        }
        cancel()
        let task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            await switchTo(query)
        }
        lock.lock()
        switchTask = task
        lock.unlock()
        return true
    }

    static func isFullscreen(_ windowID: CGWindowID, pid _: pid_t = 0) -> Bool {
        guard let cid = connectionID() else { return false }
        if windowID != 0 {
            for space in spaceIDs(for: windowID, cid: cid) {
                let type = spaceType(space, cid: cid)
                if type == 1 || type == 4 { return true }
            }
        }
        guard let displays = managedDisplays(cid: cid) else { return false }
        for display in displays {
            let spaces = display["Spaces"] as? [[String: Any]] ?? []
            for space in spaces where ownsWindow(windowID, space: space) {
                return true
            }
        }
        return false
    }

    /// For a window that owns a fullscreen Space: is that Space current on its
    /// display? Nil when the window does not own a fullscreen Space.
    static func fullscreenSpaceIsCurrent(_ windowID: CGWindowID) -> Bool? {
        guard windowID != 0, let cid = connectionID(),
              let displays = managedDisplays(cid: cid) else { return nil }
        for display in displays {
            let spaces = display["Spaces"] as? [[String: Any]] ?? []
            guard let owner = spaces.first(where: { ownsWindow(windowID, space: $0) }),
                  let id = topID(owner) else { continue }
            let current = topID(display["Current Space"] as? [String: Any] ?? [:])
            return current == id
        }
        return nil
    }

    private struct Query {
        var windowID: CGWindowID
        var pid: pid_t
        var pids: Set<pid_t>
        var bounds: CGRect
    }

    @MainActor
    private static func switchTo(_ query: Query) async {
        guard let cid = connectionID() else { return }
        let home = CGEvent(source: nil)?.location ?? .zero
        var parked = false
        defer {
            if parked {
                CGWarpMouseCursorPosition(home)
            }
        }
        for _ in 0..<12 {
            guard !Task.isCancelled else { return }
            guard let step = snapshot(query, from: home, cid: cid) else { return }
            if step.from == step.to { return }
            // Something else is already sliding this display (Apple's own
            // activation of a fullscreen app). A swipe on top of that
            // cancels or overshoots it. Let it land, then re-check.
            if isAnimating(step.uuid, cid: cid) {
                await waitWhileAnimating(step.uuid, cid: cid)
                continue
            }
            if !pointerOnDisplay(step.point) {
                parkCursor(at: step.point)
                parked = true
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
            DockSwipe.playOneSpace(
                axis: .horizontal,
                towardPositive: step.to > step.from,
                at: step.point
            )
            if parked {
                await waitUntilSlideStarts(from: step.current, uuid: step.uuid, cid: cid)
                CGWarpMouseCursorPosition(home)
                parked = false
            }
            await waitForMove(from: step.current, uuid: step.uuid, cid: cid)
        }
    }

    private struct Step {
        var uuid: String
        var current: UInt64
        var from: Int
        var to: Int
        var point: CGPoint
    }

    private static func snapshot(_ query: Query, from cursor: CGPoint, cid: Int32) -> Step? {
        guard let displays = managedDisplays(cid: cid) else { return nil }
        guard let hit = find(query, in: displays) else { return nil }
        guard let from = hit.ids.firstIndex(of: hit.current),
              let to = hit.ids.firstIndex(of: hit.target)
        else { return nil }
        guard let point = nearestPoint(on: hit.uuid, from: cursor) else { return nil }
        return Step(uuid: hit.uuid, current: hit.current, from: from, to: to, point: point)
    }

    private struct Hit {
        var uuid: String
        var ids: [UInt64]
        var current: UInt64
        var target: UInt64
        var rank: Int
    }

    private static func find(_ query: Query, in displays: [[String: Any]]) -> Hit? {
        let raw = query.windowID == 0 ? [] : (connectionID().map { spaceIDs(for: query.windowID, cid: $0) } ?? [])
        var best: Hit?
        for display in displays {
            guard let uuid = display["Display Identifier"] as? String else { continue }
            let spaces = display["Spaces"] as? [[String: Any]] ?? []
            let ids = spaces.compactMap { topID($0) }
            let current = topID(display["Current Space"] as? [String: Any] ?? [:]) ?? 0
            guard let pick = target(
                query,
                raw: raw,
                uuid: uuid,
                current: current,
                spaces: spaces
            ) else { continue }
            let hit = Hit(uuid: uuid, ids: ids, current: current, target: pick.id, rank: pick.rank)
            if best == nil || hit.rank < best!.rank {
                best = hit
            }
        }
        return best
    }

    private static func target(
        _ query: Query,
        raw: [UInt64],
        uuid: String,
        current: UInt64,
        spaces: [[String: Any]]
    ) -> (id: UInt64, rank: Int)? {
        let onThisDisplay = displayContains(uuid, query.bounds)
        var pidHit: (id: UInt64, rank: Int)?
        var userMatches: [UInt64] = []
        for space in spaces {
            guard let id = topID(space) else { continue }
            let type = int(space["type"])
            let fullscreen = type == 1 || type == 4
            if ownsWindow(query.windowID, space: space) {
                return (id, 0)
            }
            if raw.contains(id) {
                if fullscreen {
                    return (id, 1)
                }
                userMatches.append(id)
            }
            let owner = pid_t(uint64(space["pid"]) ?? 0)
            if fullscreen, query.pids.contains(owner) || owner == query.pid {
                let rank = onThisDisplay ? 2 : 3
                if pidHit == nil || rank < pidHit!.rank {
                    pidHit = (id, rank)
                }
            }
        }
        if userMatches.count == 1 {
            return (userMatches[0], 4)
        }
        if userMatches.count > 1 {
            let others = userMatches.filter { $0 != current }
            if others.count == 1 {
                return (others[0], 4)
            }
        }
        return pidHit
    }

    private static func ownsWindow(_ windowID: CGWindowID, space: [String: Any]) -> Bool {
        guard windowID != 0 else { return false }
        let id = UInt64(windowID)
        if uint64(space["fs_wid"]) == id { return true }
        if uint64(space["TileWindowID"]) == id { return true }
        let tiles = (space["TileLayoutManager"] as? [String: Any])?["TileSpaces"] as? [[String: Any]] ?? []
        for tile in tiles {
            if uint64(tile["fs_wid"]) == id { return true }
            if uint64(tile["TileWindowID"]) == id { return true }
        }
        return false
    }

    private static func topID(_ space: [String: Any]) -> UInt64? {
        uint64(space["id64"]) ?? uint64(space["ManagedSpaceID"])
    }

    private static func managedDisplays(cid: Int32) -> [[String: Any]]? {
        guard let copy = symbol("SLSCopyManagedDisplaySpaces")
            ?? symbol("CGSCopyManagedDisplaySpaces") else { return nil }
        typealias Copy = @convention(c) (Int32) -> Unmanaged<CFArray>?
        guard let raw = unsafeBitCast(copy, to: Copy.self)(cid) else { return nil }
        let array = raw.takeRetainedValue() as NSArray
        return array.compactMap { $0 as? [String: Any] }
    }

    private static func waitUntilSlideStarts(from: UInt64, uuid: String, cid: Int32) async {
        let deadline = Date().addingTimeInterval(0.15)
        while Date() < deadline {
            if Task.isCancelled { return }
            if isAnimating(uuid, cid: cid) { return }
            let now = currentSpace(on: uuid as CFString, cid: cid)
            if now != 0, now != from { return }
            try? await Task.sleep(nanoseconds: 8_000_000)
        }
    }

    private static func waitWhileAnimating(_ uuid: String, cid: Int32) async {
        let deadline = Date().addingTimeInterval(1.0)
        while Date() < deadline, isAnimating(uuid, cid: cid) {
            if Task.isCancelled { return }
            try? await Task.sleep(nanoseconds: 16_000_000)
        }
        // The current-Space read can lag the end of the slide by a frame.
        try? await Task.sleep(nanoseconds: 32_000_000)
    }

    private static func waitForMove(from: UInt64, uuid: String, cid: Int32) async {
        let deadline = Date().addingTimeInterval(0.85)
        while Date() < deadline {
            if Task.isCancelled { return }
            let now = currentSpace(on: uuid as CFString, cid: cid)
            if now != 0, now != from {
                while Date() < deadline, isAnimating(uuid, cid: cid) {
                    if Task.isCancelled { return }
                    try? await Task.sleep(nanoseconds: 16_000_000)
                }
                return
            }
            try? await Task.sleep(nanoseconds: 16_000_000)
        }
    }

    private static func isAnimating(_ uuid: String, cid: Int32) -> Bool {
        guard let symbol = symbol("SLSManagedDisplayIsAnimating")
            ?? symbol("CGSManagedDisplayIsAnimating") else { return false }
        typealias Anim = @convention(c) (Int32, CFString) -> Bool
        return unsafeBitCast(symbol, to: Anim.self)(cid, uuid as CFString)
    }

    private static func parkCursor(at point: CGPoint) {
        CGWarpMouseCursorPosition(point)
    }

    private static func pointerOnDisplay(_ point: CGPoint) -> Bool {
        let cursor = CGEvent(source: nil)?.location ?? .zero
        guard let screen = WindowLayout.screen(containingQuartz: point) else { return false }
        return WindowLayout.quartzFrame(from: screen.frame).insetBy(dx: -2, dy: -2).contains(cursor)
    }

    private static func displayContains(_ uuid: String, _ bounds: CGRect) -> Bool {
        guard !bounds.isNull, !bounds.isInfinite, bounds.width > 1, bounds.height > 1 else {
            return false
        }
        guard let screen = screen(uuid: uuid) else { return false }
        let frame = WindowLayout.quartzFrame(from: screen.frame).insetBy(dx: -2, dy: -2)
        return frame.contains(CGPoint(x: bounds.midX, y: bounds.midY))
    }

    private static func nearestPoint(on uuid: String, from cursor: CGPoint) -> CGPoint? {
        guard let screen = screen(uuid: uuid) else { return nil }
        let frame = WindowLayout.quartzFrame(from: screen.frame).insetBy(dx: 8, dy: 8)
        return CGPoint(
            x: min(max(cursor.x, frame.minX), frame.maxX),
            y: min(max(cursor.y, frame.minY), frame.maxY)
        )
    }

    private static func screen(uuid: String) -> NSScreen? {
        for screen in NSScreen.screens {
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
            guard let displayID = number as? CGDirectDisplayID else { continue }
            let cfUUID = CGDisplayCreateUUIDFromDisplayID(displayID).takeRetainedValue()
            let string = CFUUIDCreateString(kCFAllocatorDefault, cfUUID) as String
            if string.caseInsensitiveCompare(uuid) == .orderedSame {
                return screen
            }
        }
        return nil
    }

    private static func spaceIDs(for windowID: CGWindowID, cid: Int32) -> [UInt64] {
        guard windowID != 0,
              let copy = symbol("SLSCopySpacesForWindows") ?? symbol("CGSCopySpacesForWindows")
        else { return [] }
        var id = Int32(bitPattern: windowID)
        guard let number = CFNumberCreate(kCFAllocatorDefault, .sInt32Type, &id) else { return [] }
        let windows = [number] as CFArray
        typealias Copy = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
        var found: [UInt64] = []
        for selector: Int32 in [7, 15] {
            guard let raw = unsafeBitCast(copy, to: Copy.self)(cid, selector, windows) else { continue }
            let spaces = raw.takeRetainedValue() as NSArray
            for value in spaces {
                if let sid = uint64(value), !found.contains(sid) {
                    found.append(sid)
                }
            }
            if !found.isEmpty { break }
        }
        return found
    }

    private static func currentSpace(on uuid: CFString, cid: Int32) -> UInt64 {
        guard let get = symbol("SLSManagedDisplayGetCurrentSpace")
            ?? symbol("CGSManagedDisplayGetCurrentSpace") else { return 0 }
        typealias Get = @convention(c) (Int32, CFString) -> UInt64
        return unsafeBitCast(get, to: Get.self)(cid, uuid)
    }

    private static func spaceType(_ space: UInt64, cid: Int32) -> Int32 {
        guard let get = symbol("SLSSpaceGetType") ?? symbol("CGSSpaceGetType") else { return -1 }
        typealias Get = @convention(c) (Int32, UInt64) -> Int32
        return unsafeBitCast(get, to: Get.self)(cid, space)
    }

    private static func int(_ value: Any?) -> Int32 {
        if let number = value as? NSNumber { return number.int32Value }
        return -1
    }

    private static func uint64(_ value: Any?) -> UInt64? {
        guard let value else { return nil }
        if let number = value as? NSNumber { return number.uint64Value }
        if CFGetTypeID(value as CFTypeRef) == CFNumberGetTypeID() {
            var sid: UInt64 = 0
            if CFNumberGetValue(value as! CFNumber, .sInt64Type, &sid) { return sid }
        }
        return nil
    }

    private static func connectionID() -> Int32? {
        guard let symbol = symbol("SLSMainConnectionID") ?? symbol("CGSMainConnectionID") else {
            return nil
        }
        typealias Connect = @convention(c) () -> Int32
        return unsafeBitCast(symbol, to: Connect.self)()
    }

    private static func symbol(_ name: String) -> UnsafeMutableRawPointer? {
        if let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) {
            return symbol
        }
        let path = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
        let handle = dlopen(path, RTLD_NOLOAD | RTLD_NOW) ?? dlopen(path, RTLD_NOW)
        return handle.flatMap { dlsym($0, name) }
    }
}
