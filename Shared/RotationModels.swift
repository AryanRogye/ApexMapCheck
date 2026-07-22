import Foundation

struct RotationSnapshot: Codable, Sendable {
    let modes: [GameModeRotation]
    let fetchedAt: Date

    func projected(at date: Date) -> RotationSnapshot {
        RotationSnapshot(modes: modes.map { $0.projected(at: date) }, fetchedAt: fetchedAt)
    }

    func mode(id: String, at date: Date = .now) -> GameModeRotation? {
        projected(at: date).modes.first { $0.id == id }
    }

    var nextBoundary: Date? {
        modes.compactMap(\.current.end).filter { $0 > .now }.min()
    }

    static var preview: RotationSnapshot {
        let now = Date.now
        return RotationSnapshot(
            modes: [
                GameModeRotation(
                    id: "battle_royale",
                    displayName: "Pubs",
                    current: MapWindow(map: "Olympus", start: now.addingTimeInterval(-1_800), end: now.addingTimeInterval(2_760), durationMinutes: 90, assetURL: nil),
                    next: MapWindow(map: "Storm Point", start: now.addingTimeInterval(2_760), end: now.addingTimeInterval(8_160), durationMinutes: 90, assetURL: nil)
                ),
                GameModeRotation(
                    id: "ranked",
                    displayName: "Ranked",
                    current: MapWindow(map: "World’s Edge", start: now.addingTimeInterval(-4_800), end: now.addingTimeInterval(5_460), durationMinutes: 270, assetURL: nil),
                    next: MapWindow(map: "E-District", start: now.addingTimeInterval(5_460), end: now.addingTimeInterval(21_660), durationMinutes: 270, assetURL: nil)
                )
            ],
            fetchedAt: now
        )
    }
}

struct GameModeRotation: Codable, Identifiable, Sendable {
    let id: String
    let displayName: String
    let current: MapWindow
    let next: MapWindow?

    var symbolName: String {
        switch id {
        case "ranked": "shield.lefthalf.filled"
        case "battle_royale": "person.3.fill"
        case "control": "scope"
        default: "gamecontroller.fill"
        }
    }

    func projected(at date: Date) -> GameModeRotation {
        guard let end = current.end, end <= date, let next else { return self }
        return GameModeRotation(id: id, displayName: displayName, current: next, next: nil)
    }
}

struct MapWindow: Codable, Sendable {
    let map: String
    let start: Date?
    let end: Date?
    let durationMinutes: Int?
    let assetURL: URL?

    func countdown(at date: Date) -> String {
        guard let end else { return "Live now" }
        let total = max(0, Int(end.timeIntervalSince(date)))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%02d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }

    func accessibleTimeRemaining(at date: Date) -> String {
        guard let end else { return "Unknown time" }
        let total = max(0, Int(end.timeIntervalSince(date)))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        if hours > 0 { return "\(hours) hours, \(minutes) minutes" }
        return "\(minutes) minutes"
    }

    var durationLabel: String {
        guard let durationMinutes else { return "" }
        if durationMinutes >= 60 {
            let hours = durationMinutes / 60
            let minutes = durationMinutes % 60
            return minutes == 0 ? "\(hours) hr" : "\(hours) hr \(minutes) min"
        }
        return "\(durationMinutes) min"
    }
}
