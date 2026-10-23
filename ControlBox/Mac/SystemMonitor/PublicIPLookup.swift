import Foundation
import Darwin

/// The Mac's public IPv4 as the internet sees it. Looked up only when the
/// user clicks Show in the Network submenu: one GET to `ipv4.icanhazip.com`
/// (the user approved that host), no cookies or cache. The answer is
/// dropped when the primary interface or its local IP changes, since the
/// public address may have changed with it. Main thread only.
final class PublicIPLookup: ObservableObject {
    static let shared = PublicIPLookup()

    enum State: Equatable {
        case idle, loading, found(String), failed
    }

    @Published private(set) var state: State = .idle

    private static let url = URL(string: "https://ipv4.icanhazip.com")!
    private let session = URLSession(configuration: .ephemeral)
    private var networkKey = ""
    private var generation = 0

    private init() {}

    func lookUp() {
        guard state != .loading else { return }
        state = .loading
        generation += 1
        let generation = generation
        let request = URLRequest(url: Self.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 6)
        session.dataTask(with: request) { [weak self] data, response, _ in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            let text = data.flatMap { String(data: $0, encoding: .utf8) }?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let ip = ok && Self.isIPv4(text) ? text : nil
            DispatchQueue.main.async {
                guard let self, self.generation == generation else { return }
                self.state = ip.map(State.found) ?? .failed
            }
        }.resume()
    }

    /// `key` identifies the primary interface and its local address.
    func networkChanged(_ key: String) {
        guard key != networkKey else { return }
        let first = networkKey.isEmpty
        networkKey = key
        guard !first else { return }
        generation += 1
        state = .idle
    }

    private static func isIPv4(_ text: String) -> Bool {
        var address = in_addr()
        return inet_pton(AF_INET, text, &address) == 1
    }
}
