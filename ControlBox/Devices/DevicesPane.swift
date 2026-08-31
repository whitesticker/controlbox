import SwiftUI

struct AddDeviceSheet: View {
    @Bindable var monitor: DualSenseMonitor
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if monitor.addableDevices.isEmpty {
                        Text("No other supported device is available. Connect a DualSense, Apple TV remote, MX Master, or MX Mechanical, or pair it in Bluetooth settings.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(monitor.addableDevices) { device in
                            Button {
                                monitor.addDevice(device)
                                dismiss()
                            } label: {
                                deviceRow(device, showsAdd: true)
                            }
                        }
                    }
                } header: {
                    Text("Available")
                } footer: {
                    footerBullets(
                        "Supported devices stay in the sidebar after they sleep.",
                        "Use Add Device if a paired one is missing."
                    )
                }

                Section("Not supported yet") {
                    if monitor.unsupportedDevices.isEmpty {
                        Text("No other Bluetooth devices connected")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(monitor.unsupportedDevices) { device in
                            deviceRow(device, showsAdd: false)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Add Device")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 440, minHeight: 380)
        .onAppear {
            monitor.reloadDevices()
        }
    }

    private func deviceRow(_ device: ConnectedBluetoothDevice, showsAdd: Bool) -> some View {
        HStack(spacing: 12) {
            Image(device.deviceKind.paneGlyph)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                Text(device.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(device.isConnected ? "Connected · \(device.address)" : "Not connected · \(device.address)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if showsAdd {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
    }
}
