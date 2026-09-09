import SwiftUI

struct MicrophoneStatusView: View {
    var dualSenseAudioPresent = false
    var audioInputs: [String] = []
    var title: String?
    var detailOverride: String?
    var available: Bool?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: isAvailable ? "mic.fill" : "mic.slash.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isAvailable ? Palette.good : Palette.bad)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(headline)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.primaryText(colorScheme))
                Text(bodyText)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Palette.secondaryText(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(14)
        .background(Palette.surface(colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var isAvailable: Bool {
        available ?? dualSenseAudioPresent
    }

    private var headline: String {
        if let title { return title }
        return dualSenseAudioPresent ? "DualSense audio device found" : "Microphone not available over Bluetooth"
    }

    private var bodyText: String {
        if let detailOverride { return detailOverride }
        if dualSenseAudioPresent {
            return "A DualSense-related audio input is on this Mac: \(audioInputs.joined(separator: ", ")). Speak into the controller to verify capture next."
        }
        let listed = audioInputs.isEmpty ? "none" : audioInputs.joined(separator: ", ")
        return "Sony does not expose the built-in DualSense mic or speaker on macOS. This Bluetooth connection is HID-only (gamepad), so Core Audio currently sees: \(listed). The 3.5 mm headset jack can work over USB; we can probe that later."
    }
}