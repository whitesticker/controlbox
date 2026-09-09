import SwiftUI

struct ControllerDiagramView: View {
    let snapshot: DualSenseSnapshot
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            ZStack {
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .fill(Palette.controllerBody(colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 36, style: .continuous)
                            .stroke(Palette.hairline(colorScheme), lineWidth: 1)
                    )

                TriggerBar(label: "L2", value: snapshot.l2)
                    .frame(width: 78, height: 54)
                    .position(x: width * 0.18, y: height * 0.12)
                TriggerBar(label: "R2", value: snapshot.r2)
                    .frame(width: 78, height: 54)
                    .position(x: width * 0.82, y: height * 0.12)

                ShoulderButton(label: "L1", pressed: snapshot.l1)
                    .position(x: width * 0.18, y: height * 0.24)
                ShoulderButton(label: "R1", pressed: snapshot.r1)
                    .position(x: width * 0.82, y: height * 0.24)

                DPad(
                    up: snapshot.dpadUp,
                    down: snapshot.dpadDown,
                    left: snapshot.dpadLeft,
                    right: snapshot.dpadRight
                )
                .position(x: width * 0.22, y: height * 0.46)

                AnalogStick(value: snapshot.leftStick, pressed: snapshot.l3, title: "L3")
                    .frame(width: 108, height: 108)
                    .position(x: width * 0.38, y: height * 0.68)

                AnalogStick(value: snapshot.rightStick, pressed: snapshot.r3, title: "R3")
                    .frame(width: 108, height: 108)
                    .position(x: width * 0.62, y: height * 0.68)

                FaceButtons(
                    triangle: snapshot.triangle,
                    circle: snapshot.circle,
                    cross: snapshot.cross,
                    square: snapshot.square
                )
                .position(x: width * 0.82, y: height * 0.46)

                TouchpadView(snapshot: snapshot)
                    .frame(width: min(width * 0.42, 280), height: 118)
                    .position(x: width * 0.50, y: height * 0.36)

                HStack(spacing: 18) {
                    SmallButton(label: "Create", pressed: snapshot.create)
                    SmallButton(label: "PS", pressed: snapshot.ps, emphasized: true)
                    SmallButton(label: "Options", pressed: snapshot.options)
                }
                .position(x: width * 0.50, y: height * 0.88)
            }
            .padding(18)
        }
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Palette.surface(colorScheme))
        )
    }
}

private struct TriggerBar: View {
    let label: String
    let value: Float
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.secondaryText(colorScheme))
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Palette.fill(colorScheme))
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Palette.accent)
                    .frame(height: 28 * CGFloat(value))
            }
            .frame(height: 28)
            Text(String(format: "%.2f", value))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Palette.secondaryText(colorScheme))
        }
    }
}

private struct ShoulderButton: View {
    let label: String
    let pressed: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(label)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .frame(width: 78, height: 28)
            .background(pressed ? Palette.accent : Palette.fill(colorScheme), in: Capsule())
            .foregroundStyle(pressed ? .white : Palette.primaryText(colorScheme))
            .scaleEffect(pressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.08), value: pressed)
    }
}

private struct AnalogStick: View {
    let value: SIMD2<Float>
    let pressed: Bool
    let title: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Circle()
                .fill(Palette.fill(colorScheme))
                .overlay(Circle().stroke(Palette.hairline(colorScheme), lineWidth: 1))
            Circle()
                .fill(pressed ? Palette.accent : Palette.raised(colorScheme))
                .frame(width: 42, height: 42)
                .offset(x: CGFloat(value.x) * 24, y: CGFloat(-value.y) * 24)
            VStack {
                Spacer()
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.secondaryText(colorScheme))
                    .padding(.bottom, 8)
            }
        }
    }
}

private struct DPad: View {
    let up: Bool
    let down: Bool
    let left: Bool
    let right: Bool

    var body: some View {
        ZStack {
            DPadArm(pressed: up).offset(y: -22)
            DPadArm(pressed: down).offset(y: 22)
            DPadArm(pressed: left).rotationEffect(.degrees(90)).offset(x: -22)
            DPadArm(pressed: right).rotationEffect(.degrees(90)).offset(x: 22)
        }
        .frame(width: 92, height: 92)
    }
}

private struct DPadArm: View {
    let pressed: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(pressed ? Palette.primaryText(colorScheme) : Palette.fill(colorScheme))
            .frame(width: 22, height: 28)
    }
}

private struct FaceButtons: View {
    let triangle: Bool
    let circle: Bool
    let cross: Bool
    let square: Bool

    var body: some View {
        ZStack {
            FaceButton(symbol: "△", pressed: triangle, color: Palette.triangle).offset(y: -34)
            FaceButton(symbol: "○", pressed: circle, color: Palette.circle).offset(x: 34)
            FaceButton(symbol: "✕", pressed: cross, color: Palette.cross).offset(y: 34)
            FaceButton(symbol: "□", pressed: square, color: Palette.square).offset(x: -34)
        }
        .frame(width: 120, height: 120)
    }
}

private struct FaceButton: View {
    let symbol: String
    let pressed: Bool
    let color: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Circle()
                .fill(pressed ? color : color.opacity(colorScheme == .dark ? 0.28 : 0.18))
                .frame(width: 36, height: 36)
            Text(symbol)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(pressed ? .white : color)
        }
        .scaleEffect(pressed ? 0.94 : 1)
        .animation(.easeOut(duration: 0.08), value: pressed)
    }
}

private struct SmallButton: View {
    let label: String
    let pressed: Bool
    var emphasized = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                pressed ? (emphasized ? Palette.accent : Palette.primaryText(colorScheme)) : Palette.fill(colorScheme),
                in: Capsule()
            )
            .foregroundStyle(pressed ? Palette.background(colorScheme) : Palette.primaryText(colorScheme))
    }
}

private struct TouchpadView: View {
    let snapshot: DualSenseSnapshot
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(snapshot.touchpadClick ? Palette.accent.opacity(0.22) : Palette.fill(colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(snapshot.touchpadClick ? Palette.accent : Palette.hairline(colorScheme), lineWidth: 1.5)
                    )
                Text("TOUCHPAD · 2 FINGERS MAX")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.secondaryText(colorScheme))
                    .offset(y: -size.height * 0.36)

                if snapshot.touch1.active {
                    FingerDot(finger: snapshot.touch1, color: Palette.accent, size: size)
                }
                if snapshot.touch2.active {
                    FingerDot(finger: snapshot.touch2, color: Palette.triangle, size: size)
                }
            }
        }
    }
}

private struct FingerDot: View {
    let finger: TouchFinger
    let color: Color
    let size: CGSize

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 18, height: 18)
            .shadow(color: color.opacity(0.8), radius: 8)
            .position(
                x: mappedX(finger.x, width: size.width),
                y: mappedY(finger.y, height: size.height)
            )
    }

    private func mappedX(_ value: Float, width: CGFloat) -> CGFloat {
        let normalized = (CGFloat(value) + 1) / 2
        return 16 + normalized * (width - 32)
    }

    private func mappedY(_ value: Float, height: CGFloat) -> CGFloat {
        let normalized = (1 - CGFloat(value)) / 2
        return 16 + normalized * (height - 32)
    }
}
