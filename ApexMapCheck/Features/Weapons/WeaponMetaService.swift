import Foundation

actor WeaponMetaService {
    private static let catalogURL = URL(
        string: "https://apexlegends.wiki.gg/api.php?action=parse&page=Weapon&prop=text%7Crevid&format=json&formatversion=2"
    )!
    private static let apiURL = URL(string: "https://apexlegends.wiki.gg/api.php")!
    private static let cacheKey = "weapon-meta.snapshot.v3"
    private static let cacheLifetime: TimeInterval = 6 * 60 * 60
    private static let maximumPayloadSize = 1_000_000

    func fetch(
        force: Bool = false,
        now: Date = .now
    ) async throws -> WeaponMetaFetchResult {
        let cached = loadCached()
        if !force, let cached,
           now.timeIntervalSince(cached.fetchedAt) < Self.cacheLifetime {
            return WeaponMetaFetchResult(snapshot: cached, refreshWarning: nil)
        }

        do {
            let catalogData = try await requestData(from: Self.catalogURL)
            let catalogPayload = try JSONDecoder().decode(WeaponWikiEnvelope.self, from: catalogData)
            let catalog = try Self.parseCatalog(html: catalogPayload.parse.text)
            let detailsURL = try Self.detailsURL(
                pageTitles: Array(Set(catalog.map(\.pageTitle))).sorted()
            )
            let detailsData = try await requestData(from: detailsURL)
            let detailsPayload = try JSONDecoder().decode(WeaponWikiQueryEnvelope.self, from: detailsData)
            let snapshot = try Self.parse(
                catalog: catalog,
                pages: detailsPayload.query.pages,
                catalogRevision: catalogPayload.parse.revision,
                fetchedAt: now
            )
            save(snapshot)
            return WeaponMetaFetchResult(snapshot: snapshot, refreshWarning: nil)
        } catch {
            if let cached {
                return WeaponMetaFetchResult(
                    snapshot: cached,
                    refreshWarning: "Couldn’t refresh weapon stats. Showing the last saved data."
                )
            }
            if error is DecodingError {
                throw WeaponMetaError.invalidResponse
            }
            throw error
        }
    }

    private func requestData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadRevalidatingCacheData
        request.setValue("ApexMapCheck/1.0 iOS", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              http.url?.scheme == "https",
              http.url?.host?.lowercased() == "apexlegends.wiki.gg",
              data.count <= Self.maximumPayloadSize else {
            throw WeaponMetaError.invalidResponse
        }
        return data
    }

    nonisolated private static func detailsURL(pageTitles: [String]) throws -> URL {
        guard (20...50).contains(pageTitles.count),
              var components = URLComponents(url: apiURL, resolvingAgainstBaseURL: false) else {
            throw WeaponMetaError.invalidData
        }

        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "prop", value: "revisions"),
            URLQueryItem(name: "titles", value: pageTitles.joined(separator: "|")),
            URLQueryItem(name: "rvprop", value: "ids|content"),
            URLQueryItem(name: "rvslots", value: "main"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2")
        ]

        guard let url = components.url else {
            throw WeaponMetaError.invalidData
        }
        return url
    }

    nonisolated private static func parseCatalog(html: String) throws -> [WeaponCatalogEntry] {
        guard let table = try captures(
            pattern: #"<table\b[^>]*>([\s\S]*?)</table>"#,
            in: html
        ).first(where: { plainText($0).contains("General Stats") }) else {
            throw WeaponMetaError.invalidData
        }

        let rows = try captures(
            pattern: #"<tr\b[^>]*>([\s\S]*?)</tr>"#,
            in: table
        )
        var entriesByName: [String: WeaponCatalogEntry] = [:]

        for row in rows {
            let cellHTML = try captures(
                pattern: #"<t[dh]\b[^>]*>([\s\S]*?)</t[dh]>"#,
                in: row
            )
            let cells = cellHTML.map(plainText)

            guard cells.count >= 13,
                  let weaponClass = WeaponClass(providerValue: cells[1]),
                  let firstCell = cellHTML.first,
                  let pageTitle = try captures(
                    pattern: #"<a\b[^>]*\btitle=\"([^\"]+)\""#,
                    in: firstCell
                  ).first else { continue }

            let name = cells[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard (2...40).contains(name.count),
                  name.rangeOfCharacter(from: .letters) != nil,
                  (2...60).contains(pageTitle.count) else { continue }

            entriesByName[name] = WeaponCatalogEntry(
                name: name,
                pageTitle: plainText(pageTitle),
                weaponClass: weaponClass
            )
        }

        let entries = entriesByName.values.sorted { $0.name < $1.name }
        guard (20...50).contains(entries.count) else {
            throw WeaponMetaError.invalidData
        }
        return entries
    }

    nonisolated private static func parse(
        catalog: [WeaponCatalogEntry],
        pages: [WeaponWikiPage],
        catalogRevision: Int,
        fetchedAt: Date
    ) throws -> WeaponMetaSnapshot {
        guard catalogRevision > 0 else {
            throw WeaponMetaError.invalidData
        }

        let pagesByTitle = Dictionary(
            uniqueKeysWithValues: pages.map { ($0.title, $0) }
        )
        var weapons: [WeaponStat] = []
        var sourceRevision = catalogRevision

        for entry in catalog {
            guard let page = pagesByTitle[entry.pageTitle],
                  let revision = page.revisions?.first,
                  let content = revision.slots.main.content,
                  let weapon = canonicalWeapon(from: entry, wikitext: content) else {
                continue
            }
            weapons.append(weapon)
            sourceRevision = max(sourceRevision, revision.revision)
        }

        weapons.sort { $0.name < $1.name }
        guard (20...50).contains(weapons.count),
              Set(weapons.map(\.name)).count == weapons.count else {
            throw WeaponMetaError.invalidData
        }

        return WeaponMetaSnapshot(
            weapons: weapons,
            sourceRevision: sourceRevision,
            fetchedAt: fetchedAt
        )
    }

    nonisolated private static func canonicalWeapon(
        from entry: WeaponCatalogEntry,
        wikitext: String
    ) -> WeaponStat? {
        guard let infobox = infobox(in: wikitext),
              let damageField = field("damageBody", in: infobox),
              let headDamageField = field("damageHead", in: infobox),
              let legDamageField = field("damageLegs", in: infobox),
              let rpmField = field("rateOfFire", in: infobox) else {
            return nil
        }

        let isAkimbo = entry.name.localizedCaseInsensitiveContains("Akimbo")
        guard let damageSegment = segments(in: damageField).first,
              let headDamageSegment = segments(in: headDamageField).first,
              let legDamageSegment = segments(in: legDamageField).first,
              !containsRange(damageSegment),
              !containsRange(headDamageSegment),
              !containsRange(legDamageSegment),
              let headDamage = damageValue(in: headDamageSegment),
              let bodyDamage = damageValue(in: damageSegment),
              let legDamage = damageValue(in: legDamageSegment),
              let rpmSegment = selectedSegment(in: rpmField, isAkimbo: isAkimbo),
              let roundsPerMinute = numericValue(in: rpmSegment, preferMaximum: true),
              (1...400).contains(headDamage),
              (1...250).contains(bodyDamage),
              (1...250).contains(legDamage),
              (20...2_000).contains(roundsPerMinute) else {
            return nil
        }

        let calculatedDPS = bodyDamage * roundsPerMinute / 60
        let publishedDPS = field("dps", in: infobox)
            .flatMap { selectedSegment(in: $0, isAkimbo: isAkimbo) }
            .flatMap { numericValue(in: $0, preferMaximum: true) }
        let damagePerSecond = publishedDPS ?? calculatedDPS
        let allowedDifference = max(3, calculatedDPS * 0.08)

        guard (10...500).contains(damagePerSecond),
              abs(damagePerSecond - calculatedDPS) <= allowedDifference else {
            return nil
        }

        let baseMagazine = field("magazineSize", in: infobox)
            .flatMap { selectedSegment(in: $0, isAkimbo: isAkimbo) }
            .flatMap { numericValue(in: $0, preferMaximum: false) }
            .map(Int.init)
            .flatMap { (1...100).contains($0) ? $0 : nil }

        return WeaponStat(
            name: entry.name,
            weaponClass: entry.weaponClass,
            headDamage: headDamage,
            bodyDamage: bodyDamage,
            legDamage: legDamage,
            roundsPerMinute: roundsPerMinute,
            damagePerSecond: damagePerSecond,
            baseMagazine: baseMagazine,
            usesPeakValues: containsRange(rpmSegment)
        )
    }

    nonisolated private static func infobox(in wikitext: String) -> String? {
        guard let start = wikitext.range(
            of: "{{Infobox-Weapon",
            options: [.caseInsensitive]
        ) else { return nil }

        var lines: [Substring] = []
        for line in wikitext[start.lowerBound...].split(
            separator: "\n",
            omittingEmptySubsequences: false
        ) {
            lines.append(line)
            if line.trimmingCharacters(in: .whitespacesAndNewlines) == "}}" {
                return lines.joined(separator: "\n")
            }
        }
        return nil
    }

    nonisolated private static func field(_ name: String, in infobox: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        guard let value = try? captures(
            pattern: #"(?m)^\|[ \t]*"# + escapedName + #"[ \t]*=[ \t]*([^\r\n]*)$"#,
            in: infobox
        ).first else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated private static func segments(in field: String) -> [String] {
        let withoutComments = field.replacingOccurrences(
            of: #"<!--[\s\S]*?-->"#,
            with: "",
            options: .regularExpression
        )
        let separated = withoutComments.replacingOccurrences(
            of: #"<br\s*/?>"#,
            with: "\u{0}",
            options: [.regularExpression, .caseInsensitive]
        )
        return separated
            .components(separatedBy: "\u{0}")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    nonisolated private static func selectedSegment(
        in field: String,
        isAkimbo: Bool
    ) -> String? {
        let values = segments(in: field)
        if isAkimbo {
            return values.first(where: { $0.localizedCaseInsensitiveContains("Akimbo") })
                ?? values.dropFirst().first
        }
        return values.first
    }

    nonisolated private static func damageValue(in segment: String) -> Double? {
        let cleaned = stripMarkup(segment)
        if let values = try? captures(
            pattern: #"([0-9]+(?:\.[0-9]+)?)\s*[×x]\s*([0-9]+(?:\.[0-9]+)?)"#,
            captureGroups: [1, 2],
            in: cleaned
        ).first,
           values.count == 2,
           let pelletDamage = Double(values[0]),
           let pelletCount = Double(values[1]) {
            return pelletDamage * pelletCount
        }
        return firstNumber(in: cleaned)
    }

    nonisolated private static func numericValue(
        in segment: String,
        preferMaximum: Bool
    ) -> Double? {
        if let levelValue = firstCapture(
            pattern: #"\{\{Level0123\|([0-9]+(?:\.[0-9]+)?)"#,
            in: segment
        ).flatMap(Double.init) {
            return levelValue
        }
        if let tooltipValue = firstCapture(
            pattern: #"\{\{Texttip\|([0-9]+(?:\.[0-9]+)?)"#,
            in: segment
        ).flatMap(Double.init) {
            return tooltipValue
        }

        let cleaned = stripMarkup(segment)
        let values = allNumbers(in: cleaned)
        guard !values.isEmpty else { return nil }
        return preferMaximum && containsRange(cleaned) ? values.max() : values.first
    }

    nonisolated private static func containsRange(_ text: String) -> Bool {
        let cleaned = stripMarkup(text)
        return cleaned.range(
            of: #"[0-9]+(?:\.[0-9]+)?\s*(?:-|–|~)\s*[0-9]+"#,
            options: .regularExpression
        ) != nil
    }

    nonisolated private static func stripMarkup(_ text: String) -> String {
        text
            .replacingOccurrences(
                of: #"<!--[\s\S]*?-->"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\[\[[\s\S]*?\]\]"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\{\{[\s\S]*?\}\}"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"<[^>]+>"#,
                with: " ",
                options: .regularExpression
            )
    }

    nonisolated private static func firstCapture(pattern: String, in text: String) -> String? {
        guard let values = try? captures(pattern: pattern, in: text) else { return nil }
        return values.first
    }

    nonisolated private static func allNumbers(in text: String) -> [Double] {
        guard let regex = try? NSRegularExpression(pattern: #"[0-9]+(?:\.[0-9]+)?"#) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let valueRange = Range(match.range, in: text) else { return nil }
            return Double(text[valueRange])
        }
    }

    private func loadCached() -> WeaponMetaSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey) else { return nil }
        return try? JSONDecoder().decode(WeaponMetaSnapshot.self, from: data)
    }

    private func save(_ snapshot: WeaponMetaSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: Self.cacheKey)
    }

    nonisolated private static func captures(
        pattern: String,
        in text: String
    ) throws -> [String] {
        let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let captureRange = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[captureRange])
        }
    }

    nonisolated private static func captures(
        pattern: String,
        captureGroups: [Int],
        in text: String
    ) throws -> [[String]] {
        let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            let values = captureGroups.compactMap { group -> String? in
                guard group < match.numberOfRanges,
                      let captureRange = Range(match.range(at: group), in: text) else { return nil }
                return String(text[captureRange])
            }
            return values.count == captureGroups.count ? values : nil
        }
    }

    nonisolated private static func plainText(_ html: String) -> String {
        let withoutTags = html.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: " ",
            options: .regularExpression
        )
        let decoded = [
            "&amp;": "&",
            "&quot;": "\"",
            "&#39;": "'",
            "&apos;": "'",
            "&nbsp;": " ",
            "&#160;": " ",
            "&times;": "×"
        ].reduce(withoutTags) { text, replacement in
            text.replacingOccurrences(of: replacement.key, with: replacement.value)
        }
        return decoded
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    nonisolated private static func firstNumber(in text: String) -> Double? {
        guard let range = text.range(of: #"[0-9]+(?:\.[0-9]+)?"#, options: .regularExpression) else {
            return nil
        }
        return Double(text[range])
    }
}

