import AppIntents
import SwiftUI
import WidgetKit

struct RotationWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: RotationSnapshot?
    let configuration: ConfigurationAppIntent

    var selectedMode: GameModeRotation? {
        snapshot?.mode(id: configuration.mode.modeID, at: date)
    }
}

struct RotationProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> RotationWidgetEntry {
        RotationWidgetEntry(date: .now, snapshot: .preview, configuration: ConfigurationAppIntent())
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> RotationWidgetEntry {
        let snapshot = context.isPreview ? RotationSnapshot.preview : (RotationStore().loadSnapshot() ?? .preview)
        return RotationWidgetEntry(date: .now, snapshot: snapshot, configuration: configuration)
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<RotationWidgetEntry> {
        let store = RotationStore()
        let snapshot = try? await store.loadSmart()
        let now = Date.now
        var dates = [now]

        if let snapshot {
            let boundaries = snapshot.modes
                .compactMap(\.current.end)
                .filter { $0 > now }
                .map { $0.addingTimeInterval(1) }
            dates.append(contentsOf: boundaries)
        }

        let entries = Array(Set(dates)).sorted().map {
            RotationWidgetEntry(date: $0, snapshot: snapshot, configuration: configuration)
        }
        let reloadDate = store.suggestedReloadDate(for: snapshot, now: now)
        return Timeline(entries: entries, policy: .after(reloadDate))
    }
}

struct ApexMapCheckWidgetsEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RotationWidgetEntry

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                mediumView
            case .systemSmall:
                compactHomeView
            case .accessoryRectangular:
                rectangularView
            case .accessoryCircular:
                circularView
            case .accessoryInline:
                inlineView
            default:
                compactHomeView
            }
        }
        .dynamicTypeSize(.small ... .large)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var mediumView: some View {
        HStack(spacing: 0) {
            modeColumn(entry.snapshot?.mode(id: "battle_royale", at: entry.date))
            Divider().overlay(.white.opacity(0.14)).padding(.vertical, 2)
            modeColumn(entry.snapshot?.mode(id: "ranked", at: entry.date))
        }
        .padding(16)
        .containerBackground(for: .widget) { HomeWidgetBackground() }
    }

    private var compactHomeView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("APEX")
                    .font(.caption2.weight(.black))
                    .tracking(1.8)
                    .foregroundStyle(Color.widgetRed)
                Spacer()
                Image(systemName: entry.selectedMode?.symbolName ?? "map.fill")
                    .foregroundStyle(.white.opacity(0.68))
            }

            Spacer(minLength: 0)

            if let mode = entry.selectedMode {
                Text(mode.displayName.uppercased())
                    .font(.caption2.weight(.black))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.55))

                Text(mode.current.map)
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)

                switchTimer(mode.current)

                compactNextBlock(mode)
            } else {
                unavailableView
            }
        }
        .padding(16)
        .containerBackground(for: .widget) { HomeWidgetBackground() }
    }

    private func modeColumn(_ mode: GameModeRotation?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let mode {
                Label(mode.displayName.uppercased(), systemImage: mode.symbolName)
                    .font(.caption2.weight(.black))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.58))

                Spacer(minLength: 3)

                Text(mode.current.map)
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)

                switchTimer(mode.current)
                nextLine(mode)
            } else {
                unavailableView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
    }

    private var rectangularView: some View {
        Group {
            if let mode = entry.selectedMode {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: mode.symbolName)
                        Text(mode.displayName.uppercased())
                            .fontWeight(.bold)
                        Spacer()
                        if let end = mode.current.end {
                            Text(end, style: .timer).monospacedDigit()
                        }
                    }
                    .font(.caption2)

                    Text(mode.current.map)
                        .font(.headline.weight(.bold))
                        .lineLimit(1)

                    if let next = mode.next {
                        HStack(spacing: 4) {
                            Text("Next \(next.map)")
                                .lineLimit(1)
                            Spacer()
                            if let start = next.start ?? mode.current.end {
                                Text(start, style: .time)
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
            } else {
                Label("Open Apex Map Check", systemImage: "map")
                    .font(.caption.weight(.semibold))
            }
        }
        .containerBackground(for: .widget) { Color.clear }
        .widgetAccentable()
    }

    private var circularView: some View {
        ZStack {
            if let mode = entry.selectedMode {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: mode.symbolName)
                        .font(.caption2)
                    Text(mapInitials(mode.current.map))
                        .font(.caption.weight(.black))
                        .lineLimit(1)
                    if let end = mode.current.end {
                        Text(end, style: .timer)
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                    }
                }
            } else {
                Image(systemName: "map")
            }
        }
        .containerBackground(for: .widget) { Color.clear }
        .widgetAccentable()
    }

    private var inlineView: some View {
        Group {
            if let mode = entry.selectedMode {
                if let end = mode.current.end {
                    Label("\(mode.displayName): \(mode.current.map) until \(end, style: .time)", systemImage: mode.symbolName)
                } else {
                    Label("\(mode.displayName): \(mode.current.map)", systemImage: mode.symbolName)
                }
            } else {
                Label("Open Apex Map Check", systemImage: "map")
            }
        }
        .containerBackground(for: .widget) { Color.clear }
        .widgetAccentable()
    }

    private func switchTimer(_ window: MapWindow) -> some View {
        Group {
            if let end = window.end, end > entry.date {
                Text(end, style: .timer)
                    .monospacedDigit()
            } else {
                Text("Switching…")
            }
        }
        .font(.subheadline.weight(.bold))
        .foregroundStyle(.white.opacity(0.72))
    }

    private func nextLine(_ mode: GameModeRotation) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text("NEXT")
                    .font(.system(size: 8, weight: .black))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.4))
                if let next = mode.next {
                    Text(next.map)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                } else {
                    Text("Updating soon")
                }
            }

            if let start = mode.next?.start ?? mode.current.end {
                Text("Starts \(start, style: .time)")
                    .foregroundStyle(.white.opacity(0.48))
            }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.white.opacity(0.72))
    }

    private func compactNextBlock(_ mode: GameModeRotation) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text("NEXT")
                    .font(.system(size: 8, weight: .black))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.4))
                Text(mode.next?.map ?? "Updating soon")
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            if let start = mode.next?.start ?? mode.current.end {
                Text("Starts \(start, style: .time)")
                    .foregroundStyle(.white.opacity(0.48))
            }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.white.opacity(0.72))
    }

    private var unavailableView: some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: "iphone.and.arrow.forward")
            Text("Open the app")
                .font(.caption.weight(.bold))
            Text("to sync rotations")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func mapInitials(_ map: String) -> String {
        let words = map.split(separator: " ")
        return words.count == 1 ? String(map.prefix(3)).uppercased() : words.compactMap(\.first).map(String.init).joined().uppercased()
    }

    private var accessibilitySummary: String {
        guard let mode = entry.selectedMode else { return "Open Apex Map Check to sync rotations" }
        let remaining = mode.current.accessibleTimeRemaining(at: entry.date)
        let next = mode.next.map { ", next \($0.map)" } ?? ""
        return "\(mode.displayName), \(mode.current.map), \(remaining) remaining\(next)"
    }
}

