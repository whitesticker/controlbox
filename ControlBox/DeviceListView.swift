import SwiftUI

struct DeviceListView: View {
    let devices: [ConnectedBluetoothDevice]
    let selectedID: String?
    let onSelect: (ConnectedBluetoothDevice) -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var supported: [ConnectedBluetoothDevice] {
        devices.filter(\.isSupported)
    }

    private var unsupported: [ConnectedBluetoothDevice] {
        devices.filter { !$0.isSupported }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Devices")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.secondaryText(colorScheme))
                .tracking(0.8)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    DeviceGroup(title: "Supported") {
                        if supported.isEmpty {
                            Text("No supported device connected")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(Palette.secondaryText(colorScheme))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 6)
                        } else {
                            ForEach(supported) { device in
                                Button {
                                    onSelect(device)
                                } label: {
                                    DeviceRow(
                                        device: device,
                                        isSelected: device.id == selectedID,
                                        enabled: true
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    DeviceGroup(title: "Not supported yet") {
                        if unsupported.isEmpty {
                            Text("No other Bluetooth devices connected")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(Palette.secondaryText(colorScheme))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 6)
                        } else {
                            ForEach(unsupported) { device in
                                DeviceRow(
                                    device: device,
                                    isSelected: false,
                                    enabled: false
                                )
                                .allowsHitTesting(false)
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Palette.surface(colorScheme))
        )
    }
}

private struct DeviceGroup<Content: View>: View {
    let title: String
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.secondaryText(colorScheme))
                .tracking(0.7)
            VStack(spacing: 6) {
                content
            }
        }
    }
}

private struct DeviceRow: View {
    let device: ConnectedBluetoothDevice
    let isSelected: Bool
    let enabled: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(enabled ? Palette.primaryText(colorScheme) : Palette.secondaryText(colorScheme))
                    .lineLimit(2)
                Text(device.detail)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Palette.secondaryText(colorScheme))
                    .lineLimit(1)
                Text(device.address)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Palette.secondaryText(colorScheme).opacity(0.8))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Palette.accent)
            }
        }
        .padding(10)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(enabled ? 1 : 0.55)
        .accessibilityAddTraits(enabled ? .isButton : .isStaticText)
    }

    private var iconName: String {
        if !enabled { return "antenna.radiowaves.left.and.right" }
        switch device.deviceKind {
        case .appleTVRemote: return "appletvremote"
        case .logitechMXMaster, .logitechMXMaster3, .logitechMXMaster3S, .logitechMXMaster4:
            return "computermouse.fill"
        case .logitechMXMechanical, .logitechMXMechanicalMini:
            return "keyboard.fill"
        default: return "gamecontroller.fill"
        }
    }

    private var iconColor: Color {
        if !enabled { return Palette.secondaryText(colorScheme) }
        return isSelected ? Palette.accent : Palette.primaryText(colorScheme)
    }

    private var rowBackground: Color {
        if isSelected {
            return Palette.accent.opacity(colorScheme == .dark ? 0.22 : 0.14)
        }
        return Palette.fill(colorScheme)
    }
}
