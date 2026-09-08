import AppKit
import SwiftUI

private enum AddDevicePanel: String, CaseIterable, Identifiable {
    case bluetooth = "Bluetooth"
    case bolt = "Logi Bolt"

    var id: String { rawValue }
}

struct AddDeviceSheet: View {
    @Bindable var monitor: DualSenseMonitor
    @Bindable var bolt: LogiBoltCatalog
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @State private var panel: AddDevicePanel = .bluetooth
    @State private var pendingUnpair: LogiBoltPairedDevice?
    @State private var boltAlert: String?
    @State private var showSupported = false
    var onOpenDevice: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            NavigationStack {
                VStack(spacing: 0) {
                    addDeviceHeader
                    addDeviceBody
                }
                .navigationTitle("Add Device")
                .navigationDestination(isPresented: $showSupported) {
                    SupportedDevicesGuide()
                }
            }
            addDeviceFooter
        }
        .frame(minWidth: 560, minHeight: 520)
        .animation(.easeInOut(duration: 0.24), value: panel)
        .onAppear {
            monitor.reloadDevices()
            bolt.sheetAppeared()
        }
        .onDisappear {
            bolt.sheetDisappeared()
        }
        .alert("Remove from Logi Bolt?", isPresented: unpairPresented) {
            Button("Remove", role: .destructive) {
                confirmUnpair()
            }
            Button("Cancel", role: .cancel) {
                pendingUnpair = nil
            }
        } message: {
            if let device = pendingUnpair {
                Text("\(device.displayName) will have to be paired again to use this receiver.")
            }
        }
        .alert("Logi Bolt", isPresented: boltAlertPresented) {
            Button("OK", role: .cancel) { boltAlert = nil }
        } message: {
            Text(boltAlert ?? "")
        }
    }

    private var addDeviceHeader: some View {
        Picker("Connection", selection: $panel.animation(.easeInOut(duration: 0.24))) {
            ForEach(AddDevicePanel.allCases) { item in
                Text(item.rawValue).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 280)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    /// Both pages stay laid out so the sheet keeps one size; the segmented
    /// control crossfades instead of swapping height.
    private var addDeviceBody: some View {
        ZStack {
            bluetoothList
                .opacity(panel == .bluetooth ? 1 : 0)
                .offset(x: panel == .bluetooth ? 0 : -12)
                .allowsHitTesting(panel == .bluetooth)
                .accessibilityHidden(panel != .bluetooth)
            boltList
                .opacity(panel == .bolt ? 1 : 0)
                .offset(x: panel == .bolt ? 0 : 12)
                .allowsHitTesting(panel == .bolt)
                .accessibilityHidden(panel != .bolt)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var addDeviceFooter: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Button("Supported Device") {
                    showSupported = true
                }
                .buttonStyle(.bordered)
                .disabled(showSupported)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private var bluetoothList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AddDeviceCard(title: "Connected") {
                    if monitor.bluetoothConnectedDevices.isEmpty {
                        AddDeviceEmptyText("No devices connected")
                    } else {
                        ForEach(monitor.bluetoothConnectedDevices) { device in
                            bluetoothRow(device)
                        }
                    }
                }
                AddDeviceCard(title: "Disconnected") {
                    if monitor.bluetoothDisconnectedDevices.isEmpty {
                        AddDeviceEmptyText("No disconnected devices")
                    } else {
                        ForEach(monitor.bluetoothDisconnectedDevices) { device in
                            bluetoothRow(device)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private var boltList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if bolt.receivers.isEmpty {
                    AddDeviceCard(title: "Receiver") {
                        AddDeviceEmptyText("Plug in a Logi Bolt receiver to continue.")
                    }
                } else {
                    ForEach(bolt.receivers) { receiver in
                        boltReceiverCard(receiver)
                    }
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func boltReceiverCard(_ receiver: LogiBoltReceiverSnapshot) -> some View {
        AddDeviceCard(title: receiver.title, footer: boltFooter(receiver)) {
            if receiver.isLoading, receiver.devices.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(receiver.status ?? "Reading paired devices…")
                        .foregroundStyle(.secondary)
                }
            } else if receiver.devices.isEmpty {
                AddDeviceEmptyText("No devices paired to this receiver.")
            } else {
                ForEach(receiver.devices.sorted { lhs, rhs in
                    if lhs.online != rhs.online { return lhs.online && !rhs.online }
                    return lhs.slot < rhs.slot
                }) { device in
                    BoltPairedRow(device: device, onSettings: {
                        openBoltSettings(device)
                    }, onRemove: {
                        pendingUnpair = device
                    })
                }
            }
            boltActions(receiver)
        }
    }

    private func boltActions(_ receiver: LogiBoltReceiverSnapshot) -> some View {
        HStack(spacing: 12) {
            Button("Add") {
                startPairing(receiverID: receiver.id)
            }
            .disabled(!receiver.hasEmptySlot || receiver.isLoading || pairingBusy)
            Spacer()
            Button("Refresh", action: bolt.refresh)
                .disabled(receiver.isLoading || pairingBusy)
        }
    }

    private var pairingBusy: Bool {
        if let pairing = bolt.pairing { return !pairing.phase.isFinished }
        return false
    }

    private func boltFooter(_ receiver: LogiBoltReceiverSnapshot) -> String {
        let used = max(receiver.pairedCount, receiver.devices.count)
        let slots = receiver.slotCount
        if !receiver.hasEmptySlot {
            return "\(used) of \(slots) slots used. Remove a device to pair another."
        }
        return "\(used) of \(slots) slots used."
    }

    private func startPairing(receiverID: String) {
        if let error = bolt.beginPairing(receiverID: receiverID) {
            boltAlert = error
            return
        }
        openWindow(id: "bolt-pairing")
        NSApp.activate()
    }

    private func confirmUnpair() {
        guard let device = pendingUnpair else { return }
        pendingUnpair = nil
        bolt.unpair(receiverID: device.receiverID, slot: device.slot) { error in
            boltAlert = error
        }
    }

    private var unpairPresented: Binding<Bool> {
        Binding(
            get: { pendingUnpair != nil },
            set: { if !$0 { pendingUnpair = nil } }
        )
    }

    private var boltAlertPresented: Binding<Bool> {
        Binding(
            get: { boltAlert != nil },
            set: { if !$0 { boltAlert = nil } }
        )
    }

    @ViewBuilder
    private func bluetoothRow(_ device: ConnectedBluetoothDevice) -> some View {
        deviceRow(device)
    }

    private func deviceRow(_ device: ConnectedBluetoothDevice) -> some View {
        HStack(spacing: 12) {
            Group {
                if device.isSupported {
                    Image(device.deviceKind.paneGlyph)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                } else {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 18, height: 18)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                Text(device.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(device.address)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            DeviceStatusTag(online: device.isConnected)
            if device.isSupported {
                Text("Supported")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color(nsColor: .systemBlue))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color(nsColor: .systemBlue).opacity(0.16), in: Capsule())
                Button("Settings") {
                    openDeviceSettings(device)
                }
                .buttonStyle(.borderless)
            }
        }
        .contentShape(Rectangle())
        .addDeviceRowChrome()
    }

    private func openDeviceSettings(_ device: ConnectedBluetoothDevice) {
        monitor.addDevice(device)
        if let id = monitor.selectedDeviceID {
            onOpenDevice(id)
        }
        dismiss()
    }

    private func openBoltSettings(_ device: LogiBoltPairedDevice) {
        if let match = matchingBluetoothDevice(for: device) {
            openDeviceSettings(match)
            return
        }
        openDeviceSettings(device.asConnectedDevice())
    }

    private func matchingBluetoothDevice(for bolt: LogiBoltPairedDevice) -> ConnectedBluetoothDevice? {
        let candidates = monitor.bluetoothConnectedDevices + monitor.bluetoothDisconnectedDevices + monitor.connectedDevices
        return candidates.first { DeviceIdentity.sameLogitech($0.logitechKey, bolt.logitechKey) }
    }
}

private struct BoltPairedRow: View {
    let device: LogiBoltPairedDevice
    var onSettings: () -> Void
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(device.deviceKind.isSupported ? device.deviceKind.paneGlyph : device.deviceClass.paneGlyph)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.displayName)
                Text(device.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            DeviceStatusTag(online: device.online)
            if device.deviceKind.isSupported {
                Button("Settings", action: onSettings)
                    .buttonStyle(.borderless)
            }
            Button("Remove", role: .destructive, action: onRemove)
                .buttonStyle(.borderless)
        }
        .addDeviceRowChrome()
    }
}

private struct DeviceStatusTag: View {
    let online: Bool

    var body: some View {
        let tint = online ? Palette.good : Palette.bad
        Text(online ? "Online" : "Not connected")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.16), in: Capsule())
    }
}

private struct SupportedDevicesGuide: View {
    private let brands: [(String, [DeviceKind])] = [
        ("Sony", [.dualSense, .dualSenseEdge]),
        ("Apple", [.appleTVRemote]),
        (
            "Logitech",
            [
                .logitechMXMaster3,
                .logitechMXMaster3S,
                .logitechMXMaster4,
                .logitechMXMechanical,
                .logitechMXMechanicalMini
            ]
        )
    ]

    private let tileColumns = [
        GridItem(.adaptive(minimum: 148), spacing: 6)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(brands, id: \.0) { brand, kinds in
                    AddDeviceCard(title: brand) {
                        LazyVGrid(columns: tileColumns, spacing: 6) {
                            ForEach(kinds, id: \.self) { kind in
                                SupportedDeviceTile(kind: kind)
                            }
                        }
                        if brand == "Logitech" {
                            Text("Logi Bolt supports this family. Only MX Master 3S, MX Master 4, and MX Mechanical have been tested here — those are the devices on this desk.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 4)
                        }
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle("Supported Device")
    }
}

private struct SupportedDeviceTile: View {
    let kind: DeviceKind
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            Image(kind.paneGlyph)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
            Text(kind.title)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Palette.fill(colorScheme), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct AddDeviceCard<Content: View>: View {
    let title: String
    var footer: String? = nil
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            VStack(alignment: .leading, spacing: 8) {
                content
            }
            if let footer, !footer.isEmpty {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface(colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Palette.hairline(colorScheme), lineWidth: 1)
        )
    }
}

private struct AddDeviceEmptyText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 13, design: .rounded))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }
}

private struct AddDeviceRowChrome: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.fill(colorScheme), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private extension View {
    func addDeviceRowChrome() -> some View {
        modifier(AddDeviceRowChrome())
    }
}
