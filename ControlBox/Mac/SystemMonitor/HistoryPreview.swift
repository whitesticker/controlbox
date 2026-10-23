import AppKit
import SwiftUI

/// Live history panel in System Monitor → History, outside any menu, so it
/// can be hovered and screenshotted normally. Option-click opens the
/// Design lab.
struct HistoryPreview: View {
    @StateObject private var feed = HistoryFeed(metric: .cpu)
    @ObservedObject private var preferences = PreferencesStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HistoryMetricPicker(metric: $feed.metric)
            HistoryPanel(
                history: feed.history,
                settings: preferences.historySettings,
                design: preferences.historyDesign
            ) { preferences.historyRange = $0 }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                if NSEvent.modifierFlags.contains(.option) {
                    HistoryDesignLab.show()
                }
            }
            if !preferences.menuBarEnabled {
                Text("History records while Show in menu bar is on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { feed.start() }
        .onDisappear { feed.stop() }
    }
}

/// The same charts the menu shows: one per dashboard row, and for Sensors
/// one per section of its submenu (power, fans, each temperature group),
/// listing only sections this Mac has recorded.
struct HistoryMetricPicker: View {
    @Binding var metric: HistoryMetric

    private var sensorMetrics: [HistoryMetric] {
        HistoryMetric.sensorCases.filter { $0 == metric || HistoryStore.shared.hasData($0) }
    }

    var body: some View {
        Picker("Preview", selection: $metric) {
            ForEach(HistoryMetric.systemCases, id: \.self, content: item)
            Section("Sensors") {
                ForEach(sensorMetrics, id: \.self, content: item)
            }
        }
    }

    private func item(_ metric: HistoryMetric) -> some View {
        Label(metric.title, systemImage: metric.systemImage).tag(metric)
    }
}

/// The six user options, shared by the pane and the Design lab.
struct HistorySettingsControls: View {
    @ObservedObject private var store = PreferencesStore.shared

    var body: some View {
        Picker("Chart style", selection: $store.historyStyle) {
            ForEach(HistoryStyle.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        Picker("Time range", selection: $store.historyRange) {
            ForEach(HistoryRange.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        if store.historyStyle != .line {
            let noun = store.historyStyle == .candles ? "candle" : "bar"
            Picker("Each \(noun) (\(store.historyRange.title))", selection: barSeconds) {
                ForEach(store.historyRange.barChoices, id: \.self) { seconds in
                    Text("\(Self.duration(seconds)) · \(Int(store.historyRange.duration / seconds)) \(noun)s")
                        .tag(seconds)
                }
            }
        }
        Toggle("Compress network & disk spikes", isOn: $store.historyCompressSpikes)
        Toggle("Show Avg / Peak / Total", isOn: $store.historyShowStats)
        Picker("Hover value", selection: $store.historyReadout) {
            ForEach(HistoryReadout.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    private var barSeconds: Binding<TimeInterval> {
        Binding(
            get: { store.historyBarSeconds(for: store.historyRange) },
            set: { store.setHistoryBarSeconds($0, for: store.historyRange) }
        )
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "\(Int(seconds)) s" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min" }
        return "\(Int(seconds / 3600)) h"
    }
}

// MARK: - Design lab

/// Hidden window with every layout value of the history panel (what
/// `Prototypes/HistoryLab` was for), on live data. Changes save as the
/// design the menu uses.
@MainActor
enum HistoryDesignLab {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: HistoryDesignLabView()))
            window.title = "History Design Lab"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 920, height: 680))
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

struct HistoryDesignLabView: View {
    @StateObject private var feed = HistoryFeed(metric: .cpu)
    @ObservedObject private var store = PreferencesStore.shared

    var body: some View {
        HStack(spacing: 0) {
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 12) {
                    HistoryMetricPicker(metric: $feed.metric)
                        .frame(width: 260)
                    HistoryPanel(
                        history: feed.history,
                        settings: store.historySettings,
                        design: store.historyDesign
                    ) { store.historyRange = $0 }
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.regularMaterial)
                            .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
                    )
                }
                .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            Form {
                Section("User settings") {
                    HistorySettingsControls()
                }
                Section("Layout") {
                    slider("Panel width", $store.historyDesign.panelWidth, 240...460, step: 10)
                    slider("Chart height", $store.historyDesign.chartHeight, 60...220, step: 5)
                    slider("Padding", $store.historyDesign.padding, 4...20, step: 1)
                    slider("Value size", $store.historyDesign.valueSize, 12...32, step: 1)
                }
                Section("Chart") {
                    Picker("Curve", selection: $store.historyDesign.curve) {
                        ForEach(HistoryDesign.Curve.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    slider("Line width", $store.historyDesign.lineWidth, 0.5...3, step: 0.25, format: "%.2f")
                    slider("Fill opacity", $store.historyDesign.fillOpacity, 0...1, step: 0.05, format: "%.2f")
                    slider("Bar gap", $store.historyDesign.barGap, 0...0.8, step: 0.05, format: "%.2f")
                    Toggle("Gridlines", isOn: $store.historyDesign.showGrid)
                    Toggle("Y-axis labels", isOn: $store.historyDesign.showYAxis)
                    Toggle("Time labels", isOn: $store.historyDesign.showTimeLabels)
                }
                Section {
                    HStack {
                        Button("Copy Design JSON") { copyDesignJSON() }
                        Spacer()
                        Button("Reset to Tuned") { store.historyDesign = .tuned }
                            .disabled(store.historyDesign == .tuned)
                    }
                } footer: {
                    Text("Saved as you change it. The menu's history submenus use this design.")
                }
            }
            .formStyle(.grouped)
            .frame(width: 340)
        }
        .onAppear { feed.start() }
        .onDisappear { feed.stop() }
    }

    private func slider(
        _ title: String,
        _ value: Binding<Double>,
        _ range: ClosedRange<Double>,
        step: Double,
        format: String = "%.0f"
    ) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: range, step: step)
                Text(String(format: format, value.wrappedValue))
                    .monospacedDigit()
                    .frame(width: 36, alignment: .trailing)
            }
        }
    }

    private func copyDesignJSON() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(store.historyDesign),
              let json = String(data: data, encoding: .utf8)
        else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(json, forType: .string)
    }
}
