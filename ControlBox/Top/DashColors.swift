import SwiftUI

/// Colors for the System Monitor menu extra. Views should use these names
/// instead of literal `.blue` / `.green` so the palette stays in one place.
enum DashColors {
    static let accent = Color.accentColor

    static let statusGood: Color = .green
    static let statusWarning: Color = .yellow
    static let statusCritical: Color = .red

    static let download = accent
    static let upload: Color = .orange
    static let cpuLine: Color = .blue
    static let gpuLine: Color = .purple
    static let diskRead: Color = .green
    static let diskWrite: Color = .pink

    static let cardBackground: Color = Color.primary.opacity(0.05)
}
