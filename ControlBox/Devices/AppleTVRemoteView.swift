import SwiftUI

struct AppleTVRemoteView: View {
    let snapshot: AppleTVRemoteSnapshot
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        remoteBody
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var remoteBody: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 14) {
                Clickpad(
                    up: snapshot.clickUp,
                    down: snapshot.clickDown,
                    left: snapshot.clickLeft,
                    right: snapshot.clickRight,
                    select: snapshot.select,
                    touchActive: snapshot.touchActive,
                    touchX: snapshot.touchX,
                    touchY: snapshot.touchY,
                    wheelActive: snapshot.wheelActive,
                    wheelAccumulated: snapshot.wheelAccumulated
                )
                HStack(spacing: 12) {
                    RemoteKey(title: "Back", pressed: snapshot.back)
                    RemoteKey(title: "TV", pressed: snapshot.tv)
                }
                HStack(spacing: 12) {
                    RemoteKey(title: "Play", pressed: snapshot.playPause)
                    VolumeHalf(title: "Vol +", pressed: snapshot.volumeUp, isTop: true)
                }
                HStack(spacing: 12) {
                    RemoteKey(title: "Mute", pressed: snapshot.mute)
                    VolumeHalf(title: "Vol −", pressed: snapshot.volumeDown, isTop: false)
                }
            }
            VStack(spacing: 10) {
                RemoteKey(title: "Power", pressed: snapshot.power, compact: true)
                RemoteKey(title: "Siri", pressed: snapshot.siri, side: true)
                    .frame(height: 132)
            }
            .padding(.top, 18)
        }
        .padding(24)
        .frame(maxWidth: 380)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(Palette.controllerBody(colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .stroke(Palette.hairline(colorScheme), lineWidth: 1)
                )
        )
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Palette.surface(colorScheme))
        )
    }
}

private struct Clickpad: View {
    let up: Bool
    let down: Bool
    let left: Bool
    let right: Bool
    let select: Bool
    let touchActive: Bool
    let touchX: Float
    let touchY: Float
    let wheelActive: Bool
    let wheelAccumulated: Double
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Circle()
                .stroke(wheelActive ? Palette.accent : Palette.hairline(colorScheme), lineWidth: 14)
                .opacity(wheelActive ? 0.9 : 0.7)
                .rotationEffect(.degrees(wheelAccumulated))
            Circle()
                .fill(select ? Palette.accent.opacity(0.28) : Palette.fill(colorScheme))
                .padding(16)
                .overlay(
                    Circle()
                        .stroke(select ? Palette.accent : Palette.hairline(colorScheme), lineWidth: 1.5)
                        .padding(16)
                )
            VStack {
                edge(up)
                Spacer()
                edge(down)
            }
            .padding(28)
            HStack {
                edge(left)
                Spacer()
                edge(right)
            }
            .padding(28)
            if touchActive {
                Circle()
                    .fill(Palette.accent)
                    .frame(width: 18, height: 18)
                    .offset(x: CGFloat(touchX - 0.5) * 150, y: CGFloat(touchY - 0.5) * 150)
            } else {
                Circle()
                    .fill(select ? Palette.accent : Palette.raised(colorScheme))
                    .frame(width: 36, height: 36)
            }
            Text(wheelActive ? "CLICK WHEEL" : "CLICKPAD")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.secondaryText(colorScheme))
                .offset(y: -88)
        }
        .frame(width: 210, height: 210)
        .animation(.easeOut(duration: 0.08), value: touchActive)
    }

    private func edge(_ pressed: Bool) -> some View {
        Capsule()
            .fill(pressed ? Palette.primaryText(colorScheme) : Palette.raised(colorScheme))
            .frame(width: 28, height: 8)
    }
}

private struct VolumeHalf: View {
    let title: String
    let pressed: Bool
    let isTop: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .frame(width: 88, height: 34)
            .background {
                UnevenRoundedRectangle(
                    topLeadingRadius: isTop ? 17 : 4,
                    bottomLeadingRadius: isTop ? 4 : 17,
                    bottomTrailingRadius: isTop ? 4 : 17,
                    topTrailingRadius: isTop ? 17 : 4,
                    style: .continuous
                )
                .fill(pressed ? Palette.accent : Palette.fill(colorScheme))
            }
            .foregroundStyle(pressed ? .white : Palette.primaryText(colorScheme))
            .scaleEffect(pressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.08), value: pressed)
    }
}