nonisolated enum WeaponMetaError: LocalizedError {
    case invalidResponse
    case invalidData

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "The weapon source sent an unexpected response."
        case .invalidData: "The weapon source changed format, so no unverified stats were shown."
        }
    }
}

nonisolated private struct WeaponCatalogEntry: Sendable {
    let name: String
    let pageTitle: String
    let weaponClass: WeaponClass
}

nonisolated private struct WeaponWikiEnvelope: Decodable {
    let parse: WeaponWikiPayload
}

nonisolated private struct WeaponWikiPayload: Decodable {
    let revision: Int
    let text: String

    private enum CodingKeys: String, CodingKey {
        case revision = "revid"
        case text
    }
}

nonisolated private struct WeaponWikiQueryEnvelope: Decodable {
    let query: WeaponWikiQuery
}

nonisolated private struct WeaponWikiQuery: Decodable {
    let pages: [WeaponWikiPage]
}

nonisolated private struct WeaponWikiPage: Decodable, Sendable {
    let title: String
    let revisions: [WeaponWikiRevision]?
}

nonisolated private struct WeaponWikiRevision: Decodable, Sendable {
    let revision: Int
    let slots: WeaponWikiSlots

    private enum CodingKeys: String, CodingKey {
        case revision = "revid"
        case slots
    }
}

nonisolated private struct WeaponWikiSlots: Decodable, Sendable {
    let main: WeaponWikiContent
}

nonisolated private struct WeaponWikiContent: Decodable, Sendable {
    let content: String?
}
