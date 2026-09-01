import AppKit
import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

enum ScreenshotExport {
    static var directory: URL? {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--export-screenshots"),
              args.indices.contains(flag + 1)
        else { return nil }
        return URL(fileURLWithPath: args[flag + 1], isDirectory: true)
    }

    static var isActive: Bool { directory != nil }

    @MainActor
    static func runIfRequested() {
        guard let directory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        Task { @MainActor in
            if !CGPreflightScreenCaptureAccess() {
                CGRequestScreenCaptureAccess()
                try? await Task.sleep(for: .seconds(2))
            }
            for _ in 0..<40 {
                if WindowActions.openMain != nil { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            WindowActions.openMain?("main")
            NSApp.activate()
            try? await Task.sleep(for: .milliseconds(900))
            let panes: [(SidebarItem, String)] = [
                (.displays, "displays"),
                (.nightShift, "night-shift"),
                (.displayArrangement, "arrangement"),
                (.sound, "sound"),
                (.caffeinate, "caffeinate"),
                (.systemMonitor, "system-monitor"),
                (.pointerScroll, "pointer"),
                (.windowGrab, "windows"),
                (.capsLock, "caps-lock"),
                (.dockPreview, "dock-previews"),
            ]
            for (item, name) in panes {
                PaneNavigation.open(item)
                try? await Task.sleep(for: .milliseconds(700))
                await captureVisibleWindow(to: directory.appendingPathComponent("\(name).png"))
            }
            NSApp.terminate(nil)
        }
    }

    @MainActor
    private static func captureVisibleWindow(to url: URL) async {
        let window = NSApp.windows.first {
            $0.isVisible && $0.canBecomeKey && ($0.title == "Control Box" || $0.identifier?.rawValue == "main")
        } ?? NSApp.windows.first { $0.isVisible && $0.contentView != nil }
        guard let window else {
            fputs("screenshot: no window for \(url.lastPathComponent)\n", stderr)
            return
        }
        let targetID = CGWindowID(window.windowNumber)
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let scWindow = content.windows.first(where: { $0.windowID == targetID })
                    ?? content.windows.first(where: { $0.owningApplication?.bundleIdentifier == "com.whitesticker.controlbox" && $0.frame.width > 800 })
            else {
                fputs("screenshot: ScreenCaptureKit missed \(url.lastPathComponent) id=\(targetID)\n", stderr)
                return
            }
            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            let scale = min(max(window.backingScaleFactor, 1), 2)
            let config = SCStreamConfiguration()
            config.width = Int(scWindow.frame.width * scale)
            config.height = Int(scWindow.frame.height * scale)
            config.showsCursor = false
            config.capturesAudio = false
            let cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
            let dest = url as CFURL
            guard let destRef = CGImageDestinationCreateWithURL(dest, UTType.png.identifier as CFString, 1, nil) else {
                fputs("screenshot: dest failed \(url.lastPathComponent)\n", stderr)
                return
            }
            CGImageDestinationAddImage(destRef, cgImage, nil)
            if CGImageDestinationFinalize(destRef) {
                print("screenshot: wrote \(url.path) \(cgImage.width)x\(cgImage.height)")
            } else {
                fputs("screenshot: finalize failed \(url.lastPathComponent)\n", stderr)
            }
        } catch {
            fputs("screenshot: \(error)\n", stderr)
        }
    }
}
