import Foundation

struct RotationAPI: Sendable {
    enum APIError: LocalizedError {
        case invalidResponse
        case unauthorized
        case rateLimited
        case server(status: Int)
        case noRotations

        var errorDescription: String? {
            switch self {
            case .invalidResponse: "The map service sent an unexpected response."
            case .unauthorized: "That API key wasn’t accepted. Check it in Settings."
            case .rateLimited: "Too many refreshes. Give the service a moment, then retry."
            case .server(let status): "The map service is unavailable right now (\(status))."
            case .noRotations: "No active map rotations were returned."
            }
        }
    }

    func fetch(apiKey: String) async throws -> RotationSnapshot {
        var components = URLComponents(string: "https://api.apexlegendsstatus.com/maprotation")!
        components.queryItems = [URLQueryItem(name: "version", value: "2")]

        var request = URLRequest(url: components.url!)
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("ApexMapCheck/1.0 iOS", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        switch http.statusCode {
        case 200: break
        case 401, 403: throw APIError.unauthorized
        case 429: throw APIError.rateLimited
        default: throw APIError.server(status: http.statusCode)
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.invalidResponse
        }

        let rotations = root.compactMap { key, value -> GameModeRotation? in
            guard
                let mode = value as? [String: Any],
                let currentJSON = mode["current"] as? [String: Any],
                let current = parseWindow(currentJSON)
            else { return nil }

            let next = (mode["next"] as? [String: Any]).flatMap(parseWindow)
            return GameModeRotation(
                id: key,
                displayName: displayName(for: key),
                current: current,
                next: next
            )
        }
        .sorted { priority(for: $0.id) < priority(for: $1.id) }

        guard !rotations.isEmpty else { throw APIError.noRotations }
        return RotationSnapshot(modes: rotations, fetchedAt: .now)
    }

    private func parseWindow(_ json: [String: Any]) -> MapWindow? {
        guard let map = json["map"] as? String, !map.isEmpty else { return nil }

        return MapWindow(
            map: map,
            start: epochDate(json["start"]),
            end: epochDate(json["end"]),
            durationMinutes: integer(json["DurationInMinutes"]),
            assetURL: (json["asset"] as? String).flatMap(URL.init(string:))
        )
    }

    private func epochDate(_ value: Any?) -> Date? {
        guard let seconds = integer(value), seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    private func integer(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber: number.intValue
        case let string as String: Int(string)
        default: nil
        }
    }

    private func displayName(for key: String) -> String {
        switch key {
        case "battle_royale": "Pubs"
        case "ranked": "Ranked"
        case "arenas": "Arenas"
        case "arenasRanked", "arenas_ranked": "Ranked Arenas"
        case "control": "Control"
        case "ltm": "Mixtape"
        default:
            key.replacingOccurrences(of: "_", with: " ")
                .split(separator: " ")
                .map { $0.capitalized }
                .joined(separator: " ")
        }
    }

    private func priority(for key: String) -> Int {
        switch key {
        case "battle_royale": 0
        case "ranked": 1
        case "ltm": 2
        case "control": 3
        default: 10
        }
    }
}

