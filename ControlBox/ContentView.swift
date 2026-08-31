import SwiftUI

struct ContentView: View {
    @Bindable var monitor: DualSenseMonitor
    @Bindable var arrangementCatalog: ArrangementCatalog
    @Bindable var nightShiftCatalog: NightShiftCatalog
    @Bindable var displayCatalog: DisplayCatalog
    @Bindable var soundCatalog: SoundCatalog
    @Bindable var dockPreviewCatalog: DockPreviewCatalog
    @Bindable var capsLockCatalog: CapsLockCatalog
    @Environment(\.colorScheme) private var colorScheme
    @State private var showAddDevice = false
    @State private var selection: SidebarItem = .displays

    var body: some View {
        NavigationSplitView {
            List(selection: sidebarSelection) {
                Section("Mac") {
                    macRow(.displays)
                    macRow(.nightShift)
                    macRow(.displayArrangement)
                    macRow(.sound)
                    macRow(.systemMonitor)
                    macRow(.pointerScroll)
                    macRow(.windowGrab)
                    macRow(.capsLock)
                    macRow(.dockPreview)
                }
                Section("Devices") {
                    if monitor.sidebarDevices.isEmpty {
                        Text("No devices yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(monitor.sidebarDevices) { device in
                            DeviceSidebarRow(device: device)
                                .tag(SidebarItem.device(device.id))
                        }
                    }
                }
                Section("App") {
                    HStack(spacing: 8) {
                        SettingsGlyph(symbol: SidebarItem.permissions.symbol, tint: SidebarItem.permissions.tint)
                        Text(SidebarItem.permissions.title)
                        Spacer(minLength: 8)
                        Circle()
                            .fill(monitor.allPermissionsGranted ? Palette.good : Palette.bad)
                            .frame(width: 8, height: 8)
                    }
                    .tag(SidebarItem.permissions)
                }
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    Divider()
                    Button {
                        showAddDevice = true
                    } label: {
                        Label("Add Device…", systemImage: "plus")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .background(.bar)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 248, max: 300)
            .sheet(isPresented: $showAddDevice) {
                AddDeviceSheet(monitor: monitor)
            }
        } detail: {
            switch selection {
            case .displays:
                DisplaysPane(catalog: displayCatalog)
            case .nightShift:
                NightShiftPane(catalog: nightShiftCatalog)
            case .displayArrangement:
                DisplayArrangementPane(catalog: arrangementCatalog, monitor: monitor)
            case .sound:
                SoundPane(catalog: soundCatalog)
            case .systemMonitor:
                TopPane()
            case .pointerScroll:
                PointerScrollPane(monitor: monitor)
            case .windowGrab:
                WindowGrabPane(monitor: monitor, arrangementCatalog: arrangementCatalog)
            case .capsLock:
                CapsLockPane(catalog: capsLockCatalog)
            case .dockPreview:
                DockPreviewPane(catalog: dockPreviewCatalog)
            case .permissions:
                PrivacyPane(monitor: monitor)
            case .device:
                DeviceProfilePane(monitor: monitor)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .foregroundStyle(Palette.primaryText(colorScheme))
        .background(Palette.background(colorScheme).ignoresSafeArea())
        .onAppear {
            applyPendingPane()
        }
        .onReceive(NotificationCenter.default.publisher(for: .controlBoxOpenPane)) { _ in
            applyPendingPane()
        }
        .onReceive(NotificationCenter.default.publisher(for: .controlBoxOpenSystemMonitor)) { _ in
            PaneNavigation.pending = .systemMonitor
            applyPendingPane()
        }
    }

    private func applyPendingPane() {
        if TopNavigation.pendingOpen {
            TopNavigation.pendingOpen = false
            selection = .systemMonitor
        }
        if let pending = PaneNavigation.pending {
            PaneNavigation.pending = nil
            selection = pending
        }
    }

    private func macRow(_ item: SidebarItem) -> some View {
        HStack(spacing: 8) {
            SettingsGlyph(symbol: item.symbol, tint: item.tint)
            Text(item.title)
        }
        .tag(item)
    }

    private var sidebarSelection: Binding<SidebarItem> {
        Binding(
            get: { selection },
            set: { item in
                selection = item
                if case .device(let id) = item {
                    monitor.selectDevice(id: id)
                }
            }
        )
    }
}

private struct DeviceSidebarRow: View {
    let device: SidebarDevice

    var body: some View {
        HStack(spacing: 8) {
            SettingsGlyph(
                symbol: device.symbol,
                tint: device.kind == .appleTVRemote
                    ? Color(red: 0.35, green: 0.34, blue: 0.84)
                    : Color(red: 0.20, green: 0.48, blue: 0.96)
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .lineLimit(1)
                Text(device.statusTitle)
                    .font(.caption)
                    .foregroundStyle(device.isConnected ? Palette.good : .secondary)
            }
            Spacer(minLength: 8)
            Circle()
                .fill(device.isConnected ? Palette.good : Color.secondary.opacity(0.55))
                .frame(width: 8, height: 8)
        }
    }
}

struct CalibrationWindow: View {
    @Bindable var monitor: DualSenseMonitor
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Calibration")
                        .font(.largeTitle.weight(.bold))
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Circle()
                    .fill(isLive ? Palette.good : Palette.bad)
                    .frame(width: 10, height: 10)
                Text(isLive ? "Live" : "Not connected")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if monitor.selectedKind == .appleTVRemote {
                AppleTVHeaderBar(snapshot: monitor.appleTVSnapshot)
                HStack(alignment: .top, spacing: 18) {
                    AppleTVRemoteView(snapshot: monitor.appleTVSnapshot)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    AppleTVSidebar(snapshot: monitor.appleTVSnapshot)
                        .frame(width: 360)
                }
            } else if monitor.selectedKind.isMXMaster {
                MXMasterCalibrationView(snapshot: monitor.mxMasterSnapshot)
            } else if monitor.selectedKind.isMXKeyboard {
                ContentUnavailableView(
                    "No calibration for this keyboard",
                    systemImage: "keyboard",
                    description: Text("MX Mechanical settings live on the device page: backlight, lighting effect, and battery.")
                )
            } else {
                HeaderBar(snapshot: monitor.snapshot)
                HStack(alignment: .top, spacing: 18) {
                    ControllerDiagramView(snapshot: monitor.snapshot)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    CaptureSidebar(snapshot: monitor.snapshot)
                        .frame(width: 360)
                }
                MicrophoneStatusView(
                    dualSenseAudioPresent: monitor.dualSenseAudioPresent,
                    audioInputs: monitor.audioInputs
                )
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background(colorScheme))
        .navigationTitle("Calibration")
    }

    private var isLive: Bool {
        if monitor.selectedKind == .appleTVRemote {
            return monitor.appleTVSnapshot.connected
        }
        if monitor.selectedKind.isMXMaster {
            return monitor.isLiveMXSelection()
        }
        if monitor.selectedKind.isMXKeyboard {
            return monitor.isLiveKeyboardSelection()
        }
        return monitor.snapshot.connected
    }

    private var subtitle: String {
        if let name = monitor.selectedRecord?.name {
            return "Live capture for \(name)"
        }
        return "Live capture for the selected device"
    }
}

private struct HeaderBar: View {
    let snapshot: DualSenseSnapshot
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(snapshot.connected ? Palette.good : Palette.bad)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.connected ? snapshot.name : "Waiting for DualSense")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.primaryText(colorScheme))
                Text(statusLine)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.secondaryText(colorScheme))
            }

            Spacer()

            if snapshot.connected {
                BatteryBadge(
                    percent: snapshot.batteryPercent,
                    charging: snapshot.batteryCharging,
                    full: snapshot.batteryFull,
                    available: snapshot.batteryAvailable,
                    stateDescription: snapshot.batteryStateDescription
                )
                StatusChip(title: snapshot.isDualSense ? "DualSense profile" : "Generic gamepad", tint: Palette.accent)
                StatusChip(
                    title: snapshot.hasMotion ? "Motion on" : "No motion",
                    tint: snapshot.hasMotion ? Palette.good : Palette.secondaryText(colorScheme)
                )
            }
        }
        .padding(.horizontal, 4)
    }

    private var statusLine: String {
        if !snapshot.connected {
            return "Press the PS button if the controller is paired but idle"
        }
        return snapshot.product
    }
}

