import ControlBoxCore
import SwiftUI

/// A module's detail view. In the panel it replaces the grid (with a back
/// chevron); as the module's own menu bar extra it is the root.
struct ControlCenterDetailView: View {
    let context: ControlCenterContext
    let module: ControlCenterModule
    let standalone: Bool
    var onBack: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Divider().padding(.horizontal, 4)
            switch module {
            case .caffeinate: CaffeinateDetail(context: context, standalone: standalone)
            case .display: DisplayDetail(catalog: context.displays)
            case .sound: SoundDetail(catalog: context.sound)
            case .arrangement: ArrangementDetail(context: context)
            case .nightShift, .sleepNow: EmptyView()
            }
            Divider().padding(.horizontal, 4)
            ControlCenterRow(action: { context.openPane(module.pane) }) {
                Text("\(module.pane.title) Settings…")
                    .font(.system(size: 13))
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if !standalone {
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
            ControlCenterIconCircle(module: module, active: active)
            VStack(alignment: .leading, spacing: 1) {
                Text(module == .arrangement ? SidebarItem.displayArrangement.title : module.title)
                    .font(.system(size: ControlCenterDesign.titleSize + 1, weight: .semibold))
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    Text(status(now: timeline.date))
                        .font(.system(size: ControlCenterDesign.subtitleSize))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if module == .caffeinate {
                Toggle("Caffeinate", isOn: Binding(
                    get: { context.caffeinate.isActive },
                    set: { $0 ? context.startCaffeinate(ControlCenterSettings.shared.lastCaffeinateDuration) : context.caffeinate.stop() }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 4)
    }

    private var active: Bool {
        switch module {
        case .caffeinate: context.caffeinate.isActive
        case .sound: !context.sound.isMuted && context.sound.volume > 0.01
        case .display: !context.displays.adjustableDisplays.isEmpty
        case .arrangement: context.liveArrangement != nil
        default: false
        }
    }

    private func status(now: Date) -> String {
        switch module {
        case .caffeinate:
            return context.caffeinateStatus(now: now)
        case .display:
            let count = context.displays.displays.count
            if context.displays.unifiedEnabled { return "One slider for all displays" }
            return count == 1 ? "1 display" : "\(count) displays"
        case .sound:
            return context.sound.outputs.first { $0.id == context.sound.selectedOutputID }?.name ?? "No output"
        case .arrangement:
            let count = context.arrangement.applicablePresets.count
            if count == 0 { return "No layout for these displays" }
            return count == 1 ? "1 layout for these displays" : "\(count) layouts for these displays"
        default:
            return ""
        }
    }
}

private struct CaffeinateDetail: View {
    let context: ControlCenterContext
    let standalone: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ControlCenterSectionHeader(title: "Keep awake for")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(CaffeinateDuration.allCases) { duration in
                    DurationChip(
                        title: duration.shortTitle,
                        selected: context.caffeinate.isActive && context.caffeinate.duration == duration
                    ) {
                        context.startCaffeinate(duration)
                    }
                    .help(duration.title)
                }
            }
            .padding(.horizontal, 4)
            if standalone {
                ControlCenterRow(action: { context.sleepNow() }) {
                    Image(systemName: "moon.zzz")
                        .frame(width: 18)
                    Text("Sleep Now").font(.system(size: 13))
                }
            }
        }
    }
}

private struct DurationChip: View {
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
                    Capsule().fill(
                        selected
                            ? AnyShapeStyle(SidebarItem.caffeinate.tint)
                            : AnyShapeStyle(Color.primary.opacity(hovering ? 0.14 : 0.08))
                    )
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct DisplayDetail: View {
    @Bindable var catalog: DisplayCatalog

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if catalog.displays.isEmpty {
                ControlCenterNote(text: "No displays reported.")
            }
            if catalog.canUnify {
                HStack {
                    Text("One slider for all displays").font(.system(size: 13))
                    Spacer()
                    Toggle("One slider for all displays", isOn: Binding(
                        get: { catalog.unifiedEnabled },
                        set: { catalog.setUnifiedEnabled($0) }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.mini)
                }
                .padding(.horizontal, 8)
            }
            if catalog.unifiedEnabled {
                labeled("All displays", value: Binding(
                    get: { catalog.unifiedBrightness },
                    set: { catalog.setUnifiedBrightness($0) }
                ), enabled: true)
            }
            ForEach(catalog.displays) { display in
                labeled(display.name, value: Binding(
                    get: { catalog.displays.first { $0.id == display.id }?.brightness ?? display.brightness },
                    set: { catalog.setBrightness($0, id: display.id) }
                ), enabled: display.canAdjustBrightness && !catalog.unifiedEnabled)
            }
        }
    }

    private func labeled(_ title: String, value: Binding<Double>, enabled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer()
                Text("\(Int((value.wrappedValue * 100).rounded()))%")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            ControlCenterSlider(value: value, symbol: "sun.max.fill", enabled: enabled)
        }
        .padding(.horizontal, 8)
        .opacity(enabled ? 1 : 0.55)
    }
}

