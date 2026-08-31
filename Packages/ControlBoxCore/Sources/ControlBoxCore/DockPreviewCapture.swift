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
        let ordered = windows.map(\.windowID).filter { $0 != 0 }
        let wanted = Array(ordered.prefix(maxStills))
        guard !wanted.isEmpty else { return [:] }

        var found: [CGWindowID: NSImage] = [:]
        var missing: [CGWindowID] = []
        let now = Date()
        lock.lock()
        for id in wanted {
            if let hold = images[id], now.timeIntervalSince(hold.0) < imageTTL {
                found[id] = hold.1
            } else {
                missing.append(id)
            }
        }
        lock.unlock()
        if missing.isEmpty {
            return found
        }

        guard let content = await shareableContent() else { return found }
        let missingSet = Set(missing)
        for scWindow in content.windows where missingSet.contains(scWindow.windowID) {
            if let image = await still(window: scWindow, maxPixelWidth: maxPixelWidth) {
                found[scWindow.windowID] = image
                lock.lock()
                images[scWindow.windowID] = (Date(), image)
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
        let source = window.frame
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
        let config = SCStreamConfiguration()
        config.width = Int(width * scale)
        config.height = Int(height * scale)
        config.showsCursor = false
        config.capturesAudio = false
        do {
            let cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
            return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
        } catch {
            return nil
        }
    }
}
