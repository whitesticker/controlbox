import ControlBoxCore
import SwiftUI

struct MXMasterCalibrationView: View {
    @Bindable var monitor: DualSenseMonitor
    let deviceID: String
    @Environment(\.colorScheme) private var colorScheme

    private var snapshot: MXMasterSnapshot { monitor.mxSnapshot(for: deviceID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Circle()
                    .fill(snapshot.connected ? Palette.good : Palette.bad)
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.connected ? snapshot.name : "Waiting for MX Master")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                    if snapshot.connected, DeviceIdentity.isConcrete(snapshot.address) {
                        Text(DeviceIdentity.format(snapshot.address))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(Palette.secondaryText(colorScheme))
                            .textSelection(.enabled)
                    }
                    Text(headlineStatus)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Palette.secondaryText(colorScheme))
                }
                Spacer()
                MXChip(title: "HID++", tint: Palette.accent)
                MXChip(
                    title: (snapshot.haptic || snapshot.gestureDown)
                        ? "\(snapshot.kind.mxGestureControlTitle) held"
                        : "\(snapshot.kind.mxGestureControlTitle) up",
                    tint: (snapshot.haptic || snapshot.gestureDown) ? Palette.good : Palette.secondaryText(colorScheme)
                )
            }

            GeometryReader { geo in
                let middleTopHeight = max(240, (geo.size.height - 14) * 0.57)
                HStack(alignment: .top, spacing: 14) {
                    CalibrationCard(title: "Button press mapping") {
                        GeometryReader { cardGeo in
                            let mouseH = min(cardGeo.size.height * 0.94, cardGeo.size.width / 0.62)
                            MXMasterMouseView(snapshot: snapshot)
                                .frame(width: mouseH * 0.62, height: mouseH)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    VStack(spacing: 14) {
                        CalibrationCard(title: "Haptic capture") {
                            GestureSwipeStage(snapshot: snapshot)
                                .padding(2)
                        }
                        .frame(height: middleTopHeight)

                        CalibrationCard(title: "Click history") {
                            MXButtonPressHistoryContent(snapshot: snapshot)
                        }
                        .frame(maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    CalibrationCard(title: "Live clicks") {
                        MXLiveClicksContent(snapshot: snapshot)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private var headlineStatus: String {
        if !snapshot.connected { return snapshot.status }
        if snapshot.gestureDown || snapshot.haptic {
            return snapshot.liveGesture?.title ?? "\(snapshot.kind.mxGestureControlTitle) held"
        }
        return "Connected"
    }
}

struct CalibrationCard<Content: View>: View {
    let title: String
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.secondaryText(colorScheme))
                .tracking(0.8)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(14)
        .background(
            Palette.surface(colorScheme),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Palette.hairline(colorScheme), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.06), radius: 2, y: 1)
    }
}

private struct MXLiveClicksContent: View {
    let snapshot: MXMasterSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            MXCalibrationGroup(title: "Main buttons") {
                MXValueRow(label: "Left", value: state(snapshot.left))
                MXValueRow(label: "Right", value: state(snapshot.right))
                MXValueRow(label: "Middle", value: state(snapshot.middle))
                MXValueRow(label: "Mode shift", value: state(snapshot.smartShift))
            }

            MXCalibrationGroup(title: "Scroll wheel") {
                MXValueRow(label: "Up", value: state(snapshot.wheelUp))
                MXValueRow(label: "Down", value: state(snapshot.wheelDown))
            }

            MXCalibrationGroup(title: "Thumb wheel") {
                MXValueRow(label: "Left", value: state(snapshot.thumbLeft))
                MXValueRow(label: "Right", value: state(snapshot.thumbRight))
            }

            MXCalibrationGroup(title: "Thumb buttons") {
                if !snapshot.kind.isMXMaster3Family {
                    MXValueRow(label: "Side", value: state(snapshot.side))
                }
                MXValueRow(label: "Back", value: state(snapshot.back))
                MXValueRow(label: "Forward", value: state(snapshot.forward))
                MXValueRow(
                    label: snapshot.kind.mxGestureControlTitle,
                    value: state(snapshot.haptic || snapshot.gestureDown)
                )
                ForEach(snapshot.extras) { extra in
                    MXValueRow(label: extra.title, value: state(extra.down))
                }
            }

            MXCalibrationGroup(
                title: snapshot.kind.isMXMaster3Family ? "Thumb gesture" : "Haptic gesture"
            ) {
                MXValueRow(
                    label: snapshot.kind.isMXMaster3Family ? "Gesture button" : "Haptic pad",
                    value: state(snapshot.haptic || snapshot.gestureDown)
                )
                MXValueRow(label: "Live swipe", value: snapshot.liveGesture?.title ?? "—")
                MXValueRow(label: "Last", value: snapshot.lastGesture?.title ?? "—")
                MXValueRow(
                    label: "Delta",
                    value: String(
                        format: "%+.0f, %+.0f",
                        snapshot.gestureDX,
                        snapshot.gestureDY
                    )
                )
            }
        }
    }

    private func state(_ pressed: Bool) -> String {
        pressed ? "down" : "up"
    }
}

private struct MXButtonPressHistoryContent: View {
    let snapshot: MXMasterSnapshot
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if snapshot.events.isEmpty {
                    Text("Click, scroll, or hold the gesture button")
                        .foregroundStyle(Palette.secondaryText(colorScheme))
                        .font(.system(size: 12, design: .rounded))
                } else {
                    ForEach(snapshot.events) { event in
                        HStack(spacing: 8) {
                            Text(event.pressed ? "↓" : "↑")
                                .foregroundStyle(
                                    event.pressed
                                        ? Palette.good
                                        : Palette.secondaryText(colorScheme)
                                )
                                .frame(width: 12)
                            Text(event.label)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                            Spacer()
                            Text(event.date, style: .time)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Palette.secondaryText(colorScheme))
                        }
                        if event.id != snapshot.events.last?.id {
                            Divider()
                        }
                    }
                }

                Divider()
                    .padding(.vertical, 4)

                MXCalibrationGroup(title: "HID++") {
                    MXValueRow(label: "Last event", value: snapshot.lastHIDEvent)
                    Text(snapshot.status)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Palette.secondaryText(colorScheme))
                        .textSelection(.enabled)
                }
            }
        }
    }
}

