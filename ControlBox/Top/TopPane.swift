import SwiftUI

struct TopPane: View {
    @ObservedObject private var store = PreferencesStore.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Show in menu bar", isOn: $store.menuBarEnabled)
                } footer: {
                    Text("Adds a separate menu bar icon with live network speed. Click it for CPU, GPU, memory, disk, sensors, and battery. The Control Box icon stays as it is.")
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
                    Text("Drag to reorder. Turn a row off to hide it from the menu bar dashboard.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("System Monitor")
        }
    }
}
