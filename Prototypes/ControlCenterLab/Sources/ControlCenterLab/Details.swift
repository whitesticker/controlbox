import SwiftUI

/// A module's detail view. In the panel it replaces the home grid (with an
/// optional back chevron); as a separate menu bar extra it is the root.
struct DetailView: View {
    @ObservedObject var store: LabStore
    let kind: ModuleKind
    let standalone: Bool
    var onBack: () -> Void = {}

    var body: some View {
        let design = store.design
        VStack(alignment: .leading, spacing: 8) {
            header(design)
            Divider().padding(.horizontal, 4)
            switch kind {
            case .caffeinate: CaffeinateDetail(store: store, standalone: standalone)
            case .display: DisplayDetail(store: store)
            case .sound: SoundDetail(store: store)
            case .arrangement: ArrangementDetail(store: store)
            case .nightShift, .sleepNow: EmptyView()
            }
            Divider().padding(.horizontal, 4)
            HoverRow(action: { store.openPane(kind.paneTitle) }) {
                Text("\(kind.paneTitle) Settings…")
                    .font(.system(size: 13))
            }
        }
    }

    private func header(_ design: CCDesign) -> some View {
        HStack(spacing: 10) {
            if !standalone && design.detailBackButton {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.primary.opacity(0.07)))
                }
                .buttonStyle(.plain)
                .help("Back")
            }
            IconCircle(kind: kind, active: active, design: design)
            VStack(alignment: .leading, spacing: 1) {
                Text(kind == .arrangement ? "Display Arrangement" : kind.title)
                    .font(.system(size: design.titleSize + 1, weight: .semibold))
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(status(now: context.date))
                        .font(.system(size: design.subtitleSize))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 0)
            if kind == .caffeinate {
                Toggle("", isOn: Binding(
                    get: { store.caffeinateActive },
                    set: { $0 ? store.startCaffeinate(store.caffeinateDuration) : store.stopCaffeinate() }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 4)
    }

    private var active: Bool {
        switch kind {
        case .caffeinate: store.caffeinateActive
        case .sound: store.volume > 0.01
        case .display: true
        case .arrangement: store.presetsMatch && store.currentPreset != nil
        default: false
        }
    }

    private func status(now: Date) -> String {
        switch kind {
        case .caffeinate:
            store.caffeinateActive ? store.caffeinateStatus(now: now) : "Last used: \(store.caffeinateDuration.title)"
        case .display:
            store.linkedDisplays ? "One slider for all displays" : "\(store.displays.count) displays"
        case .sound:
            store.outputs.first { $0.id == store.selectedOutput }?.name ?? "No output"
        case .arrangement:
            store.presetsMatch ? "\(store.presets.count) layouts for these displays" : "No layout for these displays"
        default:
            ""
        }
    }
}

struct CaffeinateDetail: View {
    @ObservedObject var store: LabStore
    let standalone: Bool

    var body: some View {
        let design = store.design
        VStack(alignment: .leading, spacing: 6) {
            DetailSectionHeader(title: "Keep awake for")
            switch design.durationLayout {
            case .chips:
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(CaffeinateDuration.allCases) { duration in
                        DurationChip(
                            title: duration.short,
                            selected: store.caffeinateActive && store.caffeinateDuration == duration,
                            action: { store.startCaffeinate(duration) }
                        )
                        .help(duration.title)
                    }
                }
                .padding(.horizontal, 4)
            case .list:
                VStack(spacing: 0) {
                    ForEach(CaffeinateDuration.allCases) { duration in
                        HoverRow(selected: store.caffeinateActive && store.caffeinateDuration == duration, action: {
                            store.startCaffeinate(duration)
                        }) {
                            Text(duration.title).font(.system(size: 13))
                        }
                    }
                }
            }
            if standalone {
                HoverRow(action: { store.sleepNow() }) {
                    Image(systemName: "moon.zzz")
                        .frame(width: 18)
                    Text("Sleep Now").font(.system(size: 13))
                }
            }
        }
    }
}

