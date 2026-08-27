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
                    Text(snapshot.status)
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
                MXMasterMouseView(snapshot: snapshot)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                MXMasterSidebar(snapshot: snapshot)
                    .frame(width: 360)
            }
        }
    }
}

private struct MXMasterMouseView: View {
    let snapshot: MXMasterSnapshot
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            ZStack {
                RoundedRectangle(cornerRadius: 90, style: .continuous)
                    .fill(Palette.controllerBody(colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 90, style: .continuous)
                            .stroke(Palette.hairline(colorScheme), lineWidth: 1)
                    )
                    .frame(width: min(width * 0.42, 220), height: min(height * 0.78, 420))
                    .position(x: width * 0.46, y: height * 0.50)

                MXButton(title: "Left", pressed: snapshot.left)
                    .frame(width: 84, height: 78)
                    .position(x: width * 0.30, y: height * 0.27)
                VStack(spacing: 6) {
                    MXButton(title: "Wheel +", pressed: snapshot.wheelUp, compact: true)
                    MXButton(title: "Middle", pressed: snapshot.middle, compact: true)
                    MXButton(title: "Wheel −", pressed: snapshot.wheelDown, compact: true)
                }
                .position(x: width * 0.46, y: height * 0.27)
                MXButton(title: "Right", pressed: snapshot.right)
                    .frame(width: 84, height: 78)
                    .position(x: width * 0.62, y: height * 0.27)

                MXButton(title: "Mode shift", pressed: snapshot.smartShift, compact: true)
                    .position(x: width * 0.62, y: height * 0.42)
                MXButton(title: snapshot.kind.mxGestureControlTitle, pressed: snapshot.haptic)
                    .frame(width: 88, height: 44)
                    .position(x: width * 0.30, y: height * 0.52)

                MXButton(title: "Thumb ←", pressed: snapshot.thumbLeft, compact: true)
                    .position(x: width * 0.24, y: height * 0.58)
                MXButton(title: "Thumb →", pressed: snapshot.thumbRight, compact: true)
                    .position(x: width * 0.24, y: height * 0.68)

                MXButton(title: "Back", pressed: snapshot.back)
                    .frame(width: 72, height: 44)
                    .position(x: width * 0.24, y: height * 0.80)
                MXButton(title: "Forward", pressed: snapshot.forward)
                    .frame(width: 72, height: 44)
                    .position(x: width * 0.38, y: height * 0.80)

                gesturePad
                    .frame(width: 150, height: 86)
                    .position(x: width * 0.58, y: height * 0.72)
            }
            .padding(18)
        }
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Palette.surface(colorScheme))
        )
    }

    private var gesturePad: some View {
        let live = snapshot.liveGesture
        return ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill((snapshot.gestureDown || snapshot.haptic) ? Palette.accent.opacity(0.28) : Palette.fill(colorScheme))
            VStack(spacing: 4) {
                Text(snapshot.kind.isMXMaster3Family ? "Gesture swipe" : "Haptic swipe")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                Text(gestureCaption)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                if snapshot.gestureDown {
                    Text(String(format: "dx %+.0f  dy %+.0f", snapshot.gestureDX, snapshot.gestureDY))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle((snapshot.gestureDown || snapshot.haptic) ? Palette.accent : Palette.primaryText(colorScheme))

            arrow("↑", active: live == .mxGestureUp || snapshot.lastGesture == .mxGestureUp)
                .offset(y: -34)
            arrow("↓", active: live == .mxGestureDown || snapshot.lastGesture == .mxGestureDown)
                .offset(y: 34)
            arrow("←", active: live == .mxGestureLeft || snapshot.lastGesture == .mxGestureLeft)
                .offset(x: -64)
            arrow("→", active: live == .mxGestureRight || snapshot.lastGesture == .mxGestureRight)
                .offset(x: 64)
        }
    }

    private var gestureCaption: String {
        if snapshot.gestureDown || snapshot.haptic {
            return snapshot.liveGesture?.title ?? "\(snapshot.kind.mxGestureControlTitle) held"
        }
        if let last = snapshot.lastGesture {
            return "Last: \(last.title)"
        }
        return snapshot.kind.isMXMaster3Family ? "Hold gesture + move" : "Hold haptic + move"
    }

    private func arrow(_ symbol: String, active: Bool) -> some View {
        Text(symbol)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(active ? Palette.accent : Palette.secondaryText(colorScheme).opacity(0.45))
    }
}

private struct MXButton: View {
    let title: String
    let pressed: Bool
    var compact = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(title)
            .font(.system(size: compact ? 10 : 12, weight: .bold, design: .rounded))
            .padding(.horizontal, compact ? 8 : 10)
            .padding(.vertical, compact ? 5 : 8)
            .background(
                pressed ? Palette.accent : Palette.fill(colorScheme),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .foregroundStyle(pressed ? .white : Palette.primaryText(colorScheme))
            .scaleEffect(pressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.08), value: pressed)
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
                MXPanel(title: "Wheels") {
                    MXValueRow(label: "Wheel up", value: down(snapshot.wheelUp))
                    MXValueRow(label: "Wheel down", value: down(snapshot.wheelDown))
                    MXValueRow(label: "Thumb left", value: down(snapshot.thumbLeft))
                    MXValueRow(label: "Thumb right", value: down(snapshot.thumbRight))
                }
                MXPanel(title: "Thumb") {
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
                    MXValueRow(label: "HID++", value: snapshot.lastHIDEvent)
                    Text(snapshot.kind.isMXMaster3Family
                         ? "Gesture means: hold the thumb gesture button and move the mouse. A tap without moving is Click. Quit Logi Options+ first."
                         : "Gesture means: press the haptic thumb pad, keep it held, and move the mouse. A tap without moving is Haptic. Quit Logi Options+ first.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Palette.secondaryText(colorScheme))
                    Text("macOS click events do not say which mouse produced them. Extra-button fallbacks are gated per model, so MX4 haptic (buttons 5/6) cannot start a 3S gesture.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Palette.secondaryText(colorScheme))
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
        }
    }
}
