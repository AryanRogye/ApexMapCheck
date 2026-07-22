import Foundation

struct RotationSnapshot: Sendable {
    let modes: [GameModeRotation]
    let fetchedAt: Date
}

struct GameModeRotation: Identifiable, Sendable {
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
}

struct MapWindow: Sendable {
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
