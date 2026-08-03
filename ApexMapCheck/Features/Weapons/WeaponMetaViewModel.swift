import Foundation
import Observation

@MainActor
@Observable
final class WeaponMetaViewModel {
    var selectedHealth: WeaponTargetHealth = .purple
    var selectedClass: WeaponClass?
    private(set) var snapshot: WeaponMetaSnapshot?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var refreshWarning: String?

    private let service = WeaponMetaService()

    var rankedWeapons: [WeaponStat] {
        guard let snapshot else { return [] }
        return snapshot.weapons
            .filter { selectedClass == nil || $0.weaponClass == selectedClass }
            .sorted { left, right in
                let leftTTK = left.idealBodyTTK(targetHealth: selectedHealth.rawValue)
                let rightTTK = right.idealBodyTTK(targetHealth: selectedHealth.rawValue)
                if abs(leftTTK - rightTTK) > 0.000_1 {
                    return leftTTK < rightTTK
                }
                return left.damagePerSecond > right.damagePerSecond
            }
    }

    func load(force: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        if force { refreshWarning = nil }
        defer { isLoading = false }

        do {
            let result = try await service.fetch(force: force)
            snapshot = result.snapshot
            refreshWarning = result.refreshWarning
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? "Weapon stats are temporarily unavailable."
            if snapshot == nil {
                errorMessage = message
            } else {
                refreshWarning = message
            }
        }
    }
}
