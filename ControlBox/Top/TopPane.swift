import SwiftUI

struct TopPane: View {
    @ObservedObject private var store = PreferencesStore.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Show in menu bar", isOn: $store.menuBarEnabled)
                } footer: {
                    footerBullets(
                        "Separate extra with live network speed. The Control Box icon stays.",
                        "Click for CPU, GPU, memory, disk, sensors, and battery.",
                        "Hide from Menu Bar turns this extra off; it does not quit Control Box."
                    )
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
                    footerBullets(
                        "Drag to reorder.",
                        "Off hides the row from the extra."
                    )
                }
            }
            .formStyle(.grouped)
            .navigationTitle("System Monitor")
        }
    }
}