struct DurationChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(selected ? Color.white : Color.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(
                    Capsule().fill(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(hovering ? 0.14 : 0.08)))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct DisplayDetail: View {
    @ObservedObject var store: LabStore

    var body: some View {
        let design = store.design
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("One slider for all displays").font(.system(size: 13))
                Spacer()
                Toggle("One slider for all displays", isOn: $store.linkedDisplays)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.mini)
            }
            .padding(.horizontal, 8)
            if store.linkedDisplays {
                labeledSlider("All displays", value: $store.linkedBrightness, enabled: true, design: design)
            }
            ForEach(store.displays) { display in
                labeledSlider(display.name, value: store.brightness(display.id), enabled: display.canAdjust && !store.linkedDisplays, design: design)
            }
        }
    }

    private func labeledSlider(_ title: String, value: Binding<Double>, enabled: Bool, design: CCDesign) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer()
                Text("\(Int((value.wrappedValue * 100).rounded()))%")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            CCSlider(value: value, symbol: "sun.max.fill", design: design, enabled: enabled)
        }
        .padding(.horizontal, 8)
        .opacity(enabled ? 1 : 0.5)
    }
}

struct SoundDetail: View {
    @ObservedObject var store: LabStore

    var body: some View {
        let design = store.design
        VStack(alignment: .leading, spacing: 6) {
            CCSlider(value: $store.volume, symbol: SoundSymbol.name(store.volume), design: design)
                .padding(.horizontal, 8)
                .padding(.bottom, 2)
            DetailSectionHeader(title: "Output")
            VStack(spacing: 0) {
                ForEach(store.outputs) { output in
                    HoverRow(selected: store.selectedOutput == output.id, action: { store.selectedOutput = output.id }) {
                        Image(systemName: output.symbol)
                            .frame(width: 18)
                            .foregroundStyle(.secondary)
                        Text(output.name).font(.system(size: 13)).lineLimit(1)
                    }
                }
            }
            DetailSectionHeader(title: "Apps")
            if !store.audioAccess {
                note("Grant System Audio Recording for per-app volume.")
            } else if !store.appsPlaying {
                note("Play something, then that app’s slider shows up here.")
            } else {
                ForEach(store.apps) { app in
                    AppVolumeRow(store: store, app: app)
                }
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct AppVolumeRow: View {
    @ObservedObject var store: LabStore
    let app: MockApp

    var body: some View {
        let live = store.apps.first { $0.id == app.id } ?? app
        HStack(spacing: 8) {
            Button { store.toggleAppMute(app.id) } label: {
                Group {
                    if let icon = LabIcons.appIcon(bundleID: app.id) {
                        Image(nsImage: icon).resizable()
                    } else {
                        Image(systemName: "app.dashed").resizable()
                    }
                }
                .frame(width: 22, height: 22)
                .opacity(live.muted ? 0.4 : 1)
                .overlay(alignment: .bottomTrailing) {
                    if live.muted {
                        Image(systemName: "speaker.slash.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.white, .red)
                    }
                }
            }
            .buttonStyle(.plain)
            .help(live.muted ? "Unmute" : "Mute")
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(live.name).font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(live.muted ? "Muted" : (live.playing ? "Playing" : "Saved"))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                CCSlider(value: store.appVolume(app.id), symbol: SoundSymbol.name(live.volume), design: store.design, enabled: !live.muted)
            }
        }
        .padding(.horizontal, 8)
    }
}

struct ArrangementDetail: View {
    @ObservedObject var store: LabStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if store.presetsMatch {
                VStack(spacing: 0) {
                    ForEach(store.presets) { preset in
                        HoverRow(selected: store.currentPreset == preset.id, action: {
                            store.currentPreset = preset.id
                            store.flash("Applied \(preset.name)")
                        }) {
                            PresetThumbnail(screens: preset.screens)
                            Text(preset.name).font(.system(size: 13))
                        }
                    }
                }
            } else {
                Text("No saved layout matches the displays connected now.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct PresetThumbnail: View {
    let screens: [CGRect]

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(Array(screens.enumerated()), id: \.offset) { _, rect in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Color.primary.opacity(0.18))
                        .overlay(RoundedRectangle(cornerRadius: 1.5).strokeBorder(Color.primary.opacity(0.45), lineWidth: 0.75))
                        .frame(width: rect.width * geometry.size.width, height: rect.height * geometry.size.height)
                        .offset(x: rect.minX * geometry.size.width, y: rect.minY * geometry.size.height)
                }
            }
        }
        .frame(width: 34, height: 22)
    }
}