private struct RemoteKey: View {
    let title: String
    let pressed: Bool
    var compact = false
    var side = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(title)
            .font(.system(size: compact ? 11 : 12, weight: .bold, design: .rounded))
            .frame(width: side ? 44 : (compact ? 72 : 88), height: side ? 132 : (compact ? 28 : 34))
            .background {
                let fill = pressed ? Palette.accent : Palette.fill(colorScheme)
                if side {
                    Capsule().fill(fill)
                } else {
                    Capsule().fill(fill)
                }
            }
            .foregroundStyle(pressed ? .white : Palette.primaryText(colorScheme))
            .scaleEffect(pressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.08), value: pressed)
    }
}

struct AppleTVSidebar: View {
    let snapshot: AppleTVRemoteSnapshot
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                panel("Last HID signal") {
                    Text(snapshot.lastHIDMappedName)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.primaryText(colorScheme))
                    Text(snapshot.lastHIDSignal)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Palette.secondaryText(colorScheme))
                    Text(snapshot.lastRawReport)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Palette.secondaryText(colorScheme))
                }
                panel("Battery") {
                    HStack {
                        Text(batteryLabel)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Palette.primaryText(colorScheme))
                        Spacer()
                        Text(snapshot.batteryAvailable ? snapshot.batteryStateDescription : "Not exposed")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(Palette.secondaryText(colorScheme))
                    }
                    Text("system_profiler does not publish a battery field for this remote (AirPods do). BLE Battery Service 0x180F is the remaining public path.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Palette.secondaryText(colorScheme))
                }
                panel("Microphone") {
                    row("Siri button", snapshot.siri)
                    ValueLine(label: "All HID reports", value: "\(snapshot.hidReports)")
                    ValueLine(label: "Button reports", value: "\(snapshot.hidButtonReports)")
                    ValueLine(label: "Large reports", value: "\(snapshot.hidLargeReports)")
                    ValueLine(label: "Mic-sized packets", value: "\(snapshot.micHIDPackets)")
                    ValueLine(label: "Level", value: String(format: "%.2f", snapshot.micLevel))
                    Text(snapshot.micSource)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Palette.secondaryText(colorScheme))
                    Text(snapshot.micArmLog)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Palette.secondaryText(colorScheme))
                    Text("Holding Siri is not enough: the Mac has to send a host enable (0xAF). This build does that on Siri-down and seizes the audio HID interface.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Palette.secondaryText(colorScheme))
                }
                panel("Clickpad / trackpad") {
                    row("Finger", snapshot.touchActive)
                    ValueLine(label: "X", value: String(format: "%.3f", snapshot.touchX))
                    ValueLine(label: "Y", value: String(format: "%.3f", snapshot.touchY))
                    ValueLine(label: "Size", value: String(format: "%.3f", snapshot.touchSize))
                    Text(snapshot.touchAvailable
                         ? "MultitouchSupport family \(snapshot.touchFamilyID)"
                         : "Waiting for MultitouchSupport (swipe the glass)")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Palette.secondaryText(colorScheme))
                }
                panel("Click wheel") {
                    row("Ring gesture", snapshot.wheelActive)
                    ValueLine(label: "Delta", value: String(format: "%+.1f°", snapshot.wheelDegrees))
                    ValueLine(label: "Total", value: String(format: "%+.1f°", snapshot.wheelAccumulated))
                    Text("Circle a finger on the outer clickpad ring. Clockwise and counterclockwise are the A2540 scrub gesture.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Palette.secondaryText(colorScheme))
                }
                panel("Buttons") {
                    row("Back", snapshot.back)
                    row("TV", snapshot.tv)
                    row("Siri", snapshot.siri)
                    row("Mute", snapshot.mute)
                    row("Play/Pause", snapshot.playPause)
                    row("Power", snapshot.power)
                    row("Volume Up", snapshot.volumeUp)
                    row("Volume Down", snapshot.volumeDown)
                }
                panel("Clickpad ring") {
                    row("Select", snapshot.select)
                    row("Up", snapshot.clickUp)
                    row("Down", snapshot.clickDown)
                    row("Left", snapshot.clickLeft)
                    row("Right", snapshot.clickRight)
                }
                panel("Recent inputs") {
                    if snapshot.events.isEmpty {
                        Text("Press buttons, swipe the pad, or circle the ring")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(Palette.secondaryText(colorScheme))
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
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
    }

    private var batteryLabel: String {
        if snapshot.batteryAvailable, let percent = snapshot.batteryPercent {
            return "\(percent)%"
        }
        return "Unknown"
    }

    private func panel<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.secondaryText(colorScheme))
                .tracking(0.8)
            VStack(alignment: .leading, spacing: 6) {
                content()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface(colorScheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func row(_ label: String, _ pressed: Bool) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Palette.secondaryText(colorScheme))
            Spacer()
            Text(pressed ? "down" : "up")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Palette.primaryText(colorScheme))
        }
    }
}

private struct ValueLine: View {
    let label: String
    let value: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack {
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