private struct MXCalibrationGroup<Content: View>: View {
    let title: String
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.secondaryText(colorScheme))
                .tracking(0.6)
            content
        }
    }
}

private struct MXMasterMouseView: View {
    let snapshot: MXMasterSnapshot
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            MXMasterOutline()
                .fill(Palette.controllerBody(colorScheme))
                .overlay {
                    MXMasterOutline()
                        .stroke(Palette.hairline(colorScheme), lineWidth: 1.2)
                }
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.12), radius: 18, y: 8)

            buttonGlows
            wheelColumn
            thumbCluster
        }
    }

    private var buttonGlows: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                glowRegion(
                    pressed: snapshot.left,
                    in: CGRect(x: w * 0.16, y: h * 0.045, width: w * 0.26, height: h * 0.20),
                    radius: 22,
                    title: "Left"
                )
                glowRegion(
                    pressed: snapshot.right,
                    in: CGRect(x: w * 0.58, y: h * 0.045, width: w * 0.26, height: h * 0.20),
                    radius: 22,
                    title: "Right"
                )
            }
            .clipShape(MXMasterOutline())
        }
    }

    private var wheelColumn: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let colW = w * 0.15
            let chipH = h * 0.052
            VStack(spacing: 4) {
                glowChip(
                    pressed: snapshot.wheelUp,
                    width: colW,
                    height: chipH,
                    radius: 8,
                    title: "Up"
                )
                glowChip(
                    pressed: snapshot.middle,
                    width: colW,
                    height: chipH,
                    radius: 8,
                    title: "Click"
                )
                glowChip(
                    pressed: snapshot.wheelDown,
                    width: colW,
                    height: chipH,
                    radius: 8,
                    title: "Down"
                )
                Color.clear
                    .frame(height: 16)
                glowChip(
                    pressed: snapshot.smartShift,
                    width: colW,
                    height: chipH,
                    radius: 8,
                    title: "Mode"
                )
            }
            .frame(width: colW)
            .position(x: w * 0.515, y: h * 0.22)
        }
    }

    @ViewBuilder
    private var thumbCluster: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let family = snapshot.kind.isMXMaster3Family
            ZStack {
                glowRegion(
                    pressed: snapshot.haptic,
                    in: family
                        ? CGRect(x: w * 0.06, y: h * 0.36, width: w * 0.20, height: h * 0.12)
                        : CGRect(x: w * 0.05, y: h * 0.32, width: w * 0.24, height: h * 0.13),
                    radius: family ? 18 : 14,
                    title: snapshot.kind.mxGestureControlTitle
                )
                HStack(spacing: 3) {
                    glowChip(
                        pressed: snapshot.thumbLeft,
                        width: w * 0.11,
                        height: 22,
                        radius: 8,
                        title: "Left"
                    )
                    glowChip(
                        pressed: snapshot.thumbRight,
                        width: w * 0.11,
                        height: 22,
                        radius: 8,
                        title: "Right"
                    )
                }
                .frame(width: w * 0.23, height: 22)
                .position(x: w * 0.17, y: family ? h * 0.545 : h * 0.50)
                if !family {
                    glowRegion(
                        pressed: snapshot.side,
                        in: CGRect(x: w * 0.06, y: h * 0.56, width: w * 0.18, height: h * 0.075),
                        radius: 10,
                        title: "Side"
                    )
                }
                glowRegion(
                    pressed: snapshot.forward,
                    in: CGRect(
                        x: w * 0.06,
                        y: family ? h * 0.60 : h * 0.655,
                        width: w * 0.18,
                        height: h * 0.075
                    ),
                    radius: 10,
                    title: "Fwd"
                )
                glowRegion(
                    pressed: snapshot.back,
                    in: CGRect(
                        x: w * 0.06,
                        y: family ? h * 0.71 : h * 0.75,
                        width: w * 0.18,
                        height: h * 0.075
                    ),
                    radius: 10,
                    title: "Back"
                )
            }
        }
    }

    private func glowChip(
        pressed: Bool,
        width: CGFloat,
        height: CGFloat,
        radius: CGFloat,
        title: String
    ) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(pressed ? Palette.accent.opacity(0.90) : Palette.fill(colorScheme).opacity(0.55))
            .overlay {
                Text(title)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(pressed ? .white : Palette.secondaryText(colorScheme).opacity(0.72))
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(pressed ? Palette.accent : Color.clear, lineWidth: pressed ? 1 : 0)
            }
            .shadow(color: pressed ? Palette.accent.opacity(0.50) : .clear, radius: pressed ? 10 : 0)
            .frame(width: width, height: height)
            .animation(.easeOut(duration: 0.08), value: pressed)
    }

    private func glowRegion(
        pressed: Bool,
        in rect: CGRect,
        radius: CGFloat,
        title: String?
    ) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(pressed ? Palette.accent.opacity(0.90) : Palette.fill(colorScheme).opacity(0.55))
            .overlay {
                if let title {
                    Text(title)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(pressed ? .white : Palette.secondaryText(colorScheme).opacity(0.72))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(
                        pressed ? Palette.accent : Color.clear,
                        lineWidth: pressed ? 1 : 0
                    )
            }
            .shadow(color: pressed ? Palette.accent.opacity(0.50) : .clear, radius: pressed ? 10 : 0)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .animation(.easeOut(duration: 0.08), value: pressed)
    }
}

