import SwiftUI

struct Inspector: View {
    @EnvironmentObject private var store: LabStore

    var body: some View {
        Form {
            Section {
                Picker("Chart style", selection: $store.design.style) {
                    ForEach(HistoryDesign.Style.userChoices) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Time range", selection: $store.range) {
                    ForEach(HistoryRange.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if store.design.style == .bars {
                    Picker("Each bar (\(store.range.title))", selection: barSeconds) {
                        ForEach(HistoryDesign.barChoices(store.range), id: \.self) { seconds in
                            Text("\(Self.duration(seconds)) · \(Int(store.range.duration / seconds)) bars").tag(seconds)
                        }
                    }
                }
                Toggle("Compress network & disk spikes", isOn: $store.design.compressSpikes)
                Toggle("Show Avg / Peak / Total", isOn: $store.design.showStats)
                Picker("Hover value", selection: $store.design.readout) {
                    ForEach(HistoryDesign.Readout.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Control Box settings")
            } footer: {
                Text("The only options users get, in System Monitor → History. Time range is also the 5m / 1h / 24h control in the menu, and the last pick is remembered.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Preview data") {
                Picker("Metric", selection: $store.metric) {
                    ForEach(Metric.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
                }
                Picker("Scenario", selection: $store.scenario) {
                    ForEach(Scenario.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledContent("Seed") {
                    HStack {
                        Text("\(store.seed)").monospacedDigit()
                        Button("Shuffle") { store.seed = UInt64.random(in: 1...9999) }
                    }
                }
                Toggle("Live (append a bucket as time passes)", isOn: $store.live)
            }

            Section("Design: layout (fixed in Control Box)") {
                slider("Panel width", $store.design.panelWidth, 260...460, step: 10)
                slider("Chart height", $store.design.chartHeight, 50...220, step: 5)
                slider("Padding", $store.design.padding, 4...20, step: 1)
                slider("Corner radius", $store.design.cornerRadius, 0...16, step: 1)
            }

            Section("Design: chart") {
                Picker("All styles", selection: $store.design.style) {
                    ForEach(HistoryDesign.Style.allCases) { Text($0.title).tag($0) }
                }
                Picker("Curve", selection: $store.design.interpolation) {
                    ForEach(HistoryDesign.Interpolation.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("In / out layout", selection: $store.design.dualLayout) {
                    ForEach(HistoryDesign.DualLayout.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(!store.metric.isDual)
                slider("Line width", $store.design.lineWidth, 0.5...3, step: 0.25, format: "%.2f")
                slider("Fill opacity", $store.design.fillOpacity, 0...1, step: 0.05, format: "%.2f")
                slider("Bar gap", $store.design.barGap, 0...0.8, step: 0.05, format: "%.2f")
                    .disabled(store.design.style != .bars)
                Toggle("Gridlines", isOn: $store.design.showGrid)
                Toggle("Y-axis labels", isOn: $store.design.showYAxis)
                Toggle("Time labels", isOn: $store.design.showTimeLabels)
                slider("Value size", $store.design.valueSize, 12...32, step: 1)
                Toggle("Range control", isOn: $store.design.showRangePicker)
            }

            Section("Design: look") {
                Picker("Background", selection: $store.design.background) {
                    ForEach(HistoryDesign.Background.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Palette", selection: $store.design.palette) {
                    ForEach(HistoryDesign.Palette.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Appearance", selection: $store.appearance) {
                    ForEach(LabAppearance.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section {
                HStack {
                    Button("Copy Design JSON") { store.copyDesignJSON() }
                    Spacer()
                    Button("Reset Design") { store.resetDesign() }
                }
            } footer: {
                Text("The design is saved as you tweak it. The menu bar chart icon shows the same panel inside a real NSMenu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var barSeconds: Binding<TimeInterval> {
        Binding(
            get: { store.design.barSeconds(store.range) },
            set: { store.design.setBarSeconds($0, for: store.range) }
        )
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "\(Int(seconds)) s" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min" }
        return "\(Int(seconds / 3600)) h"
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
}