private struct SoundDetail: View {
    @Bindable var catalog: SoundCatalog

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if catalog.outputs.isEmpty {
                ControlCenterNote(text: "No output devices.")
            } else {
                ControlCenterSlider(
                    value: Binding(get: { catalog.volume }, set: { catalog.setVolume($0) }),
                    symbol: ControlCenterSymbols.speaker(catalog.volume, muted: catalog.isMuted)
                )
                .padding(.horizontal, 8)
                .padding(.bottom, 2)
                ControlCenterSectionHeader(title: "Output")
                VStack(spacing: 0) {
                    ForEach(catalog.outputs) { output in
                        ControlCenterRow(selected: catalog.selectedOutputID == output.id, action: { catalog.setOutput(output.id) }) {
                            Text(output.name).font(.system(size: 13)).lineLimit(1)
                        }
                    }
                }
            }
            if catalog.mixSupported {
                ControlCenterSectionHeader(title: "Apps")
                if !catalog.hasCaptureAccess {
                    ControlCenterNote(text: "Grant System Audio Recording for per-app volume.")
                    ControlCenterRow(action: { catalog.requestCaptureAccess() }) {
                        Text("Allow System Audio Recording…").font(.system(size: 13))
                    }
                } else if catalog.apps.isEmpty {
                    ControlCenterNote(text: "Play something, then that app’s slider shows up here.")
                } else {
                    ForEach(catalog.apps) { app in
                        AppVolumeRow(catalog: catalog, app: app)
                    }
                }
            }
        }
    }
}

private struct AppVolumeRow: View {
    @Bindable var catalog: SoundCatalog
    let app: AttachedAudioApp

    var body: some View {
        let live = catalog.apps.first { $0.id == app.id } ?? app
        HStack(spacing: 8) {
            Button { catalog.setAppMuted(!live.isMuted, id: app.id) } label: {
                Group {
                    if let icon = ControlCenterAppIcon.image(id: app.id, name: app.name) {
                        Image(nsImage: icon).resizable()
                    } else {
                        Image(systemName: "app.dashed").resizable()
                    }
                }
                .frame(width: 22, height: 22)
                .opacity(live.isMuted ? 0.4 : 1)
                .overlay(alignment: .bottomTrailing) {
                    if live.isMuted {
                        Image(systemName: "speaker.slash.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.white, .red)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!live.canAdjust)
            .help(live.isMuted ? "Unmute \(live.name)" : "Mute \(live.name)")
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(live.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Spacer()
                    Text(live.isMuted ? "Muted" : (live.isPlaying ? "Playing" : "Saved"))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { catalog.apps.first { $0.id == app.id }?.volume ?? app.volume },
                        set: { catalog.setAppVolume($0, id: app.id) }
                    ),
                    in: 0...1
                )
                .controlSize(.small)
                .disabled(!live.canAdjust || live.isMuted)
            }
        }
        .padding(.horizontal, 8)
    }
}

private struct ArrangementDetail: View {
    let context: ControlCenterContext

    var body: some View {
        let catalog = context.arrangement
        VStack(alignment: .leading, spacing: 4) {
            if catalog.applicablePresets.isEmpty {
                ControlCenterNote(text: "No saved layout matches the displays connected now.")
            } else {
                VStack(spacing: 0) {
                    ForEach(catalog.applicablePresets) { preset in
                        ControlCenterRow(selected: catalog.matchesLive(preset), action: { catalog.apply(preset) }) {
                            ArrangementThumbnail(screens: preset.screens)
                            Text(preset.name).font(.system(size: 13)).lineLimit(1)
                        }
                    }
                }
            }
            if catalog.applyFailed, let message = catalog.applyMessage {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.bad)
                    .padding(.horizontal, 8)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Screens of a saved arrangement, scaled into a small box.
private struct ArrangementThumbnail: View {
    let screens: [ArrangedScreen]

    var body: some View {
        let box = CGSize(width: 34, height: 22)
        let minX = screens.map { CGFloat($0.x) }.min() ?? 0
        let minY = screens.map { CGFloat($0.y) }.min() ?? 0
        let maxX = screens.map { CGFloat($0.x) + CGFloat($0.width) }.max() ?? 1
        let maxY = screens.map { CGFloat($0.y) + CGFloat($0.height) }.max() ?? 1
        let scale = min(box.width / max(maxX - minX, 1), box.height / max(maxY - minY, 1))
        let offsetX = (box.width - (maxX - minX) * scale) / 2
        let offsetY = (box.height - (maxY - minY) * scale) / 2
        ZStack(alignment: .topLeading) {
            ForEach(screens) { screen in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color.primary.opacity(screen.isMain ? 0.32 : 0.18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.45), lineWidth: 0.75)
                    )
                    .frame(width: max(CGFloat(screen.width) * scale - 1, 2), height: max(CGFloat(screen.height) * scale - 1, 2))
                    .offset(x: offsetX + (CGFloat(screen.x) - minX) * scale, y: offsetY + (CGFloat(screen.y) - minY) * scale)
            }
        }
        .frame(width: box.width, height: box.height, alignment: .topLeading)
    }
}

extension CaffeinateDuration {
    /// Chip label in the Caffeinate detail view.
    var shortTitle: String {
        switch self {
        case .oneMinute: "1m"
        case .fiveMinutes: "5m"
        case .tenMinutes: "10m"
        case .twentyMinutes: "20m"
        case .thirtyMinutes: "30m"
        case .fortyMinutes: "40m"
        case .fiftyMinutes: "50m"
        case .oneHour: "1h"
        case .twoHours: "2h"
        case .threeHours: "3h"
        case .oneDay: "1d"
        case .forever: "∞"
        }
    }
}