/// Right-handed MX Master, nose up, thumb rest on the left.
private struct MXMasterOutline: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: w * 0.40, y: h * 0.03))
        path.addQuadCurve(
            to: CGPoint(x: w * 0.82, y: h * 0.10),
            control: CGPoint(x: w * 0.70, y: h * 0.01)
        )
        path.addQuadCurve(
            to: CGPoint(x: w * 0.90, y: h * 0.40),
            control: CGPoint(x: w * 0.97, y: h * 0.20)
        )
        path.addQuadCurve(
            to: CGPoint(x: w * 0.82, y: h * 0.86),
            control: CGPoint(x: w * 0.94, y: h * 0.64)
        )
        path.addQuadCurve(
            to: CGPoint(x: w * 0.50, y: h * 0.97),
            control: CGPoint(x: w * 0.70, y: h * 1.01)
        )
        path.addQuadCurve(
            to: CGPoint(x: w * 0.10, y: h * 0.74),
            control: CGPoint(x: w * 0.14, y: h * 0.96)
        )
        path.addQuadCurve(
            to: CGPoint(x: w * 0.08, y: h * 0.40),
            control: CGPoint(x: w * 0.00, y: h * 0.56)
        )
        path.addQuadCurve(
            to: CGPoint(x: w * 0.22, y: h * 0.10),
            control: CGPoint(x: w * 0.10, y: h * 0.18)
        )
        path.addQuadCurve(
            to: CGPoint(x: w * 0.40, y: h * 0.03),
            control: CGPoint(x: w * 0.28, y: h * 0.02)
        )
        path.closeSubpath()
        return path
    }
}

private struct GestureSwipeStage: View {
    let snapshot: MXMasterSnapshot
    @Environment(\.colorScheme) private var colorScheme
    @State private var trail: [CGPoint] = []
    @State private var fade = 1.0

