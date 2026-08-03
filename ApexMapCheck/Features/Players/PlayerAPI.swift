import Foundation

struct PlayerAPI: Sendable {
    enum APIError: LocalizedError, Equatable {
        case invalidResponse
        case unauthorized
        case playerNotFound
        case invalidPlatform
        case rateLimited
        case temporarilyUnavailable
        case server(status: Int)

        var errorDescription: String? {
            switch self {
            case .invalidResponse: "Player data came back in an unexpected format."
            case .unauthorized: "That API key wasn’t accepted. Check it in Settings."
            case .playerNotFound: "No player matched that name and platform. Check the spelling and try again."
            case .invalidPlatform: "That platform isn’t supported for this player search."
            case .rateLimited: "The stats service is limiting requests. Your saved players are still available."
            case .temporarilyUnavailable: "Player lookup is temporarily unavailable. Try again in a few minutes."
            case .server(let status): "The player service is unavailable right now (\(status))."
            }
        }
    }

    func fetch(name: String, platform: PlayerPlatform, apiKey: String) async throws -> PlayerSnapshot {
        try await fetch(queryName: "player", queryValue: name, platform: platform, apiKey: apiKey)
    }

    func fetch(uid: String, platform: PlayerPlatform, apiKey: String) async throws -> PlayerSnapshot {
        try await fetch(queryName: "uid", queryValue: uid, platform: platform, apiKey: apiKey)
    }

    private func fetch(
        queryName: String,
        queryValue: String,
        platform: PlayerPlatform,
        apiKey: String
    ) async throws -> PlayerSnapshot {
        var components = URLComponents(string: "https://api.apexlegendsstatus.com/bridge")!
        components.queryItems = [
            URLQueryItem(name: queryName, value: queryValue),
            URLQueryItem(name: "platform", value: platform.rawValue),
            URLQueryItem(name: "version", value: "5"),
            URLQueryItem(name: "merge", value: "1"),
            URLQueryItem(name: "removeMerged", value: "1")
        ]

        guard let url = components.url else { throw APIError.invalidResponse }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("ApexMapCheck/1.0 iOS", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard
            let http = response as? HTTPURLResponse,
            http.url?.scheme == "https",
            http.url?.host?.lowercased() == "api.apexlegendsstatus.com",
            data.count <= 2_000_000
        else {
            throw APIError.invalidResponse
        }

        switch http.statusCode {
        case 200:
            break
        case 400, 405:
            throw APIError.temporarilyUnavailable
        case 401, 403:
            throw APIError.unauthorized
        case 404:
            throw APIError.playerNotFound
        case 410:
            throw APIError.invalidPlatform
        case 429:
            throw APIError.rateLimited
        default:
            throw APIError.server(status: http.statusCode)
        }

        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let global = root["global"] as? [String: Any],
            let uid = string(global["uid"]),
            !uid.isEmpty,
            let name = global["name"] as? String,
            !name.isEmpty
        else {
            throw APIError.invalidResponse
        }

        let responsePlatform = (global["platform"] as? String)
            .flatMap(PlayerPlatform.init(rawValue:)) ?? platform
        let rankJSON = global["rank"] as? [String: Any] ?? [:]
        let rank = PlayerRank(
            name: (rankJSON["rankName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Unranked",
            division: integer(rankJSON["rankDiv"]) ?? 0,
            score: max(0, integer(rankJSON["rankScore"]) ?? 0),
            ladderPosition: positiveInteger(rankJSON["ladderPosPlatform"]),
            imageURL: validatedURL(rankJSON["rankImg"])
        )

        let legends = root["legends"] as? [String: Any]
        let selected = legends?["selected"] as? [String: Any]
        let imageAssets = selected?["ImgAssets"] as? [String: Any]
        let trackers = parseTrackerArray(selected?["data"])
        let totals = parseTotals(root["total"])
        let realtime = root["realtime"] as? [String: Any]
        let isOnline = (integer(realtime?["isOnline"]) ?? 0) == 1
        let activityText = (realtime?["currentStateAsText"] as? String)
            .flatMap { $0.isEmpty ? nil : $0 }

        return PlayerSnapshot(
            uid: uid,
            name: name,
            platform: responsePlatform,
            level: max(0, integer(global["level"]) ?? 0),
            prestige: max(0, integer(global["levelPrestige"]) ?? 0),
            avatarURL: validatedURL(global["avatar"]),
            rank: rank,
            selectedLegend: (selected?["LegendName"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            legendIconURL: validatedURL(imageAssets?["icon"]),
            legendBannerURL: validatedURL(imageAssets?["banner"]),
            trackers: trackers,
            totals: totals,
            activityText: activityText,
            isOnline: isOnline,
            fetchedAt: .now
        )
    }

    private func parseTrackerArray(_ value: Any?) -> [PlayerTracker] {
        guard let values = value as? [[String: Any]] else { return [] }
        return values.compactMap { item in
            guard
                let key = item["key"] as? String,
                let name = item["name"] as? String,
                let value = number(item["value"]),
                value >= 0
            else { return nil }
            return PlayerTracker(key: key, name: name, value: value)
        }
    }

    private func parseTotals(_ value: Any?) -> [PlayerTracker] {
        guard let totals = value as? [String: Any] else { return [] }
        let priority = ["kills", "damage", "wins", "games_played", "kd"]

        return totals.compactMap { key, rawValue -> PlayerTracker? in
            guard
                let item = rawValue as? [String: Any],
                let value = number(item["value"]),
                value >= 0
            else { return nil }
            let name = (item["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? key.replacingOccurrences(of: "_", with: " ").capitalized
            return PlayerTracker(key: key, name: name, value: value)
        }
        .sorted { first, second in
            let firstPriority = priority.firstIndex(of: first.key) ?? priority.count
            let secondPriority = priority.firstIndex(of: second.key) ?? priority.count
            if firstPriority == secondPriority { return first.name < second.name }
            return firstPriority < secondPriority
        }
    }

    private func validatedURL(_ value: Any?) -> URL? {
        guard
            let string = value as? String,
            let url = URL(string: string),
            url.scheme == "https"
        else { return nil }
        return url
    }

    private func integer(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber: number.intValue
        case let string as String: Int(string)
        default: nil
        }
    }

    private func positiveInteger(_ value: Any?) -> Int? {
        guard let value = integer(value), value > 0 else { return nil }
        return value
    }

    private func number(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: number.doubleValue
        case let string as String: Double(string)
        default: nil
        }
    }

    private func string(_ value: Any?) -> String? {
        switch value {
        case let string as String: string
        case let number as NSNumber: number.stringValue
        default: nil
        }
    }
}
