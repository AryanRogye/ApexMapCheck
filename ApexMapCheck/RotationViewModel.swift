import Combine
import Foundation
import WidgetKit

@MainActor
final class RotationViewModel: ObservableObject {
    @Published private(set) var apiKey = ""
    @Published private(set) var rotations: [GameModeRotation] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var errorActionURL: URL?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var usesBundledAPIKey = false

    private let store = RotationStore()
    private let keychain = KeychainStore()
    private var didLoad = false

    var hasAPIKey: Bool { !apiKey.isEmpty }

    init() {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--demo-rotations") {
            let preview = RotationSnapshot.preview
            apiKey = "debug-demo-key"
            rotations = preview.modes
            lastUpdated = .now
            store.save(preview)
            didLoad = true
            return
        }
#endif
        if let bundledKey = Self.bundledAPIKey() {
            apiKey = bundledKey
            usesBundledAPIKey = true
        } else {
            apiKey = keychain.read() ?? ""
        }

        if !apiKey.isEmpty {
            store.saveAPIKey(apiKey)
        }

        if let cached = store.loadSnapshot()?.projected(at: .now) {
            rotations = cached.modes
            lastUpdated = cached.fetchedAt
        }
    }

    func loadIfNeeded() async {
        guard !didLoad else { return }
        didLoad = true
        guard hasAPIKey else { return }
        await refresh(force: false)
    }

    func saveAPIKey(_ key: String) async {
        let cleanKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else { return }

        do {
            try keychain.save(cleanKey)
            apiKey = cleanKey
            store.saveAPIKey(cleanKey)
            await refresh(force: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeAPIKey() {
        guard !usesBundledAPIKey else { return }
        keychain.remove()
        store.removeAPIKey()
        apiKey = ""
        rotations = []
        errorMessage = nil
        errorActionURL = nil
        lastUpdated = nil
    }

    private static func bundledAPIKey() -> String? {
        guard
            let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let values = plist as? [String: Any],
            let key = values["APEX_API_KEY"] as? String
        else { return nil }

        let cleanKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty, cleanKey != "YOUR_API_KEY" else { return nil }
        return cleanKey
    }

    func refresh(force: Bool = true) async {
        guard hasAPIKey, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let previousFetch = lastUpdated
            let snapshot = try await store.loadSmart(apiKey: apiKey, force: force)
            rotations = snapshot.projected(at: .now).modes
            lastUpdated = snapshot.fetchedAt
            errorActionURL = nil
            if previousFetch != snapshot.fetchedAt {
                WidgetCenter.shared.reloadAllTimelines()
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn’t refresh map rotations."
            if let apiError = error as? RotationAPI.APIError,
               case .accountVerificationRequired = apiError {
                errorActionURL = URL(string: "https://portal.apexlegendsapi.com/discord-auth")
            } else if let apiError = error as? RotationAPI.APIError,
                      case .refreshCooldown = apiError {
                // Preserve an existing verification action during the local cooldown.
            } else {
                errorActionURL = nil
            }
        }
    }

}
