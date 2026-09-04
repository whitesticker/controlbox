import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

enum DockPreviewCapture {
    private static let lock = NSLock()
    private static var contentHold: (Date, SCShareableContent)?
    private static var images: [CGWindowID: (Date, NSImage)] = [:]
    private static let contentTTL: TimeInterval = 2.5
    private static let imageTTL: TimeInterval = 8
    private static let maxStills = 6

    static func stills(
        for windows: [DockPreviewWindow],
        maxPixelWidth: CGFloat
    ) async -> [CGWindowID: NSImage] {
        guard CGPreflightScreenCaptureAccess() else { return [:] }
        let ordered = windows.filter { $0.windowID != 0 }
        let wanted = Array(ordered.prefix(maxStills))
        guard !wanted.isEmpty else { return [:] }

        var found: [CGWindowID: NSImage] = [:]
        var missing: [DockPreviewWindow] = []
        let now = Date()
        lock.lock()
        for window in wanted {
            if let hold = images[window.windowID], now.timeIntervalSince(hold.0) < imageTTL {
                found[window.windowID] = hold.1
            } else {
                missing.append(window)
            }
        }
        lock.unlock()
        if missing.isEmpty {
            return found
        }

        let content = await shareableContent()
        let missingSet = Set(missing.map(\.windowID))
        if let content {
            for window in missing {
                let scWindow = content.windows.first(where: { $0.windowID == window.windowID })
                    ?? matchShareable(content.windows, to: window)
                guard let scWindow else { continue }
                if let image = await still(window: scWindow, maxPixelWidth: maxPixelWidth) {
                    found[window.windowID] = image
                    lock.lock()
                    images[window.windowID] = (Date(), image)
                    lock.unlock()
                }
            }
        }
        for window in missing where found[window.windowID] == nil && missingSet.contains(window.windowID) {
            if let image = cgStill(windowID: window.windowID, bounds: window.bounds, maxPixelWidth: maxPixelWidth) {
                found[window.windowID] = image
                lock.lock()
                images[window.windowID] = (Date(), image)
                lock.unlock()
            }
        }
        return found
    }

    private static func shareableContent() async -> SCShareableContent? {
        let now = Date()
        lock.lock()
        if let hold = contentHold, now.timeIntervalSince(hold.0) < contentTTL {
            let cached = hold.1
            lock.unlock()
            return cached
        }
        lock.unlock()
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            lock.lock()
            contentHold = (Date(), content)
            lock.unlock()
            return content
        } catch {
            return nil
        }
    }

    private static func still(window: SCWindow, maxPixelWidth: CGFloat) async -> NSImage? {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = min(max(NSScreen.main?.backingScaleFactor ?? 2, 1), 2)
        let size = thumbnailSize(source: window.frame, maxPixelWidth: maxPixelWidth)
        let config = SCStreamConfiguration()
        config.width = Int(size.width * scale)
        config.height = Int(size.height * scale)
        config.showsCursor = false
        config.capturesAudio = false
        do {
            let cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
            return NSImage(cgImage: cgImage, size: size)
        } catch {
            return nil
        }
    }

    /// Other-Space windows are often missing from `SCShareableContent` on a
    /// multi-display Mac. ScreenCaptureKit stays the primary path; this is
    /// only for IDs that path did not still.
    private static func cgStill(
        windowID: CGWindowID,
        bounds: CGRect,
        maxPixelWidth: CGFloat
    ) -> NSImage? {
        let options: CGWindowImageOption = [.boundsIgnoreFraming, .bestResolution]
        guard let cgImage = CGWindowListCreateImage(
            .null,
            [.optionIncludingWindow, .excludeDesktopElements],
            windowID,
            options
        ) else { return nil }
        guard cgImage.width >= 8, cgImage.height >= 8 else { return nil }
        let source = bounds.width > 1 && bounds.height > 1
            ? bounds
            : CGRect(x: 0, y: 0, width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
        let size = thumbnailSize(source: source, maxPixelWidth: maxPixelWidth)
        return NSImage(cgImage: cgImage, size: size)
    }

    private static func matchShareable(_ windows: [SCWindow], to listed: DockPreviewWindow) -> SCWindow? {
        let listedArea = max(listed.bounds.width * listed.bounds.height, 1)
        var best: SCWindow?
        var bestArea: CGFloat = 0
        for window in windows {
            guard window.owningApplication?.processID == listed.pid else { continue }
            let frame = window.frame
            let overlap = frame.intersection(listed.bounds)
            let area = overlap.width * overlap.height
            let scArea = max(frame.width * frame.height, 1)
            guard area / scArea >= 0.55, area / listedArea >= 0.55 else { continue }
            if area > bestArea {
                bestArea = area
                best = window
            }
        }
        return best
    }

    private static func thumbnailSize(source: CGRect, maxPixelWidth: CGFloat) -> NSSize {
        let ratio = source.height > 0 ? source.width / source.height : 16 / 10
        let height: CGFloat
        let width: CGFloat
        if ratio < 1 {
            height = max(maxPixelWidth, 160)
            width = max(height * ratio, 80)
        } else {
            width = max(maxPixelWidth, 120)
            height = max(width / max(ratio, 0.4), 80)
        }
        return NSSize(width: width, height: height)
    }
}
