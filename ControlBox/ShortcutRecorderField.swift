import AppKit
import ControlBoxCore
import SwiftUI

struct ShortcutRecorderField: View {
    var shortcut: (virtualKey: UInt16, flags: UInt64)?
    var width: CGFloat = 168
    var isRecording: Bool
    var onBegin: () -> Void
    var onRecord: (UInt16, UInt64) -> Void
    var onClear: () -> Void
    var onCancel: () -> Void

    var body: some View {
        ShortcutRecorderNSView(
            shortcut: shortcut,
            isRecording: isRecording,
            onBegin: onBegin,
            onRecord: onRecord,
            onClear: onClear,
            onCancel: onCancel
        )
        .frame(width: width, height: 24)
    }
}

private struct ShortcutRecorderNSView: NSViewRepresentable {
    var shortcut: (virtualKey: UInt16, flags: UInt64)?
    var isRecording: Bool
    var onBegin: () -> Void
    var onRecord: (UInt16, UInt64) -> Void
    var onClear: () -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> InnerView {
        let view = InnerView()
        view.onBegin = onBegin
        view.onRecord = onRecord
        view.onClear = onClear
        view.onCancel = onCancel
        view.apply(shortcut: shortcut, requestedRecording: isRecording)
        return view
    }

    func updateNSView(_ view: InnerView, context: Context) {
        view.onBegin = onBegin
        view.onRecord = onRecord
        view.onClear = onClear
        view.onCancel = onCancel
        view.apply(shortcut: shortcut, requestedRecording: isRecording)
    }

    final class InnerView: NSView {
        var onBegin: (() -> Void)?
        var onRecord: ((UInt16, UInt64) -> Void)?
        var onClear: (() -> Void)?
        var onCancel: (() -> Void)?

        private var shortcut: (UInt16, UInt64)?
        private var recording = false
        private var liveFlags = CGEventFlags(rawValue: 0)
        private var monitor: Any?
        private var awaitingKeyUp = false
        private let label = CenteredShortcutLabel()
        private let recordButton = NSButton(title: "", target: nil, action: nil)

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.cornerRadius = 6
            layer?.borderWidth = 1
            addSubview(label)

            recordButton.bezelStyle = .circular
            recordButton.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Record shortcut")
            recordButton.imagePosition = .imageOnly
            recordButton.isBordered = false
            recordButton.target = self
            recordButton.action = #selector(toggleRecording)
            recordButton.toolTip = "Record Shortcut"
            addSubview(recordButton)
        }

        required init?(coder: NSCoder) {
            nil
        }

        deinit {
            stopMonitor()
            ShortcutCapture.setActive(false)
        }

        override var acceptsFirstResponder: Bool { true }

        override func layout() {
            super.layout()
            let buttonSize: CGFloat = 18
            recordButton.frame = NSRect(
                x: bounds.maxX - buttonSize - 4,
                y: (bounds.height - buttonSize) / 2,
                width: buttonSize,
                height: buttonSize
            )
            label.frame = NSRect(
                x: 8,
                y: 0,
                width: max(40, recordButton.frame.minX - 10),
                height: bounds.height
            )
        }

        override func mouseDown(with event: NSEvent) {
            super.mouseDown(with: event)
            if !recording {
                beginRecording()
            }
        }

        @objc private func toggleRecording() {
            if recording {
                cancelRecording()
            } else {
                beginRecording()
            }
        }

        func apply(shortcut: (UInt16, UInt64)?, requestedRecording: Bool) {
            self.shortcut = shortcut
            if requestedRecording && !recording {
                beginRecording(notify: false)
            } else if !requestedRecording && recording {
                recording = false
                if !awaitingKeyUp {
                    stopMonitor()
                    ShortcutCapture.setActive(false)
                }
            }
            refresh()
        }

        private func beginRecording(notify: Bool = true) {
            awaitingKeyUp = false
            recording = true
            liveFlags = []
            ShortcutCapture.setActive(true)
            window?.makeFirstResponder(self)
            if window == nil {
                DispatchQueue.main.async { [weak self] in
                    self?.window?.makeFirstResponder(self)
                }
            }
            startMonitor()
            refresh()
            if notify {
                onBegin?()
            }
        }

        private func cancelRecording() {
            awaitingKeyUp = false
            recording = false
            stopMonitor()
            ShortcutCapture.setActive(false)
            refresh()
            onCancel?()
        }

        private func refresh() {
            let active = recording
            layer?.borderColor = (active ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
            layer?.backgroundColor = (active
                ? NSColor.controlAccentColor.withAlphaComponent(0.12)
                : NSColor.controlBackgroundColor
            ).cgColor
            label.textColor = active ? .controlAccentColor : .labelColor
            recordButton.image = NSImage(
                systemSymbolName: active ? "stop.circle.fill" : "record.circle",
                accessibilityDescription: active ? "Stop recording" : "Record shortcut"
            )
            recordButton.contentTintColor = active ? .systemRed : .secondaryLabelColor
            recordButton.toolTip = active ? "Cancel" : "Record Shortcut"

            if active {
                let prefix = ShortcutFormatter.modifierGlyphs(liveFlags)
                label.stringValue = prefix.isEmpty ? "Type Shortcut" : prefix
            } else if let shortcut {
                label.stringValue = ShortcutFormatter.describe(virtualKey: shortcut.0, flags: shortcut.1)
            } else {
                label.stringValue = "Record Shortcut"
            }
        }

        private func startMonitor() {
            stopMonitor()
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
                guard let self, self.recording || self.awaitingKeyUp else { return event }
                return self.handle(event)
            }
        }

        private func stopMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func finishHold() {
            awaitingKeyUp = false
            recording = false
            stopMonitor()
            ShortcutCapture.setActive(false)
            refresh()
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            if event.type == .keyUp {
                if awaitingKeyUp {
                    finishHold()
                    return nil
                }
                return recording ? nil : event
            }

            let flags = Self.capturedFlags(from: event)
            if event.type == .flagsChanged {
                liveFlags = CGEventFlags(rawValue: flags)
                if awaitingKeyUp, ModifierChords.normalized(liveFlags).isEmpty {
                    finishHold()
                } else {
                    refresh()
                }
                return nil
            }

            if awaitingKeyUp {
                return nil
            }

            let keyCode = UInt16(event.keyCode)
            if keyCode == 53 {
                cancelRecording()
                return nil
            }
            if keyCode == 51 || keyCode == 117 {
                awaitingKeyUp = false
                recording = false
                stopMonitor()
                shortcut = nil
                ShortcutCapture.setActive(false)
                refresh()
                onClear?()
                return nil
            }

            awaitingKeyUp = true
            recording = false
            shortcut = (keyCode, flags)
            refresh()
            onRecord?(keyCode, flags)
            return nil
        }

        private static func capturedFlags(from event: NSEvent) -> UInt64 {
            let allowed: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
            return UInt64(event.modifierFlags.intersection(allowed).rawValue)
        }
    }
}

private final class CenteredShortcutLabel: NSView {
    var stringValue = "" {
        didSet { needsDisplay = true }
    }
    var textColor: NSColor = .labelColor {
        didSet { needsDisplay = true }
    }
    var font: NSFont = .systemFont(ofSize: 13, weight: .medium)

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: style
        ]
        let text = stringValue as NSString
        let size = text.size(withAttributes: attributes)
        let rect = CGRect(
            x: 0,
            y: ((bounds.height - size.height) / 2).rounded(),
            width: bounds.width,
            height: max(size.height, 1)
        )
        text.draw(in: rect, withAttributes: attributes)
    }
}
