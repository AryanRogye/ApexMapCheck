import Combine
import Foundation

@MainActor
final class RotationViewModel: ObservableObject {
    @Published private(set) var apiKey = ""
    @Published private(set) var rotations: [GameModeRotation] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdated: Date?

    private let api = RotationAPI()
    private let keychain = KeychainStore()
    private var didLoad = false

    var hasAPIKey: Bool { !apiKey.isEmpty }

    init() {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--demo-rotations") {
            apiKey = "debug-demo-key"
            rotations = Self.demoRotations
            lastUpdated = .now
            didLoad = true
            return
        }
#endif
        apiKey = keychain.read() ?? ""
    }

    func loadIfNeeded() async {
        guard !didLoad else { return }
        didLoad = true
        guard hasAPIKey else { return }
        await refresh()
    }

    func saveAPIKey(_ key: String) async {
        let cleanKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else { return }

        do {
            try keychain.save(cleanKey)
            apiKey = cleanKey
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeAPIKey() {
        keychain.remove()
        apiKey = ""
        rotations = []
        errorMessage = nil
        lastUpdated = nil
    }

    func refresh() async {
        guard hasAPIKey, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let snapshot = try await api.fetch(apiKey: apiKey)
            rotations = snapshot.modes
            lastUpdated = snapshot.fetchedAt
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn’t refresh map rotations."
        }
    }

#if DEBUG
    private static var demoRotations: [GameModeRotation] {
        let now = Date.now
        return [
            GameModeRotation(
                id: "battle_royale",
                displayName: "Pubs",
                current: MapWindow(
                    map: "Olympus",
                    start: now.addingTimeInterval(-1_800),
                    end: now.addingTimeInterval(2_760),
                    durationMinutes: 90,
                    assetURL: nil
                ),
                next: MapWindow(
                    map: "Storm Point",
                    start: now.addingTimeInterval(2_760),
                    end: now.addingTimeInterval(8_160),
                    durationMinutes: 90,
                    assetURL: nil
                )
            ),
            GameModeRotation(
                id: "ranked",
                displayName: "Ranked",
                current: MapWindow(
                    map: "World’s Edge",
                    start: now.addingTimeInterval(-4_800),
                    end: now.addingTimeInterval(5_460),
                    durationMinutes: 270,
                    assetURL: nil
                ),
                next: MapWindow(
                    map: "E-District",
                    start: now.addingTimeInterval(5_460),
                    end: now.addingTimeInterval(21_660),
                    durationMinutes: 270,
                    assetURL: nil
                )
            )
        ]
    }
#endif
}
