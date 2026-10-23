import SwiftUI

/// Colors for the System Monitor menu extra. Views should use these names
/// instead of literal `.blue` / `.green` so the palette stays in one place.
enum DashColors {
    static let accent = Color.accentColor

    static let statusGood: Color = .green
    static let statusWarning: Color = .yellow
    static let statusCritical: Color = .red

    /// In/out pairs: blue for in (download, read), red for out (upload, write).
    static let download: Color = .blue
    static let upload: Color = .red
    static let cpuLine: Color = .blue
    static let gpuLine: Color = .purple
    static let diskRead: Color = .blue
    static let diskWrite: Color = .red

    static let cardBackground: Color = Color.primary.opacity(0.05)
}
