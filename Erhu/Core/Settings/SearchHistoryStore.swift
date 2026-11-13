import Foundation
import Observation

/// Recent query text stays on this device, independently for each search surface.
@MainActor @Observable
final class SearchHistoryStore {
    static let shared = SearchHistoryStore()
    static let limit = 15
    private static let key = "amp.searchHistory.queries"
    private(set) var searches: [String: [String]]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        searches = (defaults.dictionary(forKey: Self.key) ?? [:]).compactMapValues { $0 as? [String] }
    }

    func entries(_ scope: String) -> [String] { searches[scope] ?? [] }

    func remember(_ query: String, in scope: String) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, entries(scope).first != query else { return }
        var entries = self.entries(scope).filter { Self.keyFor($0) != Self.keyFor(query) }
        entries.insert(query, at: 0)
        searches[scope] = Array(entries.prefix(Self.limit))
        save()
    }

    func remove(_ query: String, in scope: String) {
        searches[scope] = entries(scope).filter { Self.keyFor($0) != Self.keyFor(query) }
        save()
    }

    func clear(_ scope: String) { searches[scope] = nil; save() }
    private func save() { defaults.set(searches, forKey: Self.key) }
    private static func keyFor(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
