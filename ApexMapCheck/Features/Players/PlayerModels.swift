import Foundation

enum PlayerPlatform: String, CaseIterable, Codable, Identifiable, Sendable {
    case pc = "PC"
    case xbox = "X1"
    case playStation = "PS4"
    case switchConsole = "SWITCH"

    nonisolated var id: String { rawValue }

    var title: String {
        switch self {
        case .pc: "PC"
        case .xbox: "Xbox"
        case .playStation: "PlayStation"
        case .switchConsole: "Switch"
        }
    }

    var compactTitle: String {
        switch self {
        case .pc: "PC"
        case .xbox: "XBOX"
        case .playStation: "PS"
        case .switchConsole: "SWITCH"
        }
    }

    var symbolName: String {
        switch self {
        case .pc: "desktopcomputer"
        case .xbox: "xbox.logo"
        case .playStation: "playstation.logo"
        case .switchConsole: "gamecontroller.fill"
        }
    }

    static let nameSearchCases: [PlayerPlatform] = [.pc, .xbox, .playStation]
}

struct PlayerRank: Codable, Hashable, Sendable {
    let name: String
    let division: Int
    let score: Int
    let ladderPosition: Int?
    let imageURL: URL?

    var displayName: String {
        guard division > 0, name.caseInsensitiveCompare("Unranked") != .orderedSame else {
            return name
        }
        return "\(name) \(Self.romanNumeral(division))"
    }

    private static func romanNumeral(_ value: Int) -> String {
        switch value {
        case 1: "I"
        case 2: "II"
        case 3: "III"
        case 4: "IV"
        default: String(value)
        }
    }
}

struct PlayerTracker: Codable, Hashable, Identifiable, Sendable {
    let key: String
    let name: String
    let value: Double

    nonisolated var id: String { key }
}

struct PlayerSnapshot: Codable, Hashable, Identifiable, Sendable {
    let uid: String
    let name: String
    let platform: PlayerPlatform
    let level: Int
    let prestige: Int
    let avatarURL: URL?
    let rank: PlayerRank
    let selectedLegend: String?
    let legendIconURL: URL?
    let legendBannerURL: URL?
    let trackers: [PlayerTracker]
    let totals: [PlayerTracker]
    let activityText: String?
    let isOnline: Bool
    let fetchedAt: Date

    nonisolated var id: String { "\(platform.rawValue):\(uid)" }

    var displayLevel: Int {
        level + max(0, prestige) * 500
    }

    var featuredTrackers: [PlayerTracker] {
        let preferredKeys = ["kills", "damage", "wins", "games_played", "kd"]
        let preferred = preferredKeys.compactMap { key in totals.first { $0.key == key } }
        if !preferred.isEmpty {
            return Array(preferred.prefix(3))
        }
        return Array((totals.isEmpty ? trackers : totals).prefix(3))
    }
}

extension PlayerSnapshot {
    static let preview = PlayerSnapshot(
        uid: "1000000001",
        name: "VoidRunner",
        platform: .pc,
        level: 342,
        prestige: 2,
        avatarURL: nil,
        rank: PlayerRank(
            name: "Diamond",
            division: 2,
            score: 12_840,
            ladderPosition: 1842,
            imageURL: nil
        ),
        selectedLegend: "Wraith",
        legendIconURL: nil,
        legendBannerURL: nil,
        trackers: [
            PlayerTracker(key: "kills", name: "BR Kills", value: 8_412),
            PlayerTracker(key: "damage", name: "BR Damage", value: 2_941_205),
            PlayerTracker(key: "wins", name: "BR Wins", value: 436)
        ],
        totals: [
            PlayerTracker(key: "kills", name: "BR Kills", value: 8_412),
            PlayerTracker(key: "damage", name: "BR Damage", value: 2_941_205),
            PlayerTracker(key: "wins", name: "BR Wins", value: 436)
        ],
        activityText: "In Lobby",
        isOnline: true,
        fetchedAt: .now.addingTimeInterval(-82)
    )

    static let xboxPreview = PlayerSnapshot(
        uid: "1000000002",
        name: "ArcStarMom",
        platform: .xbox,
        level: 118,
        prestige: 1,
        avatarURL: nil,
        rank: PlayerRank(
            name: "Platinum",
            division: 1,
            score: 9_672,
            ladderPosition: nil,
            imageURL: nil
        ),
        selectedLegend: "Lifeline",
        legendIconURL: nil,
        legendBannerURL: nil,
        trackers: [
            PlayerTracker(key: "kills", name: "BR Kills", value: 3_091),
            PlayerTracker(key: "revives", name: "Revives", value: 804)
        ],
        totals: [
            PlayerTracker(key: "kills", name: "BR Kills", value: 3_091),
            PlayerTracker(key: "wins", name: "BR Wins", value: 188)
        ],
        activityText: "Offline",
        isOnline: false,
        fetchedAt: .now.addingTimeInterval(-640)
    )
}