private struct HomeWidgetBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.039, blue: 0.05)
            LinearGradient(
                colors: [Color.widgetRed.opacity(0.30), .clear],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
        }
    }
}

private extension Color {
    static let widgetRed = Color(red: 0.90, green: 0.10, blue: 0.12)
}

struct ApexMapCheckWidgets: Widget {
    static let kind = "ApexMapCheckWidgets"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: ConfigurationAppIntent.self, provider: RotationProvider()) { entry in
            ApexMapCheckWidgetsEntryView(entry: entry)
        }
        .configurationDisplayName("Apex Map Rotation")
        .description("Current and next maps for pubs and ranked.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

private extension ConfigurationAppIntent {
    static var rankedPreview: ConfigurationAppIntent {
        let intent = ConfigurationAppIntent()
        intent.mode = .ranked
        return intent
    }
}

#Preview("Home — Small", as: .systemSmall) {
    ApexMapCheckWidgets()
} timeline: {
    RotationWidgetEntry(date: .now, snapshot: .preview, configuration: .rankedPreview)
}

#Preview("Home — Medium", as: .systemMedium) {
    ApexMapCheckWidgets()
} timeline: {
    RotationWidgetEntry(date: .now, snapshot: .preview, configuration: .rankedPreview)
}

#Preview("Lock Screen", as: .accessoryRectangular) {
    ApexMapCheckWidgets()
} timeline: {
    RotationWidgetEntry(date: .now, snapshot: .preview, configuration: .rankedPreview)
}
