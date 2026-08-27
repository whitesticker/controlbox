import ControlBoxCore
import SwiftUI

struct MXMasterCalibrationView: View {
    let snapshot: MXMasterSnapshot
    @Environment(\.colorScheme) private var colorScheme

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

            HStack(alignment: .top, spacing: 18) {
                GeometryReader { geo in
                    let mouseH = min(geo.size.height * 0.92, 520)
                    let mouseW = mouseH * 0.62
                    let padH = mouseH * 0.86
                    let padW = padH * 0.82
                    HStack(alignment: .center, spacing: 36) {
                        MXMasterMouseView(snapshot: snapshot)
                            .frame(width: mouseW, height: mouseH)
                        GestureSwipeStage(snapshot: snapshot)
                            .frame(width: padW, height: padH)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Palette.surface(colorScheme))
                )
                MXMasterSidebar(snapshot: snapshot)
                    .frame(width: 360)
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

private struct MXMasterSidebar: View {
    let snapshot: MXMasterSnapshot
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                MXPanel(title: "Clicks") {
                    MXValueRow(label: "Left", value: down(snapshot.left))
                    MXValueRow(label: "Right", value: down(snapshot.right))
                    MXValueRow(label: "Middle", value: down(snapshot.middle))
                }
                MXPanel(title: "Scroll wheel") {
                    MXValueRow(label: "Up", value: down(snapshot.wheelUp))
                    MXValueRow(label: "Down", value: down(snapshot.wheelDown))
                }
                MXPanel(title: "Thumb wheel") {
                    MXValueRow(label: "Left", value: down(snapshot.thumbLeft))
                    MXValueRow(label: "Right", value: down(snapshot.thumbRight))
                }
                MXPanel(title: "Thumb") {
                    if !snapshot.kind.isMXMaster3Family {
                        MXValueRow(label: "Side", value: down(snapshot.side))
                    }
                    MXValueRow(label: "Back", value: down(snapshot.back))
                    MXValueRow(label: "Forward", value: down(snapshot.forward))
                    MXValueRow(label: "Mode shift", value: down(snapshot.smartShift))
                    MXValueRow(label: snapshot.kind.mxGestureControlTitle, value: down(snapshot.haptic))
                    ForEach(snapshot.extras) { extra in
                        MXValueRow(label: extra.title, value: down(extra.down))
                    }
                }
                MXPanel(title: snapshot.kind.isMXMaster3Family ? "Thumb gesture" : "Haptic gesture") {
                    MXValueRow(
                        label: snapshot.kind.isMXMaster3Family ? "Gesture button" : "Haptic pad",
                        value: down(snapshot.haptic || snapshot.gestureDown)
                    )
                    MXValueRow(label: "Live swipe", value: snapshot.liveGesture?.title ?? "—")
                    MXValueRow(label: "Last", value: snapshot.lastGesture?.title ?? "—")
                    MXValueRow(
                        label: "Delta",
                        value: String(format: "%+.0f, %+.0f", snapshot.gestureDX, snapshot.gestureDY)
                    )
                    Text(snapshot.kind.isMXMaster3Family
                         ? "Gesture means: hold the thumb gesture button and move the mouse. A tap without moving is Click. Quit Logi Options+ first."
                         : "Gesture means: press the haptic thumb pad, keep it held, and move the mouse. A tap without moving is Haptic. Quit Logi Options+ first.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Palette.secondaryText(colorScheme))
                }
                MXPanel(title: "HID++") {
                    MXValueRow(label: "Last event", value: snapshot.lastHIDEvent)
                    Text(snapshot.status)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Palette.secondaryText(colorScheme))
                        .textSelection(.enabled)
                }
                MXPanel(title: "Recent inputs") {
                    if snapshot.events.isEmpty {
                        Text("Click, scroll, or hold the gesture button")
                            .foregroundStyle(Palette.secondaryText(colorScheme))
                            .font(.system(size: 12, design: .rounded))
                    } else {
                        ForEach(snapshot.events) { event in
                            HStack(spacing: 8) {
                                Text(event.pressed ? "↓" : "↑")
                                    .foregroundStyle(event.pressed ? Palette.good : Palette.secondaryText(colorScheme))
                                    .frame(width: 12)
                                Text(event.label)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                Spacer()
                                Text(event.date, style: .time)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Palette.secondaryText(colorScheme))
                            }
                        }
                    }
                }
            }
        }
    }

    private func down(_ pressed: Bool) -> String {
        pressed ? "down" : "up"
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

private struct MXPanel<Content: View>: View {
    let title: String
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.secondaryText(colorScheme))
                .tracking(0.8)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                content
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface(colorScheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
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
