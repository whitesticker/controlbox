import SwiftUI

/// Label on the leading edge, centered on the full slider; ticks and value trail.
struct SettingsSlider: View {
    private let title: String
    private let detail: String?
    @Binding private var value: Double
    private var range: ClosedRange<Double>
    private var step: Double?
    private var enabled: Bool
    private var valueText: String?

    init(
        _ title: String,
        description: String? = nil,
        value: Binding<Double>,
        in range: ClosedRange<Double> = 0...1,
        step: Double? = nil,
        enabled: Bool = true,
        valueText: String? = nil
    ) {
        self.title = title
        self.detail = description
        self._value = value
        self.range = range
        self.step = step
        self.enabled = enabled
        self.valueText = valueText
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            label
            LinearTickSlider(value: $value, in: range, step: step)
                .frame(maxWidth: .infinity)
            Text(displayedValue)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: 52, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityName)
        .accessibilityValue(displayedValue)
        .accessibilityAdjustableAction { direction in
            let span = range.upperBound - range.lowerBound
            let delta = step ?? span / 20
            switch direction {
            case .increment:
                value = min(value + delta, range.upperBound)
            case .decrement:
                value = max(value - delta, range.lowerBound)
            @unknown default:
                break
            }
        }
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.leading)
        .frame(width: 156, alignment: .leading)
    }

    private var accessibilityName: String {
        if let detail {
            return "\(title), \(detail)"
        }
        return title
    }

    private var displayedValue: String {
        if let valueText { return valueText }
        let span = range.upperBound - range.lowerBound
        let progress = span > 0 ? (value - range.lowerBound) / span : 0
        return "\(Int((progress * 100).rounded()))%"
    }
}

private struct LinearTickSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double?

    init(value: Binding<Double>, in range: ClosedRange<Double>, step: Double?) {
        self._value = value
        self.range = range
        self.step = step
    }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    private static let trackHeight: CGFloat = 6
    private static let thumbWidth: CGFloat = 8
    private static let thumbHeight: CGFloat = 18

    private var trackHeight: CGFloat { Self.trackHeight }
    private var thumbWidth: CGFloat { Self.thumbWidth }
    private var thumbHeight: CGFloat { Self.thumbHeight }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let t = progress
            let thumbCenter = thumbWidth / 2 + t * max(width - thumbWidth, 0)

            VStack(spacing: 5) {
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(trackEmpty)
                        .frame(height: trackHeight)
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(trackHeight, thumbCenter), height: trackHeight)
                    Capsule()
                        .fill(thumbFill)
                        .overlay {
                            Capsule()
                                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                        }
                        .shadow(color: .black.opacity(colorScheme == .dark ? 0.45 : 0.18), radius: 1, y: 0.5)
                        .frame(width: thumbWidth, height: thumbHeight)
                        .offset(x: thumbCenter - thumbWidth / 2)
                }
                .frame(height: thumbHeight)

                tickRow(width: width)
            }
            .frame(width: width, height: geo.size.height, alignment: .top)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        value = value(at: drag.location.x, width: width)
                    }
            )
        }
        .frame(height: 30)
        .opacity(isEnabled ? 1 : 0.55)
    }

    private var progress: CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return CGFloat(min(max((value - range.lowerBound) / span, 0), 1))
    }

    private var tickCount: Int {
        if let step, step > 0 {
            let count = Int((range.upperBound - range.lowerBound) / step + 0.5) + 1
            if (2...21).contains(count) { return count }
        }
        return 11
    }

    private var thumbFill: Color {
        colorScheme == .dark ? Color(white: 0.84) : Color(white: 0.99)
    }

    private var trackEmpty: Color {
        colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.10)
    }

    private func tickRow(width: CGFloat) -> some View {
        let count = tickCount
        let inset = thumbWidth / 2
        return HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                let major = index == 0 || index == count - 1 || index == count / 2
                Capsule()
                    .fill(Color.secondary.opacity(major ? 0.5 : 0.28))
                    .frame(width: 1, height: major ? 6 : 4)
                if index < count - 1 {
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, inset)
        .frame(width: width)
    }

    private func value(at x: CGFloat, width: CGFloat) -> Double {
        let usable = max(width - thumbWidth, 1)
        let t = min(max((x - thumbWidth / 2) / usable, 0), 1)
        var next = range.lowerBound + Double(t) * (range.upperBound - range.lowerBound)
        if let step, step > 0 {
            next = (next / step).rounded() * step
        }
        return min(max(next, range.lowerBound), range.upperBound)
    }
}
