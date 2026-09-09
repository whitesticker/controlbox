import SwiftUI

struct CaffeinatePane: View {
    @Bindable var catalog: CaffeinateCatalog
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Show in menu bar", isOn: $settings.caffeinateMenuBarEnabled)
                } footer: {
                    footerBullets(
                        "Separate extra. The Control Box icon stays.",
                        "Click for how long to keep this Mac awake.",
                        "Hide from Menu Bar turns this extra off; it does not quit Control Box."
                    )
                }

                Section {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        LabeledContent("Status") {
                            Text(catalog.statusText)
                                .monospacedDigit()
                                .foregroundStyle(catalog.isActive ? Palette.good : .secondary)
                        }
                    }
                    if catalog.isActive {
                        Button("Turn Off") {
                            catalog.stop()
                        }
                    }
                } footer: {
                    footer
                }

                Section {
                    ForEach(CaffeinateDuration.allCases) { duration in
                        Button {
                            catalog.start(duration)
                        } label: {
                            HStack {
                                Text(duration.title)
                                Spacer()
                                if catalog.isActive, catalog.duration == duration {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Palette.good)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Keep awake for")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Caffeinate")
        }
    }

    private var footer: Text {
        footerBullets(
            "Stops idle sleep and keeps the display on.",
            "Closing the lid can still sleep a MacBook.",
            "Off when Control Box quits."
        )
    }
}
