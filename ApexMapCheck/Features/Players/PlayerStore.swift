import Foundation

actor PlayerStore {
    private enum Key {
        static let favorites = "players.favorites.v1"
        static let lastRequest = "players.last-request.v1"
    }

    static let cacheLifetime: TimeInterval = 5 * 60
    static let requestSpacing: TimeInterval = 10
    static let playerRefreshSpacing: TimeInterval = 60

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func favorites() -> [PlayerSnapshot] {
        guard
            let data = defaults.data(forKey: Key.favorites),
            let snapshots = try? decoder.decode([PlayerSnapshot].self, from: data)
        else { return [] }
        return snapshots.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func saveFavorite(_ snapshot: PlayerSnapshot) -> [PlayerSnapshot] {
        var values = favorites().filter { $0.id != snapshot.id }
        values.append(snapshot)
        persist(values)
        return favorites()
    }

    func removeFavorite(id: String) -> [PlayerSnapshot] {
        let values = favorites().filter { $0.id != id }
        persist(values)
        return favorites()
    }

    func cached(name: String, platform: PlayerPlatform, now: Date = .now) -> PlayerSnapshot? {
        favorites().first {
            $0.platform == platform
                && $0.name.caseInsensitiveCompare(name) == .orderedSame
                && now.timeIntervalSince($0.fetchedAt) < Self.cacheLifetime
        }
    }

    func lastRequestDate() -> Date? {
        defaults.object(forKey: Key.lastRequest) as? Date
    }

    func recordRequest(at date: Date = .now) {
        defaults.set(date, forKey: Key.lastRequest)
    }

    private func persist(_ values: [PlayerSnapshot]) {
        guard let data = try? encoder.encode(values) else { return }
        defaults.set(data, forKey: Key.favorites)
    }
}
