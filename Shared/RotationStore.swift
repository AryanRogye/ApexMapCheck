import Foundation

struct RotationStore: Sendable {
    static let appGroupID = "group.com.aryanrogye.ApexMapCheck"

    private enum Key {
        static let snapshot = "rotation.snapshot.v1"
        static let apiKey = "rotation.api-key.v1"
        static let lastAttempt = "rotation.last-attempt.v1"
        static let lastFailure = "rotation.last-failure.v1"
    }

    private var defaults: UserDefaults {
        UserDefaults(suiteName: Self.appGroupID) ?? .standard
    }

    func loadSnapshot() -> RotationSnapshot? {
        guard let data = defaults.data(forKey: Key.snapshot) else { return nil }
        return try? JSONDecoder().decode(RotationSnapshot.self, from: data)
    }

    func save(_ snapshot: RotationSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Key.snapshot)
    }

    func loadAPIKey() -> String? {
        defaults.string(forKey: Key.apiKey)
    }

    func saveAPIKey(_ apiKey: String) {
        if defaults.string(forKey: Key.apiKey) != apiKey {
            defaults.removeObject(forKey: Key.lastAttempt)
            defaults.removeObject(forKey: Key.lastFailure)
        }
        defaults.set(apiKey, forKey: Key.apiKey)
    }

    func removeAPIKey() {
        defaults.removeObject(forKey: Key.apiKey)
    }

    func prepareForAccountVerification() {
        defaults.removeObject(forKey: Key.lastAttempt)
        defaults.removeObject(forKey: Key.lastFailure)
    }

    func loadSmart(apiKey: String? = nil, force: Bool = false, now: Date = .now) async throws -> RotationSnapshot {
        let cached = loadSnapshot()
        let effectiveKey = apiKey ?? loadAPIKey()
        let refreshNeeded = force || needsRefresh(cached, now: now)

        guard refreshNeeded, let effectiveKey, !effectiveKey.isEmpty else {
            if let cached { return cached }
            throw RotationAPI.APIError.unauthorized
        }

        let minimumInterval: TimeInterval = force ? 60 : 5 * 60
        if let lastAttempt = defaults.object(forKey: Key.lastAttempt) as? Date,
           now.timeIntervalSince(lastAttempt) < minimumInterval {
            if let cached { return cached }
            if defaults.string(forKey: Key.lastFailure) == "account-verification-required" {
                throw RotationAPI.APIError.accountVerificationRequired
            }
            throw RotationAPI.APIError.refreshCooldown
        }

        defaults.set(now, forKey: Key.lastAttempt)

        do {
            let fresh = try await RotationAPI().fetch(apiKey: effectiveKey)
            save(fresh)
            defaults.removeObject(forKey: Key.lastFailure)
            return fresh
        } catch {
            if let apiError = error as? RotationAPI.APIError,
               case .accountVerificationRequired = apiError {
                defaults.set("account-verification-required", forKey: Key.lastFailure)
            } else {
                defaults.removeObject(forKey: Key.lastFailure)
            }
            if let cached { return cached }
            throw error
        }
    }

    func suggestedReloadDate(for snapshot: RotationSnapshot?, now: Date = .now) -> Date {
        let minimum = now.addingTimeInterval(5 * 60)
        guard let snapshot else { return now.addingTimeInterval(15 * 60) }

        let boundaryRefresh = snapshot.nextBoundary?.addingTimeInterval(75)
        let ageRefresh = snapshot.fetchedAt.addingTimeInterval(60 * 60)
        let candidate = [boundaryRefresh, ageRefresh].compactMap { $0 }.min() ?? ageRefresh
        return max(minimum, candidate)
    }

    private func needsRefresh(_ snapshot: RotationSnapshot?, now: Date) -> Bool {
        guard let snapshot else { return true }
        if now.timeIntervalSince(snapshot.fetchedAt) >= 60 * 60 { return true }
        if snapshot.modes.contains(where: { ($0.current.end ?? .distantFuture) <= now }) { return true }
        return false
    }
}
