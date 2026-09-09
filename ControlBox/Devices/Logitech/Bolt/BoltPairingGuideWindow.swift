import SwiftUI

struct BoltPairingGuideWindow: View {
    @Bindable var catalog: LogiBoltCatalog

    var body: some View {
        Group {
            if let session = catalog.pairing {
                BoltPairingGuide(session: session, catalog: catalog)
            } else {
                ContentUnavailableView(
                    "No pairing in progress",
                    systemImage: "link",
                    description: Text("Choose Add from Add Device → Logi Bolt.")
                )
            }
        }
        .frame(minWidth: 560, minHeight: 520)
        .onDisappear {
            catalog.pairingWindowClosed()
        }
    }
}

private struct BoltPairingGuide: View {
    @Bindable var session: LogiBoltPairingSession
    @Bindable var catalog: LogiBoltCatalog
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 22) {
                    statusCard
                    phaseBody
                }
                .padding(24)
            }
            Divider()
            footer
        }
        .background(Palette.background(colorScheme))
        .onChange(of: session.phase) { _, phase in
            if phase == .succeeded {
                dismissWindow(id: "bolt-pairing")
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(headerGlyph)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .foregroundStyle(Palette.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(headerTitle)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                Text(headerSubtitle)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Palette.secondaryText(colorScheme))
            }
            Spacer()
            phaseBadge
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var headerGlyph: String {
        if session.phase == .discovering {
            return DeviceKind.logitechMXMaster4.paneGlyph
        }
        return session.kind == .keyboard
            ? DeviceKind.logitechMXMechanical.paneGlyph
            : DeviceKind.logitechMXMaster4.paneGlyph
    }

    private var headerTitle: String {
        if session.phase == .discovering {
            return "Add to Logi Bolt"
        }
        if !session.discoveredName.isEmpty {
            return session.discoveredName
        }
        return "Pair \(session.kind.title)"
    }

    private var headerSubtitle: String {
        if session.phase == .discovering {
            return "Slot \(session.slot) · \(LogiBoltPairKind.mouse.channelHint)"
        }
        return session.discoveredName.isEmpty ? "Slot \(session.slot)" : "Slot \(session.slot)"
    }

    private var phaseBadge: some View {
        let text: String = {
            switch session.phase {
            case .discovering: return "Listening"
            case .connecting: return "Pairing"
            case .enterPasskey: return "Enter passkey"
            case .succeeded: return "Paired"
            case .failed: return "Failed"
            case .cancelled: return "Cancelled"
            }
        }()
        let tint: Color = {
            switch session.phase {
            case .succeeded: return Palette.good
            case .failed, .cancelled: return Palette.bad
            default: return Palette.accent
            }
        }()
        return Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.16), in: Capsule())
    }

    private var statusCard: some View {
        HStack(alignment: .top, spacing: 12) {
            if session.phase == .discovering || session.phase == .connecting {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 2)
            }
            Text(session.status)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Palette.primaryText(colorScheme))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Palette.surface(colorScheme))
        )
    }

    @ViewBuilder
    private var phaseBody: some View {
        switch session.phase {
        case .discovering:
            discoveredList
        case .connecting:
            EmptyView()
        case .enterPasskey, .succeeded:
            if session.kind == .keyboard {
                keyboardGuide
            } else {
                mouseGuide
            }
        case .failed, .cancelled:
            EmptyView()
        }
    }

    private var discoveredList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Available")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.secondaryText(colorScheme))
            if session.discovered.isEmpty {
                Text("Waiting for a device in pairing mode.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Palette.secondaryText(colorScheme))
            } else {
                ForEach(session.discovered) { device in
                    Button {
                        session.select(device)
                    } label: {
                        discoveredRow(device)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func discoveredRow(_ device: LogiBoltDiscoveredDevice) -> some View {
        HStack(spacing: 12) {
            Image(device.deviceKind.isSupported ? device.deviceKind.paneGlyph : device.deviceClass.paneGlyph)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.displayName)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.primaryText(colorScheme))
                Text(device.detail)
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText(colorScheme))
            }
            Spacer()
            if device.deviceKind.isSupported {
                Text("Supported")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Palette.accent.opacity(0.16), in: Capsule())
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Palette.fill(colorScheme))
        )
        .contentShape(Rectangle())
    }

    private var mouseGuide: some View {
        VStack(alignment: .leading, spacing: 14) {
            if session.mouseClicks.isEmpty {
                Text("The click sequence appears here once the receiver shares the passkey.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Palette.secondaryText(colorScheme))
            } else {
                Text("Click this sequence")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.secondaryText(colorScheme))
                BoltFlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(Array(session.mouseClicks.enumerated()), id: \.offset) { index, click in
                        let done = index < session.enteredCount
                        let current = index == session.enteredCount && session.phase == .enterPasskey && !session.highlightBoth
                        mouseWord(click.title, done: done, current: current)
                    }
                    if session.highlightBoth || session.enteredCount >= session.mouseClicks.count {
                        mouseWord("Left + Right", done: false, current: session.highlightBoth)
                    }
                }
                Text(session.highlightBoth
                     ? "Now click Left and Right together."
                     : "\(min(session.enteredCount, session.expectedCount)) of \(session.expectedCount)")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Palette.secondaryText(colorScheme))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func mouseWord(_ title: String, done: Bool, current: Bool) -> some View {
        Text(title)
            .font(.system(size: 22, weight: .semibold, design: .rounded))
            .padding(.horizontal, 4)
            .foregroundStyle(mouseWordForeground(done: done, current: current))
            .background(mouseWordBackground(current: current))
    }

    private func mouseWordForeground(done: Bool, current: Bool) -> Color {
        if current {
            return colorScheme == .dark ? Palette.background(colorScheme) : Color.white
        }
        if done {
            return Palette.secondaryText(colorScheme).opacity(0.55)
        }
        return Palette.primaryText(colorScheme).opacity(0.38)
    }

    private func mouseWordBackground(current: Bool) -> Color {
        guard current else { return .clear }
        return Palette.primaryText(colorScheme)
    }

    private var keyboardGuide: some View {
        VStack(spacing: 18) {
            if session.passkey.isEmpty {
                Text("The pairing code appears here once the receiver shares it.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Palette.secondaryText(colorScheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 10) {
                    ForEach(Array(session.passkeyCharacters.enumerated()), id: \.offset) { index, digit in
                        let done = index < session.enteredCount
                        let current = index == session.enteredCount && session.phase == .enterPasskey
                        Text(String(digit))
                            .font(.system(size: 32, weight: .semibold, design: .rounded))
                            .frame(width: 52, height: 64)
                            .foregroundStyle(done || current ? Palette.primaryText(colorScheme) : Palette.secondaryText(colorScheme))
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(chipFill(done: done, current: current))
                            )
                            .overlay {
                                if current {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Palette.accent, lineWidth: 2)
                                }
                            }
                    }
                }
                Text("Then press Return.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Palette.secondaryText(colorScheme))
                returnKey(lit: session.enteredCount >= session.expectedCount && session.phase == .enterPasskey)
            }
        }
    }

    private func returnKey(lit: Bool) -> some View {
        Text("Return")
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .frame(width: 140, height: 44)
            .foregroundStyle(lit ? Color.white : Palette.primaryText(colorScheme))
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(lit ? Palette.good : Palette.surface(colorScheme))
            )
    }

    private func chipFill(done: Bool, current: Bool) -> Color {
        if done { return Palette.good.opacity(colorScheme == .dark ? 0.35 : 0.28) }
        if current { return Palette.accent.opacity(colorScheme == .dark ? 0.28 : 0.18) }
        return Palette.fill(colorScheme)
    }

    private var footer: some View {
        HStack {
            if session.phase.isFinished {
                Button("Close") {
                    dismissWindow(id: "bolt-pairing")
                }
                if case .failed = session.phase {
                    Button("Try Again") {
                        session.retry()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            } else {
                Button("Cancel") {
                    catalog.cancelPairing()
                    dismissWindow(id: "bolt-pairing")
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

private struct BoltFlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: ProposedViewSize(width: bounds.width, height: bounds.height), subviews: subviews)
        for index in subviews.indices {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + result.origins[index].x, y: bounds.minY + result.origins[index].y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (origins: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var width: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            width = max(width, x + size.width)
            x += size.width + spacing
        }
        return (origins, CGSize(width: width, height: y + rowHeight))
    }
}
