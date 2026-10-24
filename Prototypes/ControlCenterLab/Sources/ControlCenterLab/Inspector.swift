import SwiftUI

struct Inspector: View {
    @ObservedObject var store: LabStore

    var body: some View {
        Form {
            Section("Panel") {
                slider("Width", $store.design.panelWidth, 260...420, step: 4)
                slider("Padding", $store.design.panelPadding, 4...24, step: 1)
                slider("Corner radius", $store.design.panelCornerRadius, 8...36, step: 1)
                slider("Spacing", $store.design.spacing, 4...20, step: 1)
                Toggle("Footer", isOn: $store.design.footer)
                picker("Footer style", $store.design.footerStyle)
                    .disabled(!store.design.footer)
            }

            Section("Modules") {
                picker("Surface", $store.design.surface)
                slider("Corner radius", $store.design.moduleCornerRadius, 4...32, step: 1)
                slider("Row height", $store.design.rowHeight, 44...96, step: 1)
                slider("Icon size", $store.design.iconSize, 22...48, step: 1)
                slider("Title size", $store.design.titleSize, 10...16, step: 0.5, format: "%.1f")
                slider("Subtitle size", $store.design.subtitleSize, 9...14, step: 0.5, format: "%.1f")
                picker("Small (Night Shift, Sleep)", $store.design.smallSpan)
                picker("Large (Caffeinate, Arrangement)", $store.design.largeSpan)
                picker("Detail chevron", $store.design.largeChevron)
                Toggle("Small labels", isOn: $store.design.smallLabels)
                picker("Active color", $store.design.activeTint)
            }

            Section("Sliders") {
                picker("Style", $store.design.sliderStyle)
                slider("Row height", $store.design.sliderRowHeight, 40...96, step: 1)
                slider("Slider height", $store.design.sliderHeight, 14...36, step: 1)
                    .disabled(store.design.sliderStyle != .controlCenter)
                Toggle("Titles above sliders", isOn: $store.design.sliderTitles)
                Picker("Display slider moves", selection: $store.design.displayScope) {
                    ForEach(CCDesign.DisplayScope.allCases) { Text($0.title).tag($0) }
                }
            }

            Section("Detail views") {
                picker("Transition", $store.design.transition)
                Toggle("Animate panel resize", isOn: $store.design.animateResize)
                Toggle("Keep home height (scroll details)", isOn: $store.design.stableHeight)
                Toggle("Back button", isOn: $store.design.detailBackButton)
                picker("Caffeinate durations", $store.design.durationLayout)
                slider("Separate extra width", $store.design.extraWidth, 240...380, step: 4)
            }

            Section("Mock state") {
                Toggle("Caffeinate on", isOn: Binding(
                    get: { store.caffeinateActive },
                    set: { $0 ? store.startCaffeinate(store.caffeinateDuration) : store.stopCaffeinate() }
                ))
                Toggle("Night Shift on", isOn: $store.nightShift)
                Toggle("Saved layout matches displays", isOn: $store.presetsMatch)
                Toggle("System Audio Recording granted", isOn: $store.audioAccess)
                Toggle("Apps playing", isOn: $store.appsPlaying)
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
                Text("Saved as you tweak. The ring icon in the real menu bar opens the same panel; turn on Show in Menu Bar in the Settings pane tab for the separate extras.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func picker<Value: CaseIterable & Identifiable & Hashable & RawRepresentable>(
        _ title: String,
        _ selection: Binding<Value>
    ) -> some View where Value.AllCases: RandomAccessCollection, Value: TitledOption {
        Picker(title, selection: selection) {
            ForEach(Value.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
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

protocol TitledOption {
    var title: String { get }
}

extension CCDesign.Surface: TitledOption {}
extension CCDesign.SmallSpan: TitledOption {}
extension CCDesign.LargeSpan: TitledOption {}
extension CCDesign.SliderStyle: TitledOption {}
extension CCDesign.ActiveTint: TitledOption {}
extension CCDesign.Transition: TitledOption {}
extension CCDesign.DurationLayout: TitledOption {}
extension CCDesign.FooterStyle: TitledOption {}
extension CCDesign.ChevronMode: TitledOption {}