private struct AppleTVHeaderBar: View {
    let snapshot: AppleTVRemoteSnapshot
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(snapshot.connected ? Palette.good : Palette.bad)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.connected ? snapshot.name : "Waiting for Apple TV Remote")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.primaryText(colorScheme))
                Text(snapshot.connected ? snapshot.product : "Press any button on the remote to wake it")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.secondaryText(colorScheme))
            }

            Spacer()

            if snapshot.connected {
                BatteryBadge(
                    percent: snapshot.batteryPercent,
                    charging: snapshot.batteryCharging,
                    full: snapshot.batteryFull,
                    available: snapshot.batteryAvailable,
                    stateDescription: snapshot.batteryStateDescription
                )
                StatusChip(title: "HID capture", tint: Palette.accent)
                StatusChip(title: "Siri Remote", tint: Palette.good)
            }
        }
        .padding(.horizontal, 4)
    }
}

private struct BatteryBadge: View {
    var percent: Int?
    var charging = false
    var full = false
    var available = false
    var stateDescription = "Unknown"
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbolName)
            Text(label)
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(colorScheme == .dark ? 0.22 : 0.16), in: Capsule())
        .foregroundStyle(colorScheme == .dark ? .white : tint)
    }

    private var label: String {
        guard available, let percent else {
            return "Battery unknown"
        }
        if full {
            return "\(percent)% · Full"
        }
        if charging {
            return "\(percent)% · Charging"
        }
        return "\(percent)% · \(stateDescription)"
    }

    private var symbolName: String {
        if charging || full {
            return "battery.100percent.bolt"
        }
        guard available, let percent else {
            return "battery.0percent"
        }
        switch percent {
        case 90...: return "battery.100percent"
        case 65...: return "battery.75percent"
        case 35...: return "battery.50percent"
        case 10...: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    private var tint: Color {
        guard available, let percent else {
            return Palette.secondaryText(colorScheme)
        }
        if charging || full { return Palette.good }
        if percent <= 15 { return Palette.bad }
        if percent <= 30 { return .orange }
        return Palette.good
    }
}

private struct StatusChip: View {
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

private struct CaptureSidebar: View {
    let snapshot: DualSenseSnapshot
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Panel(title: "Analog") {
                ValueRow(label: "Left stick", value: format(snapshot.leftStick))
                ValueRow(label: "Right stick", value: format(snapshot.rightStick))
                ValueRow(label: "L2", value: String(format: "%.3f", snapshot.l2))
                ValueRow(label: "R2", value: String(format: "%.3f", snapshot.r2))
            }

            Panel(title: "Touchpad") {
                ValueRow(label: "Click", value: snapshot.touchpadClick ? "down" : "up")
                ValueRow(label: "Finger 1", value: format(snapshot.touch1))
                ValueRow(label: "Finger 2", value: format(snapshot.touch2))
                Text("Hardware limit: 2 fingers at once")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Palette.secondaryText(colorScheme))
            }

            Panel(title: "Motion") {
                if snapshot.hasMotion {
                    ValueRow(label: "Gravity", value: format(snapshot.gravity))
                    ValueRow(label: "Accel", value: format(snapshot.userAcceleration))
                    ValueRow(label: "Gyro", value: format(snapshot.rotationRate))
                } else {
                    Text("No IMU data")
                        .foregroundStyle(Palette.secondaryText(colorScheme))
                        .font(.system(size: 12, design: .rounded))
                }
            }

            Panel(title: "Recent inputs") {
                if snapshot.events.isEmpty {
                    Text("Press buttons, move sticks, or use the touchpad")
                        .foregroundStyle(Palette.secondaryText(colorScheme))
                        .font(.system(size: 12, design: .rounded))
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(snapshot.events) { event in
                                HStack(spacing: 8) {
                                    Text(event.pressed ? "↓" : "↑")
                                        .foregroundStyle(event.pressed ? Palette.good : Palette.secondaryText(colorScheme))
                                        .frame(width: 12)
                                    Text(event.label)
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(Palette.primaryText(colorScheme))
                                    Spacer()
                                    Text(event.date, style: .time)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(Palette.secondaryText(colorScheme))
                                }
                            }
                        }
                    }
                    .frame(minHeight: 140)
                }
            }
        }
    }

    private func format(_ stick: SIMD2<Float>) -> String {
        String(format: "x %.3f   y %.3f", stick.x, stick.y)
    }

    private func format(_ finger: TouchFinger) -> String {
        if finger.active {
            return String(format: "x %.3f   y %.3f", finger.x, finger.y)
        }
        return "up"
    }

    private func format(_ vector: Vec3) -> String {
        String(format: "x %.2f  y %.2f  z %.2f", vector.x, vector.y, vector.z)
    }
}

private struct Panel<Content: View>: View {
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

private struct ValueRow: View {
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