    private var held: Bool { snapshot.gestureDown || snapshot.haptic }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(held ? Palette.accent.opacity(0.16) : Palette.fill(colorScheme))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(held ? Palette.accent.opacity(0.75) : Palette.hairline(colorScheme), lineWidth: 1.5)
                }
                .shadow(color: held ? Palette.accent.opacity(0.28) : .clear, radius: 16)

            crosshair
            trailCanvas
            compass

            VStack(spacing: 4) {
                Text(snapshot.kind.isMXMaster3Family ? "GESTURE SWIPE" : "HAPTIC SWIPE")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(Palette.secondaryText(colorScheme))
                    .padding(.top, 16)
                Spacer()
                Text(caption)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(held ? Palette.accent : Palette.secondaryText(colorScheme))
                    .padding(.bottom, 16)
            }
        }
        .onChange(of: held) { _, isHeld in
            if isHeld {
                trail = [.zero]
                fade = 1
            } else {
                withAnimation(.easeOut(duration: 0.7)) { fade = 0 }
            }
        }
        .onChange(of: snapshot.gestureDX) { _, _ in appendTrail() }
        .onChange(of: snapshot.gestureDY) { _, _ in appendTrail() }
    }

    private var caption: String {
        if held {
            return snapshot.liveGesture?.title ?? "Held · move"
        }
        if let last = snapshot.lastGesture {
            return last.title
        }
        return "Hold and move"
    }

    private var crosshair: some View {
        GeometryReader { geo in
            Path { path in
                path.move(to: CGPoint(x: geo.size.width / 2, y: 44))
                path.addLine(to: CGPoint(x: geo.size.width / 2, y: geo.size.height - 44))
                path.move(to: CGPoint(x: 28, y: geo.size.height / 2))
                path.addLine(to: CGPoint(x: geo.size.width - 28, y: geo.size.height / 2))
            }
            .stroke(Palette.hairline(colorScheme).opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
        }
    }

    private var trailCanvas: some View {
        GeometryReader { geo in
            let size = geo.size
            Canvas { context, _ in
                let mapped = trail.map { point(in: size, dx: $0.x, dy: $0.y) }
                if mapped.count > 1 {
                    var path = Path()
                    path.addLines(mapped)
                    context.opacity = fade
                    context.stroke(
                        path,
                        with: .color(Palette.accent),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                    )
                }
                if let last = mapped.last {
                    let dot = Path(ellipseIn: CGRect(x: last.x - 5, y: last.y - 5, width: 10, height: 10))
                    context.opacity = fade
                    context.fill(dot, with: .color(Palette.accent))
                }
            }
        }
        .opacity(fade)
    }

    private var compass: some View {
        let live = snapshot.liveGesture
        let last = snapshot.lastGesture
        return VStack {
            tick(active: live == .mxGestureUp || last == .mxGestureUp)
            Spacer()
            tick(active: live == .mxGestureDown || last == .mxGestureDown)
        }
        .padding(.vertical, 36)
        .overlay {
            HStack {
                tick(active: live == .mxGestureLeft || last == .mxGestureLeft)
                Spacer()
                tick(active: live == .mxGestureRight || last == .mxGestureRight)
            }
            .padding(.horizontal, 22)
        }
    }

    private func tick(active: Bool) -> some View {
        Capsule()
            .fill(active ? Palette.accent : Palette.raised(colorScheme).opacity(0.7))
            .frame(width: 22, height: 6)
            .shadow(color: active ? Palette.accent.opacity(0.55) : .clear, radius: 6)
    }

    private func appendTrail() {
        guard held else { return }
        let next = CGPoint(x: snapshot.gestureDX, y: snapshot.gestureDY)
        if trail.last != next {
            trail.append(next)
            if trail.count > 80 { trail.removeFirst(trail.count - 80) }
        }
    }

    private func point(in size: CGSize, dx: CGFloat, dy: CGFloat) -> CGPoint {
        let scale: CGFloat = 0.16
        let x = min(max(size.width / 2 + dx * scale, 20), size.width - 20)
        let y = min(max(size.height / 2 + dy * scale, 36), size.height - 36)
        return CGPoint(x: x, y: y)
    }
}

struct MXMouseSettingsWindow: View {
    @Bindable var monitor: DualSenseMonitor
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("On This Mouse")
                    .font(.largeTitle.weight(.bold))
                Text(monitor.selectedRecord?.displayName ?? "MX Master")
                    .foregroundStyle(.secondary)
            }

            if monitor.selectedKind.isMXMaster {
                CalibrationCard(title: "Mouse settings") {
                    MXMouseSettingsContent(monitor: monitor)
                }
            } else {
                ContentUnavailableView(
                    "Select an MX Master",
                    systemImage: "computermouse",
                    description: Text("Choose an MX Master in the sidebar to view its settings.")
                )
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background(colorScheme))
    }
}

