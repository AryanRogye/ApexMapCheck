import Combine
import Foundation

@MainActor
final class PlayerViewModel: ObservableObject {
    @Published var query = ""
    @Published var platform: PlayerPlatform = .pc
    @Published private(set) var favorites: [PlayerSnapshot] = []
    @Published private(set) var selectedPlayer: PlayerSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var noticeMessage: String?
    @Published private(set) var nextSearchAt: Date?

    private let api = PlayerAPI()
    private let store = PlayerStore()
    private var apiKey = ""
    private var didLoad = false
    private var usesDemoPlayers = false

    var canSearch: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !apiKey.isEmpty && !isLoading
    }

    func load(apiKey: String) async {
        self.apiKey = apiKey
        guard !didLoad else { return }
        didLoad = true

#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--demo-players") {
            usesDemoPlayers = true
            favorites = [.xboxPreview, .preview]
            selectedPlayer = .preview
            return
        }
#endif

        favorites = await store.favorites()
        selectedPlayer = favorites.first
        if let lastRequest = await store.lastRequestDate() {
            nextSearchAt = lastRequest.addingTimeInterval(PlayerStore.requestSpacing)
        }
    }

    func updateAPIKey(_ apiKey: String) {
        self.apiKey = apiKey
    }

    func search(now: Date = .now) async {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty, !isLoading else { return }
        guard !apiKey.isEmpty else {
            errorMessage = "Add an Apex Legends Status API key in Settings first."
            return
        }

        if let cached = await store.cached(name: cleanQuery, platform: platform, now: now) {
            selectedPlayer = cached
            errorMessage = nil
            noticeMessage = "Opened the saved result without using an API request."
            return
        }

        if let selectedPlayer,
           selectedPlayer.platform == platform,
           selectedPlayer.name.caseInsensitiveCompare(cleanQuery) == .orderedSame,
           now.timeIntervalSince(selectedPlayer.fetchedAt) < PlayerStore.cacheLifetime {
            errorMessage = nil
            noticeMessage = "This result is already fresh, so no API request was used."
            return
        }

        guard canMakeRequest(at: now) else {
            noticeMessage = "Smart refresh is holding this check for a few seconds."
            return
        }

        isLoading = true
        errorMessage = nil
        noticeMessage = nil
        await store.recordRequest(at: now)
        nextSearchAt = now.addingTimeInterval(PlayerStore.requestSpacing)
        defer { isLoading = false }

        do {
            let snapshot = try await api.fetch(name: cleanQuery, platform: platform, apiKey: apiKey)
            selectedPlayer = snapshot
            query = snapshot.name
            if isFavorite(snapshot) {
                favorites = await store.saveFavorite(snapshot)
            }
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    func select(_ snapshot: PlayerSnapshot) {
        selectedPlayer = snapshot
        platform = snapshot.platform
        query = snapshot.name
        errorMessage = nil
        noticeMessage = nil
    }

    func refreshSelected(now: Date = .now) async {
        guard let selectedPlayer, !isLoading else { return }
        let playerReadyAt = selectedPlayer.fetchedAt.addingTimeInterval(PlayerStore.playerRefreshSpacing)
        let requestReadyAt = nextSearchAt ?? .distantPast
        let readyAt = max(playerReadyAt, requestReadyAt)
        guard now >= readyAt else {
            noticeMessage = "This player was checked recently. The saved snapshot is still fresh."
            return
        }

        guard !apiKey.isEmpty else {
            errorMessage = "Add an Apex Legends Status API key in Settings first."
            return
        }

        isLoading = true
        errorMessage = nil
        noticeMessage = nil
        await store.recordRequest(at: now)
        nextSearchAt = now.addingTimeInterval(PlayerStore.requestSpacing)
        defer { isLoading = false }

        do {
            let snapshot = try await api.fetch(
                uid: selectedPlayer.uid,
                platform: selectedPlayer.platform,
                apiKey: apiKey
            )
            self.selectedPlayer = snapshot
            if isFavorite(selectedPlayer) {
                favorites = await store.saveFavorite(snapshot)
            }
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    func toggleFavorite(_ snapshot: PlayerSnapshot) async {
        if usesDemoPlayers {
            if isFavorite(snapshot) {
                favorites.removeAll { $0.id == snapshot.id }
                noticeMessage = "Removed \(snapshot.name) from saved players."
            } else {
                favorites.append(snapshot)
                favorites.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                noticeMessage = "Saved \(snapshot.name) for quick access."
            }
            return
        }

        if isFavorite(snapshot) {
            favorites = await store.removeFavorite(id: snapshot.id)
            noticeMessage = "Removed \(snapshot.name) from saved players."
        } else {
            favorites = await store.saveFavorite(snapshot)
            noticeMessage = "Saved \(snapshot.name) for quick access."
        }
    }

    func removeFavorite(_ snapshot: PlayerSnapshot) async {
        if usesDemoPlayers {
            favorites.removeAll { $0.id == snapshot.id }
            noticeMessage = "Removed \(snapshot.name) from saved players."
            return
        }

        favorites = await store.removeFavorite(id: snapshot.id)
        noticeMessage = "Removed \(snapshot.name) from saved players."
    }

    func isFavorite(_ snapshot: PlayerSnapshot) -> Bool {
        favorites.contains { $0.id == snapshot.id }
    }

    func selectedRefreshDate() -> Date? {
        guard let selectedPlayer else { return nil }
        return max(
            selectedPlayer.fetchedAt.addingTimeInterval(PlayerStore.playerRefreshSpacing),
            nextSearchAt ?? .distantPast
        )
    }

    private func canMakeRequest(at date: Date) -> Bool {
        guard let nextSearchAt else { return true }
        return date >= nextSearchAt
    }

    private func userMessage(for error: Error) -> String {
        if let apiError = error as? PlayerAPI.APIError {
            return apiError.errorDescription ?? "Couldn’t check that player."
        }
        if let urlError = error as? URLError,
           [.notConnectedToInternet, .networkConnectionLost, .timedOut].contains(urlError.code) {
            return "You appear to be offline. Saved player snapshots are still available."
        }
        return "Couldn’t check that player right now."
    }
}
