import Foundation
import Observation
import WidgetKit

@MainActor
@Observable
final class RotationViewModel {
    private(set) var apiKey = ""
    private(set) var rotations: [GameModeRotation] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var errorActionURL: URL?
    private(set) var lastUpdated: Date?
    private(set) var usesBundledAPIKey = false
    private(set) var latestPatchNote: PatchNote?
    private(set) var isLoadingPatchNotes = false

    private let store = RotationStore()
    private let keychain = KeychainStore()
    private let patchNotesService = PatchNotesService()
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
        async let patchNotes: Void = loadPatchNotes()
        if hasAPIKey {
            await refresh(force: false)
        }
        await patchNotes
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

    func prepareForAccountVerification() {
        store.prepareForAccountVerification()
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

    func loadPatchNotes(force: Bool = false) async {
        guard !isLoadingPatchNotes else { return }
        isLoadingPatchNotes = true
        defer { isLoadingPatchNotes = false }
        latestPatchNote = try? await patchNotesService.latest(force: force)
    }
}
