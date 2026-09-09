import AppKit
import ControlBoxCore
import SwiftUI
import UniformTypeIdentifiers

struct AddAppSheet: View {
    @Bindable var monitor: DualSenseMonitor
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(16)
            List {
                if !filteredRecent.isEmpty {
                    Section("Recent") {
                        ForEach(filteredRecent) { app in
                            appRow(bundleID: app.bundleID, name: app.name)
                        }
                    }
                }
                Section("Running") {
                    if filteredRunning.isEmpty {
                        Text("No matching apps.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredRunning, id: \.bundleID) { app in
                            appRow(bundleID: app.bundleID, name: app.name)
                        }
                    }
                }
            }
            .listStyle(.inset)
            Divider()
            HStack {
                Button("Other…") {
                    pickOther()
                }
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(16)
        }
        .frame(minWidth: 420, minHeight: 480)
        .navigationTitle("Add App")
    }

    private var filteredRecent: [RecentFrontmostApp] {
        filter(monitor.recentFrontmostApps, query: query)
    }

    private var filteredRunning: [RecentFrontmostApp] {
        let running = NSWorkspace.shared.runningApplications.compactMap { app -> RecentFrontmostApp? in
            guard app.activationPolicy == .regular,
                  let bundle = app.bundleIdentifier,
                  bundle != MouseAppCatalog.controlBoxBundleID
            else { return nil }
            let name = app.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines)
            return RecentFrontmostApp(bundleID: bundle, name: (name?.isEmpty == false) ? name! : bundle)
        }
        .uniquedByBundle()
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return filter(running, query: query)
    }

    private func filter(_ apps: [RecentFrontmostApp], query: String) -> [RecentFrontmostApp] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return apps }
        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(needle)
                || $0.bundleID.localizedCaseInsensitiveContains(needle)
        }
    }

    private func appRow(bundleID: String, name: String) -> some View {
        Button {
            pick(bundleID: bundleID, name: name)
        } label: {
            HStack(spacing: 10) {
                AppBundleIcon(bundleID: bundleID)
                    .frame(width: 24, height: 24)
                Text(name)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func pick(bundleID: String, name: String) {
        monitor.addMXApp(bundleID: bundleID, name: name)
        dismiss()
    }

    private func pickOther() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Choose an app"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let bundle = Bundle(url: url)
        let identifier = bundle?.bundleIdentifier ?? url.deletingPathExtension().lastPathComponent
        let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        pick(bundleID: identifier, name: name)
    }
}

struct AppBundleIcon: View {
    var bundleID: String

    var body: some View {
        if let image = Self.icon(for: bundleID) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "app")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    static func icon(for bundleID: String) -> NSImage? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return nil
    }
}

private extension Array where Element == RecentFrontmostApp {
    func uniquedByBundle() -> [RecentFrontmostApp] {
        var seen = Set<String>()
        return filter { seen.insert($0.bundleID).inserted }
    }
}
