import Foundation

nonisolated struct PatchNote: Codable, Equatable, Sendable {
    let title: String
    let publishedAt: Date?
    let url: URL
}

actor PatchNotesService {
    private static let feedURL = URL(
        string: "https://news.google.com/rss/search?q=site%3Aea.com%2Fgames%2Fapex-legends%20%22patch%20notes%22&hl=en-US&gl=US&ceid=US%3Aen"
    )!
    private static let cacheKey = "patch-notes.latest.v1"
    private static let cacheDateKey = "patch-notes.latest-date.v1"
    private static let cacheLifetime: TimeInterval = 12 * 60 * 60

    func latest(force: Bool = false, now: Date = .now) async throws -> PatchNote {
        let defaults = UserDefaults.standard

        if !force,
           let cachedAt = defaults.object(forKey: Self.cacheDateKey) as? Date,
           now.timeIntervalSince(cachedAt) < Self.cacheLifetime,
           let cached = loadCached(from: defaults) {
            return cached
        }

        var request = URLRequest(url: Self.feedURL)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadRevalidatingCacheData
        request.setValue("ApexMapCheck/1.0 iOS", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  data.count <= 1_000_000 else {
                throw PatchNotesError.invalidResponse
            }

            let parser = PatchNotesFeedParser(data: data)
            guard parser.parse(), let note = parser.latestPatchNote else {
                throw PatchNotesError.noPatchNotes
            }

            if let encoded = try? JSONEncoder().encode(note) {
                defaults.set(encoded, forKey: Self.cacheKey)
                defaults.set(now, forKey: Self.cacheDateKey)
            }
            return note
        } catch {
            if let cached = loadCached(from: defaults) {
                return cached
            }
            throw error
        }
    }

    private func loadCached(from defaults: UserDefaults) -> PatchNote? {
        guard let data = defaults.data(forKey: Self.cacheKey) else { return nil }
        return try? JSONDecoder().decode(PatchNote.self, from: data)
    }
}

nonisolated enum PatchNotesError: LocalizedError {
    case invalidResponse
    case noPatchNotes

    var errorDescription: String? {
        "Latest patch notes are temporarily unavailable."
    }
}

nonisolated private final class PatchNotesFeedParser: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    private var currentElement = ""
    private var currentTitle = ""
    private var currentLink = ""
    private var currentDate = ""
    private var currentSource = ""
    private var insideItem = false
    private var notes: [PatchNote] = []

    var latestPatchNote: PatchNote? {
        notes.sorted {
            ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast)
        }.first
    }

    init(data: Data) {
        parser = XMLParser(data: data)
        super.init()
        parser.delegate = self
        parser.shouldResolveExternalEntities = false
    }

    func parse() -> Bool {
        parser.parse()
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        if elementName == "item" {
            insideItem = true
            currentTitle = ""
            currentLink = ""
            currentDate = ""
            currentSource = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard insideItem else { return }
        switch currentElement {
        case "title": currentTitle += string
        case "link": currentLink += string
        case "pubDate": currentDate += string
        case "source": currentSource += string
        default: break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        defer { currentElement = "" }
        guard elementName == "item" else { return }
        insideItem = false

        let title = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = currentSource.trimmingCharacters(in: .whitespacesAndNewlines)
        let link = currentLink.trimmingCharacters(in: .whitespacesAndNewlines)

        guard title.localizedCaseInsensitiveContains("patch notes"),
              source.localizedCaseInsensitiveContains("Electronic Arts"),
              let url = URL(string: link),
              url.scheme == "https",
              url.host?.lowercased() == "news.google.com" else { return }

        notes.append(
            PatchNote(
                title: title.hasSuffix(" - \(source)")
                    ? String(title.dropLast(source.count + 3))
                    : title,
                publishedAt: Self.dateFormatter.date(from: currentDate),
                url: url
            )
        )
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        return formatter
    }()
}
