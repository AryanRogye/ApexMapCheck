import Combine
import Foundation

nonisolated enum LegendRank: String, CaseIterable, Identifiable, Sendable {
    case any
    case unranked
    case bronze
    case silver
    case gold
    case platinum
    case diamond
    case masterPredator

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: "All"
        case .unranked: "Rookie"
        case .bronze: "Bronze"
        case .silver: "Silver"
        case .gold: "Gold"
        case .platinum: "Platinum"
        case .diamond: "Diamond"
        case .masterPredator: "Master/Pred"
        }
    }

    var pathComponent: String? {
        switch self {
        case .any: nil
        case .unranked: "Unranked"
        case .bronze: "Bronze"
        case .silver: "Silver"
        case .gold: "Gold"
        case .platinum: "Platinum"
        case .diamond: "Diamond"
        case .masterPredator: "Masterpred"
        }
    }
}

nonisolated struct LegendPickRate: Codable, Identifiable, Sendable {
    var id: String { name }
    let name: String
    let pickRate: Double
    let colorHex: String
}

nonisolated struct LegendPickRateSnapshot: Codable, Sendable {
    let legends: [LegendPickRate]
    let sampleDescription: String?
    let fetchedAt: Date
}

actor LegendPickRateService {
    private static let baseURL = URL(
        string: "https://apexlegendsstatus.com/game-stats/legends-pick-rates"
    )!
    private static let cacheLifetime: TimeInterval = 6 * 60 * 60

    func fetch(
        rank: LegendRank,
        force: Bool = false,
        now: Date = .now
    ) async throws -> LegendPickRateSnapshot {
        if !force, let cached = loadCached(rank: rank),
           now.timeIntervalSince(cached.fetchedAt) < Self.cacheLifetime {
            return cached
        }

        let url = rank.pathComponent.map { Self.baseURL.appending(path: $0) } ?? Self.baseURL
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadRevalidatingCacheData
        request.setValue("ApexMapCheck/1.0 iOS", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  http.url?.scheme == "https",
                  http.url?.host?.lowercased() == "apexlegendsstatus.com",
                  data.count <= 2_000_000,
                  let html = String(data: data, encoding: .utf8) else {
                throw LegendPickRateError.invalidResponse
            }

            let snapshot = try Self.parse(html: html, fetchedAt: now)
            save(snapshot, rank: rank)
            return snapshot
        } catch {
            if let cached = loadCached(rank: rank) {
                return cached
            }
            throw error
        }
    }

    private static func parse(html: String, fetchedAt: Date) throws -> LegendPickRateSnapshot {
        let pattern = #"\{name:\s*'([^']+)',\s*y:\s*([0-9.]+),\s*color:\s*'(#[0-9A-Fa-f]{6})'\}"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(html.startIndex..., in: html)

        let legends = regex.matches(in: html, range: range).compactMap { match -> LegendPickRate? in
            guard match.numberOfRanges == 4,
                  let nameRange = Range(match.range(at: 1), in: html),
                  let rateRange = Range(match.range(at: 2), in: html),
                  let colorRange = Range(match.range(at: 3), in: html),
                  let rate = Double(html[rateRange]),
                  (0...100).contains(rate) else { return nil }

            return LegendPickRate(
                name: String(html[nameRange]),
                pickRate: rate,
                colorHex: String(html[colorRange])
            )
        }
        .reduce(into: [String: LegendPickRate]()) { result, legend in
            result[legend.name] = legend
        }
        .values
        .sorted { $0.pickRate > $1.pickRate }

        let total = legends.reduce(0) { $0 + $1.pickRate }
        guard legends.count >= 20, (95...105).contains(total) else {
            throw LegendPickRateError.invalidData
        }

        let samplePattern = #"based on\s+([^<]+?)\s+players in our API database"#
        let sampleRegex = try NSRegularExpression(pattern: samplePattern, options: .caseInsensitive)
        let sample = sampleRegex.firstMatch(in: html, range: range).flatMap {
            Range($0.range(at: 1), in: html).map { String(html[$0]) }
        }

        return LegendPickRateSnapshot(
            legends: legends,
            sampleDescription: sample,
            fetchedAt: fetchedAt
        )
    }

    private func loadCached(rank: LegendRank) -> LegendPickRateSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey(rank)) else { return nil }
        return try? JSONDecoder().decode(LegendPickRateSnapshot.self, from: data)
    }

    private func save(_ snapshot: LegendPickRateSnapshot, rank: LegendRank) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey(rank))
    }

    private func cacheKey(_ rank: LegendRank) -> String {
        "legend-pick-rates.\(rank.rawValue).v1"
    }
}

nonisolated enum LegendPickRateError: LocalizedError {
    case invalidResponse
    case invalidData

    var errorDescription: String? {
        "Pick rates are temporarily unavailable."
    }
}

@MainActor
final class LegendPickRatesViewModel: ObservableObject {
    @Published var selectedRank: LegendRank = .any
    @Published private(set) var snapshot: LegendPickRateSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let service = LegendPickRateService()

    func load(force: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            snapshot = try await service.fetch(rank: selectedRank, force: force)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Pick rates are temporarily unavailable."
        }
    }

    func select(_ rank: LegendRank) async {
        guard selectedRank != rank else { return }
        selectedRank = rank
        await load()
    }
}
