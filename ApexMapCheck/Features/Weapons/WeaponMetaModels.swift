import Foundation

nonisolated enum WeaponClass: String, Codable, CaseIterable, Identifiable, Sendable {
    case assaultRifle
    case submachineGun
    case lightMachineGun
    case marksman
    case sniper
    case shotgun
    case pistol

    var id: String { rawValue }

    var title: String {
        switch self {
        case .assaultRifle: "AR"
        case .submachineGun: "SMG"
        case .lightMachineGun: "LMG"
        case .marksman: "Marksman"
        case .sniper: "Sniper"
        case .shotgun: "Shotgun"
        case .pistol: "Pistol"
        }
    }

    init?(providerValue: String) {
        switch providerValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "ar": self = .assaultRifle
        case "smg": self = .submachineGun
        case "lmg": self = .lightMachineGun
        case "marksman": self = .marksman
        case "sniper": self = .sniper
        case "shotgun": self = .shotgun
        case "pistol": self = .pistol
        default: return nil
        }
    }
}

nonisolated enum WeaponTargetHealth: Int, CaseIterable, Identifiable, Sendable {
    case white = 150
    case blue = 175
    case purple = 200
    case red = 225

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .white: "White"
        case .blue: "Blue"
        case .purple: "Purple"
        case .red: "Red"
        }
    }
}

nonisolated struct WeaponStat: Codable, Identifiable, Sendable {
    var id: String { name }

    let name: String
    let weaponClass: WeaponClass
    let headDamage: Double
    let bodyDamage: Double
    let legDamage: Double
    let roundsPerMinute: Double
    let damagePerSecond: Double
    let baseMagazine: Int?
    let usesPeakValues: Bool

    func bodyShots(toEliminate targetHealth: Int) -> Int {
        Int(ceil(Double(targetHealth) / bodyDamage))
    }

    func idealBodyTTK(targetHealth: Int) -> Double {
        let shots = bodyShots(toEliminate: targetHealth)
        return Double(max(0, shots - 1)) * 60 / roundsPerMinute
    }

    func fitsInBaseMagazine(targetHealth: Int) -> Bool {
        guard let baseMagazine else { return true }
        return bodyShots(toEliminate: targetHealth) <= baseMagazine
    }

    func expectedDamage(for mix: WeaponHitMix) -> Double? {
        guard mix.total > 0 else { return nil }
        let weightedDamage = headDamage * Double(mix.head)
            + bodyDamage * Double(mix.body)
            + legDamage * Double(mix.legs)
        return weightedDamage / Double(mix.total)
    }

    func expectedShots(toEliminate targetHealth: Int, mix: WeaponHitMix) -> Int? {
        guard let damage = expectedDamage(for: mix), damage > 0 else { return nil }
        return Int(ceil(Double(targetHealth) / damage))
    }

    func expectedTTK(targetHealth: Int, mix: WeaponHitMix) -> Double? {
        guard let shots = expectedShots(toEliminate: targetHealth, mix: mix) else {
            return nil
        }
        return Double(max(0, shots - 1)) * 60 / roundsPerMinute
    }

    func expectedKillFitsInBaseMagazine(targetHealth: Int, mix: WeaponHitMix) -> Bool {
        guard let baseMagazine,
              let shots = expectedShots(toEliminate: targetHealth, mix: mix) else {
            return true
        }
        return shots <= baseMagazine
    }
}

nonisolated struct WeaponHitMix: Equatable, Sendable {
    var head: Int
    var body: Int
    var legs: Int

    var total: Int { head + body + legs }

    static let bodyOnly = WeaponHitMix(head: 0, body: 10, legs: 0)
}

nonisolated struct WeaponMetaSnapshot: Codable, Sendable {
    let weapons: [WeaponStat]
    let sourceRevision: Int
    let fetchedAt: Date
}

nonisolated struct WeaponMetaFetchResult: Sendable {
    let snapshot: WeaponMetaSnapshot
    let refreshWarning: String?
}
