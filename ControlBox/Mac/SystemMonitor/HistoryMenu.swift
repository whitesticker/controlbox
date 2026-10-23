import AppKit
import Combine
import SwiftUI

/// Refreshes one history panel from `HistoryStore` once a second, only
/// while it is on screen (its detail submenu is open, or the pane preview shows).
final class HistoryFeed: ObservableObject {
    @Published var metric: HistoryMetric {
        didSet { if metric != oldValue { refresh() } }
    }
    @Published private(set) var history: MetricHistory
    private var timer: Timer?
    private var preferencesCancellable: AnyCancellable?

    init(metric: HistoryMetric) {
        self.metric = metric
        history = MetricHistory(metric: metric, range: PreferencesStore.shared.historyRange, series: [])
    }

    func start() {
        refresh()
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        preferencesCancellable = PreferencesStore.shared.$historyRange
            .dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.refresh() } }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        preferencesCancellable = nil
    }

    func refresh() {
        history = HistoryStore.shared.history(metric, range: PreferencesStore.shared.historyRange)
    }
}

/// Which metric a submenu's one history panel charts, picked by hovering a
/// section of its stats panel (Sensors: power, fans, or one temperature
/// group). Separate from `HistoryFeed` so the stats panel re-renders only
/// when the pick changes, not on every history refresh.
final class HistoryFocus: ObservableObject {
    @Published private(set) var metric: HistoryMetric
    let feed: HistoryFeed

    init(_ metric: HistoryMetric) {
        self.metric = metric
        feed = HistoryFeed(metric: metric)
    }

    func select(_ metric: HistoryMetric) {
        guard metric != self.metric else { return }
        self.metric = metric
        feed.metric = metric
    }
}

struct HistoryPanelHost: View {
    @ObservedObject var feed: HistoryFeed
    @ObservedObject private var preferences = PreferencesStore.shared

    var body: some View {
        HistoryPanel(
            history: feed.history,
            settings: preferences.historySettings,
            design: preferences.historyDesign
        ) { range in
            preferences.historyRange = range
        }
        .padding(.horizontal, 5)
    }
}

/// The history panels beside one detail submenu, stacked. A panel after the
/// first hides while it has no data (fans on a fanless Mac).
struct HistoryColumn: View {
    let feeds: [HistoryFeed]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(feeds.indices, id: \.self) { index in
                HistoryColumnPanel(feed: feeds[index], hidesWhenEmpty: index > 0)
            }
        }
    }
}

private struct HistoryColumnPanel: View {
    @ObservedObject var feed: HistoryFeed
    let hidesWhenEmpty: Bool

    var body: some View {
        if !(hidesWhenEmpty && feed.history.series.isEmpty) {
            HistoryPanelHost(feed: feed)
        }
    }
}
