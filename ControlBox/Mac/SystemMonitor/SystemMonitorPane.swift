import SwiftUI

struct SystemMonitorPane: View {
    @Bindable var monitor: DualSenseMonitor
    @ObservedObject private var store = PreferencesStore.shared
    @State private var addingLauncherApp = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Show in menu bar", isOn: $store.menuBarEnabled)
                }

                Section {
                    MenuBarIconEditor()
                        .padding(.vertical, 4)
                    HStack {
                        Spacer()
                        Button("Reset to Defaults") {
                            withAnimation(.snappy) { store.resetMenuBarItems() }
                        }
                        .disabled(store.menuBarItems == MenuBarItem.defaultShown)
                    }
                } header: {
                    Text("Menu Bar Icon")
                } footer: {
                    Text("Drag an item between the rows to show or hide it, or within the top row to reorder. With nothing in the top row the menu bar shows a small gauge. macOS hides menu bar items that do not fit, so keep the row short on a notched display.")
                }

                Section {
                    ForEach(store.rowOrder) { row in
                        HStack(spacing: 10) {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.tertiary)
                            Image(systemName: row.systemImage)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            Text(row.title)
                            Spacer()
                            Toggle(row.title, isOn: Binding(
                                get: { !store.isHidden(row) },
                                set: { store.setHidden(!$0, for: row) }
                            ))
                            .toggleStyle(.switch)
                            .labelsHidden()
                        }
                    }
                    .onMove { indices, newOffset in
                        store.move(fromOffsets: indices, toOffset: newOffset)
                    }
                } header: {
                    Text("Dashboard rows")
                } footer: {
                    Text("Drag to reorder.")
                }

                Section {
                    HistoryPreview()
                        .padding(.vertical, 4)
                    HistorySettingsControls()
                    HStack {
                        Spacer()
                        Button("Reset to Defaults") {
                            store.resetHistory()
                        }
                        .disabled(store.historyIsDefault)
                    }
                } header: {
                    Text("History")
                } footer: {
                    Text("Hover the graph at the top of a detail submenu to open its history. The time range is also the 5m / 1h / 24h control in that submenu, and your last pick is kept. History is kept in memory for up to 24 hours and starts over when Control Box quits.")
                }

                Section {
                    QuickLauncherEditor()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    HStack {
                        Button("Add App…") {
                            addingLauncherApp = true
                        }
                        .disabled(!store.canAddLauncherApp)
                        Spacer()
                        Button("Reset to Defaults") {
                            store.resetLauncherApps()
                        }
                        .disabled(store.launcherApps == PreferencesStore.defaultLauncherApps)
                    }
                } header: {
                    Text("Quick launch")
                } footer: {
                    Text("The row at the bottom of the menu, up to \(PreferencesStore.maxLauncherApps) apps. Drag a tile to reorder. Hover a tile to remove it.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("System Monitor")
            .sheet(isPresented: $addingLauncherApp) {
                AddAppSheet(
                    monitor: monitor,
                    excludedBundleIDs: Set(store.launcherApps),
                    onPick: { bundleID, _ in
                        store.addLauncherApp(bundleID)
                    }
                )
            }
        }
    }
}