private struct MXMouseSettingsContent: View {
    @Bindable var monitor: DualSenseMonitor
    @Environment(\.colorScheme) private var colorScheme

    private var snapshot: MXMasterSnapshot { monitor.mxMasterSnapshot }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                dpiSlider
                Text("Written to the sensor over HID++. Pointer speed stays the same.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Palette.secondaryText(colorScheme))
                Divider()
                ratchetPicker
                ratchetSensitivitySlider
                Text("Free Spin and Ratchet are written to this mouse. Sensitivity only applies in Ratchet.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Palette.secondaryText(colorScheme))
                Divider()
                thumbWheelSlider
                Text("Scales HID++ thumb-wheel travel. Pointer & Scroll wheel speed stays on the main wheel.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Palette.secondaryText(colorScheme))
                Toggle("Invert thumb wheel", isOn: thumbInvertBinding)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                Text("Written to this mouse. Does not change the main wheel or the trackpad.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Palette.secondaryText(colorScheme))
            }
        }
    }

    private var dpiLevels: [Int] {
        let fromMouse = snapshot.availableDPI
        return fromMouse.count >= 2 ? fromMouse : MappingProfile.fallbackDPILevels
    }

    private var dpiProfile: MappingProfile {
        monitor.selectedRecord?.mxDefaultProfile ?? monitor.selectedProfile
    }

    private var dpiIndexBinding: Binding<Double> {
        Binding(
            get: {
                let levels = dpiLevels
                let current = MappingProfile.nearestDPI(dpiProfile.resolvedSensorDPI, in: levels)
                return Double(levels.firstIndex(of: current) ?? 0)
            },
            set: { index in
                let levels = dpiLevels
                let clamped = min(max(Int(index.rounded()), 0), levels.count - 1)
                monitor.setSensorDPI(levels[clamped])
            }
        )
    }

    @ViewBuilder
    private var dpiSlider: some View {
        let levels = dpiLevels
        let current = MappingProfile.nearestDPI(dpiProfile.resolvedSensorDPI, in: levels)
        SettingsSlider(
            "DPI",
            value: dpiIndexBinding,
            in: 0...Double(max(levels.count - 1, 1)),
            step: 1,
            valueText: "\(current)",
            labelWidth: 92
        )
    }

    private var thumbWheelBinding: Binding<Double> {
        Binding(
            get: { dpiProfile.resolvedMXThumbWheelSensitivity },
            set: { monitor.setMXThumbWheelSensitivity($0) }
        )
    }

    private var thumbInvertBinding: Binding<Bool> {
        Binding(
            get: { dpiProfile.resolvedMXThumbWheelInvert },
            set: { monitor.setMXThumbWheelInvert($0) }
        )
    }

    private var ratchetModeBinding: Binding<MXRatchetMode> {
        Binding(
            get: { dpiProfile.resolvedMXRatchetMode },
            set: { monitor.setMXRatchetMode($0) }
        )
    }

    private var ratchetSensitivityBinding: Binding<Double> {
        Binding(
            get: { Double(dpiProfile.resolvedMXSmartShiftSensitivity) },
            set: { monitor.setMXSmartShiftSensitivity(Int($0.rounded())) }
        )
    }

    @ViewBuilder
    private var thumbWheelSlider: some View {
        SettingsSlider(
            "Thumb wheel",
            value: thumbWheelBinding,
            labelWidth: 92
        )
    }

    @ViewBuilder
    private var ratchetPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Main wheel")
                .font(.system(size: 12, weight: .medium, design: .rounded))
            Picker("Main wheel", selection: ratchetModeBinding) {
                Text("Free Spin").tag(MXRatchetMode.freeSpin)
                Text("Ratchet").tag(MXRatchetMode.ratchet)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var ratchetSensitivitySlider: some View {
        SettingsSlider(
            "Sensitivity",
            description: "Higher keeps the ratchet longer before Free Spin.",
            value: ratchetSensitivityBinding,
            in: Double(MappingProfile.smartShiftSensitivityMin)...Double(MappingProfile.smartShiftSensitivityMax),
            step: 1,
            enabled: dpiProfile.resolvedMXRatchetMode == .ratchet,
            valueText: "\(dpiProfile.resolvedMXSmartShiftSensitivity)",
            labelWidth: 92
        )
    }
}

private struct MXChip: View {
    let title: String
    let tint: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(colorScheme == .dark ? 0.22 : 0.16), in: Capsule())
            .foregroundStyle(colorScheme == .dark ? .white : tint)
    }
}

private struct MXValueRow: View {
    let label: String
    let value: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Palette.secondaryText(colorScheme))
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Palette.primaryText(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}
