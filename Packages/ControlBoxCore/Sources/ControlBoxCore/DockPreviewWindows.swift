import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum DockPreviewWindows {
    private static let minWidth: CGFloat = 80
    private static let minHeight: CGFloat = 52

    static func list(app: NSRunningApplication) -> [DockPreviewWindow] {
        let pids = relatedPIDs(for: app)
        let cg = cgEntries(pids: pids)
        var claimed = Set<CGWindowID>()
        var windows: [DockPreviewWindow] = []
        var seenAX: [AXUIElement] = []

        for pid in pids {
            for ax in copyAXWindows(pid: pid) {
                if seenAX.contains(where: { CFEqual($0, ax) }) { continue }
                guard isStandardWindow(ax) else { continue }
                let frame = DockAX.axFrame(ax) ?? .zero
                let minimized = DockAX.bool(ax, kAXMinimizedAttribute as CFString)
                if isParked(frame) { continue }
                if !minimized, isTitleBarStrip(frame) { continue }
                if !minimized, frame.width < minWidth || frame.height < minHeight { continue }
                seenAX.append(ax)
                let title = cleanedTitle(axTitle(ax), fallback: app.localizedName ?? "")
                let match = matchCG(cg, bounds: frame, title: title, claimed: claimed)
                if let id = match?.windowID, id != 0 {
                    claimed.insert(id)
                }
                windows.append(
                    DockPreviewWindow(
                        windowID: match?.windowID ?? 0,
                        pid: pid,
                        title: title,
                        bounds: match?.bounds ?? frame,
                        isMinimized: minimized,
                        isOnScreen: match?.onScreen ?? !minimized
                    )
                )
            }
        }

        var listedBounds = windows.map(\.bounds)
        let extras = cg
            .filter { entry in
                if entry.windowID != 0, claimed.contains(entry.windowID) { return false }
                if entry.onScreen { return false }
                return isRealContentWindow(entry.bounds, listed: listedBounds)
            }
            .sorted { area($0.bounds) > area($1.bounds) }
        for entry in extras {
            if isNested(entry.bounds, in: listedBounds) { continue }
            claimed.insert(entry.windowID)
            listedBounds.append(entry.bounds)
            windows.append(
                DockPreviewWindow(
                    windowID: entry.windowID,
                    pid: entry.pid,
                    title: cleanedTitle(entry.title.isEmpty ? nil : entry.title, fallback: app.localizedName ?? ""),
                    bounds: entry.bounds,
                    isMinimized: false,
                    isOnScreen: false
                )
            )
        }

        windows = pruneChrome(windows)
        windows.sort { a, b in
            if a.isOnScreen != b.isOnScreen { return a.isOnScreen && !b.isOnScreen }
            if a.isMinimized != b.isMinimized { return !a.isMinimized && b.isMinimized }
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
        return windows
    }

    private static func relatedPIDs(for app: NSRunningApplication) -> Set<pid_t> {
        var pids: Set<pid_t> = [app.processIdentifier]
        let bid = app.bundleIdentifier ?? ""
        for running in NSWorkspace.shared.runningApplications {
            if running.processIdentifier == app.processIdentifier { continue }
            guard let other = running.bundleIdentifier, !bid.isEmpty else { continue }
            if other == bid
                || (bid.hasPrefix("com.google.Chrome") && other.hasPrefix("com.google.Chrome")) {
                pids.insert(running.processIdentifier)
            }
        }
        return pids
    }

    private struct CGEntry {
        var windowID: CGWindowID
        var pid: pid_t
        var title: String
        var bounds: CGRect
        var onScreen: Bool
    }

    private static func cgEntries(pids: Set<pid_t>) -> [CGEntry] {
        let options: CGWindowListOption = [.excludeDesktopElements]
        let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        var entries: [CGEntry] = []
        for entry in info {
            guard let pid = entry[kCGWindowOwnerPID as String] as? pid_t, pids.contains(pid) else {
                continue
            }
            let layer = entry[kCGWindowLayer as String] as? Int ?? 0
            guard layer == 0 else { continue }
            let alpha = entry[kCGWindowAlpha as String] as? Double ?? 1
            guard alpha > 0.05 else { continue }
            let owner = entry[kCGWindowOwnerName as String] as? String ?? ""
            if ignoredOwners.contains(owner) { continue }
            let name = entry[kCGWindowName as String] as? String ?? ""
            if name == DockPreview.overlayTitle || name == WindowThrowOverlay.windowTitle {
                continue
            }
            guard let bounds = cgBounds(entry[kCGWindowBounds as String] as? [String: Any]) else {
                continue
            }
            if isParked(bounds) { continue }
            let windowID = CGWindowID((entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0)
            entries.append(
                CGEntry(
                    windowID: windowID,
                    pid: pid,
                    title: name,
                    bounds: bounds,
                    onScreen: (boolNumber(entry[kCGWindowIsOnscreen as String]) ?? 0) > 0
                )
            )
        }
        return entries
    }

    private static func matchCG(
        _ entries: [CGEntry],
        bounds: CGRect,
        title: String,
        claimed: Set<CGWindowID>
    ) -> CGEntry? {
        let unused = entries.filter { $0.windowID == 0 || !claimed.contains($0.windowID) }
        if !title.isEmpty {
            if let exact = unused.first(where: { !$0.title.isEmpty && $0.title == title }) {
                return exact
            }
        }
        var best: CGEntry?
        var bestArea: CGFloat = 0
        for entry in unused {
            let overlap = entry.bounds.intersection(bounds)
            let area = overlap.width * overlap.height
            let cgArea = max(entry.bounds.width * entry.bounds.height, 1)
            let axArea = max(bounds.width * bounds.height, 1)
            guard area / cgArea >= 0.55, area / axArea >= 0.55 else { continue }
            if area > bestArea {
                bestArea = area
                best = entry
            }
        }
        return best
    }

    private static func copyAXWindows(pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.08)
        return copyArray(app, kAXWindowsAttribute as CFString) ?? []
    }

    static func axWindow(for listed: DockPreviewWindow) -> AXUIElement? {
        let windows = copyAXWindows(pid: listed.pid)
        if !listed.title.isEmpty {
            if let exact = windows.first(where: { axTitle($0) == listed.title }) {
                return exact
            }
        }
        return matchAX(windows, bounds: listed.bounds, title: listed.title)
    }

    private static func matchAX(_ windows: [AXUIElement], bounds: CGRect, title: String) -> AXUIElement? {
        var best: AXUIElement?
        var bestArea: CGFloat = 0
        for window in windows {
            let axTitle = axTitle(window) ?? ""
            if !title.isEmpty, !axTitle.isEmpty, title == axTitle {
                return window
            }
            guard let frame = DockAX.axFrame(window) else { continue }
            let overlap = frame.intersection(bounds)
            let area = overlap.width * overlap.height
            let cgArea = max(bounds.width * bounds.height, 1)
            let axArea = max(frame.width * frame.height, 1)
            guard area / cgArea >= 0.55, area / axArea >= 0.55 else { continue }
            if area > bestArea {
                bestArea = area
                best = window
            }
        }
        return best
    }

    private static func isStandardWindow(_ element: AXUIElement) -> Bool {
        let role = DockAX.string(element, kAXRoleAttribute as CFString)
        if role == "AXPopover" || role == "AXUnknown" { return false }
        if !role.isEmpty, role != kAXWindowRole as String {
            return false
        }
        let sub = DockAX.string(element, kAXSubroleAttribute as CFString)
        if rejectedSubroles.contains(sub) { return false }
        if sub.isEmpty { return true }
        return acceptedSubroles.contains(sub)
    }

    /// Calendar’s event inspector and mini month are their own CG/AX windows.
    /// They often sit beside the host (not nested) and can still be
    /// `AXStandardWindow`. Other Spaces of the same app reuse display
    /// coordinates, so only drop surfaces that are clearly chrome-sized
    /// next to a real window on that display.
    private static func pruneChrome(_ items: [DockPreviewWindow]) -> [DockPreviewWindow] {
        let groups = Dictionary(grouping: items) { displayKey($0.bounds) }
        var kept: [DockPreviewWindow] = []
        for group in groups.values {
            let maxArea = group.map { area($0.bounds) }.max() ?? 0
            let cutoff = maxArea * 0.35
            for item in group {
                if item.isMinimized {
                    kept.append(item)
                    continue
                }
                if area(item.bounds) < cutoff { continue }
                let others = group.compactMap { other -> CGRect? in
                    guard other.id != item.id else { return nil }
                    return other.bounds
                }
                if isNested(item.bounds, in: others) { continue }
                kept.append(item)
            }
        }
        return kept
    }

    private static func displayKey(_ bounds: CGRect) -> String {
        let point = CGPoint(x: bounds.midX, y: bounds.midY)
        if let screen = WindowLayout.screen(containingQuartz: point) {
            let frame = screen.frame
            return "\(Int(frame.minX)),\(Int(frame.minY)),\(Int(frame.width)),\(Int(frame.height))"
        }
        return "unknown"
    }

    private static func isNested(_ bounds: CGRect, in hosts: [CGRect]) -> Bool {
        let childArea = area(bounds)
        guard childArea > 0 else { return true }
        for host in hosts {
            let hostArea = area(host)
            guard hostArea >= childArea * 1.35 else { continue }
            if host.insetBy(dx: -12, dy: -12).contains(bounds) { return true }
            let overlap = host.intersection(bounds)
            guard !overlap.isNull, !overlap.isInfinite else { continue }
            if area(overlap) / childArea >= 0.55 { return true }
        }
        return false
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        max(rect.width, 0) * max(rect.height, 0)
    }

    /// Off-screen CG windows on another Space still have a real frame on a display.
    /// Menu-bar clones (~30pt) and Mail’s 500×500 placeholder are not windows.
    private static func isRealContentWindow(_ bounds: CGRect, listed: [CGRect]) -> Bool {
        if isParked(bounds) { return false }
        if isTitleBarStrip(bounds) { return false }
        if bounds.width < minWidth || bounds.height < minHeight { return false }
        if abs(bounds.width - 500) < 8, abs(bounds.height - 500) < 8 { return false }
        if isNested(bounds, in: listed) { return false }
        return true
    }

    private static func isTitleBarStrip(_ bounds: CGRect) -> Bool {
        guard bounds.height > 0, bounds.height <= 36 else { return false }
        return NSScreen.screens.contains { abs($0.frame.width - bounds.width) < 8 }
    }

    private static func isParked(_ bounds: CGRect) -> Bool {
        bounds.minX <= -9000 || bounds.minY <= -9000
    }

    private static func boolNumber(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let value = value as? Double { return value }
        if let value = value as? Bool { return value ? 1 : 0 }
        return nil
    }

    private static func axTitle(_ element: AXUIElement?) -> String? {
        guard let element else { return nil }
        let title = DockAX.string(element, kAXTitleAttribute as CFString)
        return title.isEmpty ? nil : title
    }

    private static func cleanedTitle(_ title: String?, fallback: String) -> String {
        let trimmed = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func copyArray(_ element: AXUIElement, _ attribute: CFString) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let array = value as? [AXUIElement] else {
            return nil
        }
        return array
    }

    private static func cgBounds(_ dict: [String: Any]?) -> CGRect? {
        guard let dict else { return nil }
        func number(_ key: String) -> CGFloat? {
            if let value = dict[key] as? NSNumber { return CGFloat(truncating: value) }
            return nil
        }
        guard let x = number("X"), let y = number("Y"),
              let w = number("Width"), let h = number("Height") else { return nil }
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private static let acceptedSubroles: Set<String> = [
        "AXStandardWindow",
        "AXDialog",
        "AXSystemDialog",
        "AXFloatingWindow"
    ]

    private static let rejectedSubroles: Set<String> = [
        "AXUnknown",
        "AXPopover",
        "AXSheet",
        "AXDrawer"
    ]

    private static let ignoredOwners: Set<String> = [
        "Window Server",
        "Dock",
        "Control Center",
        "Notification Centre",
        "Notification Center",
        "SystemUIServer",
        "Spotlight",
        "loginwindow",
        "Screenshot"
    ]
}
