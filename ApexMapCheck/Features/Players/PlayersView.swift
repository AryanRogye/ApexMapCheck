import SwiftUI

struct PlayersScreen: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var model = PlayerViewModel()
    @FocusState private var searchFocused: Bool

    let apiKey: String

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ScreenHeader(
                            eyebrow: "SQUAD INTEL",
                            title: "Players"
                        )

                        PlayerSearchDeck(
                            query: $model.query,
                            platform: $model.platform,
                            isLoading: model.isLoading,
                            nextSearchAt: model.nextSearchAt,
                            hasAPIKey: !apiKey.isEmpty,
                            searchFocused: $searchFocused
                        ) {
                            searchFocused = false
                            Task { await model.search() }
                        }

                        if let errorMessage = model.errorMessage {
                            PlayerMessageBanner(
                                message: errorMessage,
                                symbol: "exclamationmark.triangle.fill",
                                color: .yellow
                            )
                        } else if let noticeMessage = model.noticeMessage {
                            PlayerMessageBanner(
                                message: noticeMessage,
                                symbol: "shield.checkered",
                                color: .green
                            )
                        }

                        if let selectedPlayer = model.selectedPlayer {
                            PlayerDossierCard(
                                player: selectedPlayer,
                                isFavorite: model.isFavorite(selectedPlayer),
                                isLoading: model.isLoading,
                                refreshAvailableAt: model.selectedRefreshDate(),
                                toggleFavorite: {
                                    Task { await model.toggleFavorite(selectedPlayer) }
                                },
                                refresh: {
                                    Task { await model.refreshSelected() }
                                }
                            )
                            .id(selectedPlayer.id)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        } else if !model.isLoading {
                            PlayerEmptyState()
                        }

                        if !model.favorites.isEmpty {
                            SavedSquadSection(
                                players: model.favorites,
                                selectedID: model.selectedPlayer?.id,
                                select: model.select,
                                remove: { player in
                                    Task { await model.removeFavorite(player) }
                                }
                            )
                        }

                        PlayerProviderFooter()
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, horizontalSizeClass == .compact ? 110 : 28)
                    .animation(.snappy(duration: 0.32), value: model.selectedPlayer?.id)
                }
                .refreshable {
                    await model.refreshSelected()
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollIndicators(.hidden)
            }
        }
        .task {
            await model.load(apiKey: apiKey)
        }
        .onChange(of: apiKey) { _, newValue in
            model.updateAPIKey(newValue)
        }
        .sensoryFeedback(.success, trigger: model.selectedPlayer?.id)
    }
}

private struct PlayerSearchDeck: View {
    @Binding var query: String
    @Binding var platform: PlayerPlatform
    let isLoading: Bool
    let nextSearchAt: Date?
    let hasAPIKey: Bool
    let searchFocused: FocusState<Bool>.Binding
    let search: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("FIND A PLAYER")
                        .font(.caption.weight(.black))
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.54))

                    Text(platform == .pc ? "Use their EA account name" : "Search their console tag")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }

                Spacer()

                Image(systemName: platform.symbolName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.apexRed)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
            }

            HStack(spacing: 6) {
                ForEach(PlayerPlatform.nameSearchCases) { choice in
                    Button {
                        withAnimation(.snappy(duration: 0.25)) {
                            platform = choice
                        }
                    } label: {
                        Label(choice.title, systemImage: choice.symbolName)
                            .labelStyle(PlayerPlatformLabelStyle())
                            .font(.caption.weight(.bold))
                            .foregroundStyle(platform == choice ? .white : .white.opacity(0.55))
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(
                                platform == choice ? Color.apexRed : .white.opacity(0.055),
                                in: UnevenRoundedRectangle(
                                    topLeadingRadius: 5,
                                    bottomLeadingRadius: 13,
                                    bottomTrailingRadius: 5,
                                    topTrailingRadius: 13,
                                    style: .continuous
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(platform == choice ? .isSelected : [])
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Player platform")

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.white.opacity(0.42))
                    .accessibilityHidden(true)

                TextField("Player name", text: $query)
                    .focused(searchFocused)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .foregroundStyle(.white)
                    .onSubmit(search)

                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.42))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear player name")
                }
            }
            .padding(.leading, 15)
            .padding(.trailing, 7)
            .frame(height: 50)
            .background(.black.opacity(0.38), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(searchFocused.wrappedValue ? Color.apexRed.opacity(0.9) : .white.opacity(0.1), lineWidth: 1)
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, Int(ceil((nextSearchAt ?? .distantPast).timeIntervalSince(context.date))))
                Button(action: search) {
                    HStack(spacing: 9) {
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: remaining > 0 ? "hourglass" : "scope")
                        }

                        Text(buttonTitle(remaining: remaining))
                            .fontWeight(.black)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 49)
                }
                .buttonStyle(.borderedProminent)
                .tint(.apexRed)
                .disabled(
                    query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || isLoading
                        || remaining > 0
                        || !hasAPIKey
                )
            }

            HStack(spacing: 10) {
                Image(systemName: "shield.lefthalf.filled")
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)

                Text("Smart refresh protects your key")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.72))

                Spacer(minLength: 8)

                Text("10s pace · 5m cache")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white.opacity(0.44))
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [.white.opacity(0.095), .white.opacity(0.035)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: UnevenRoundedRectangle(
                topLeadingRadius: 4,
                bottomLeadingRadius: 24,
                bottomTrailingRadius: 4,
                topTrailingRadius: 24,
                style: .continuous
            )
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.apexRed)
                .frame(width: 3)
        }
        .overlay {
            UnevenRoundedRectangle(
                topLeadingRadius: 4,
                bottomLeadingRadius: 24,
                bottomTrailingRadius: 4,
                topTrailingRadius: 24,
                style: .continuous
            )
            .stroke(.white.opacity(0.09), lineWidth: 1)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func buttonTitle(remaining: Int) -> String {
        guard hasAPIKey else { return "Add API Key in Settings" }
        if isLoading { return "Checking the Outlands…" }
        if remaining > 0 { return "Ready in \(remaining)s" }
        return "Check Player"
    }
}

private struct PlayerPlatformLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                configuration.icon
                configuration.title
            }

            configuration.icon
        }
    }
}

private struct PlayerDossierCard: View {
    let player: PlayerSnapshot
    let isFavorite: Bool
    let isLoading: Bool
    let refreshAvailableAt: Date?
    let toggleFavorite: () -> Void
    let refresh: () -> Void

    @State private var showsAllTrackers = false

    var body: some View {
        VStack(spacing: 0) {
            identityHeader
            rankBand
            trackerBoard
            actionBar
        }
        .background(Color(red: 0.055, green: 0.06, blue: 0.075))
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 5,
                bottomLeadingRadius: 28,
                bottomTrailingRadius: 5,
                topTrailingRadius: 28,
                style: .continuous
            )
        )
        .overlay {
            UnevenRoundedRectangle(
                topLeadingRadius: 5,
                bottomLeadingRadius: 28,
                bottomTrailingRadius: 5,
                topTrailingRadius: 28,
                style: .continuous
            )
            .stroke(.white.opacity(0.11), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.34), radius: 24, y: 14)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var identityHeader: some View {
        ZStack(alignment: .bottomLeading) {
            PlayerRemoteArtwork(url: player.legendBannerURL, fallbackSymbol: "person.crop.circle.fill")
                .frame(height: 190)

            LinearGradient(
                colors: [.black.opacity(0.05), .black.opacity(0.35), .black.opacity(0.96)],
                startPoint: .top,
                endPoint: .bottom
            )

            TacticalGrid()
                .stroke(.white.opacity(0.055), lineWidth: 1)
                .accessibilityHidden(true)

            HStack(alignment: .bottom, spacing: 14) {
                PlayerAvatar(player: player, size: 62)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Label(player.platform.compactTitle, systemImage: player.platform.symbolName)
                            .font(.caption2.weight(.black))
                            .tracking(0.9)
                            .foregroundStyle(.white.opacity(0.72))

                        if player.isOnline {
                            Label("ONLINE", systemImage: "circle.fill")
                                .font(.caption2.weight(.black))
                                .foregroundStyle(.green)
                        }
                    }

                    Text(player.name)
                        .font(.system(.title, design: .rounded, weight: .black))
                        .tracking(-0.7)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text("LEVEL \(player.displayLevel.formatted())")
                        .font(.caption.monospacedDigit().weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.58))
                }

                Spacer(minLength: 8)

                Button(action: toggleFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(isFavorite ? Color.yellow : .white)
                        .frame(width: 48, height: 48)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isFavorite ? "Remove \(player.name) from saved players" : "Save \(player.name)")
            }
            .padding(18)
        }
        .accessibilityElement(children: .contain)
    }

    private var rankBand: some View {
        HStack(spacing: 14) {
            PlayerRemoteArtwork(url: player.rank.imageURL, fallbackSymbol: "medal.fill")
                .scaledToFit()
                .frame(width: 62, height: 62)
                .padding(5)
                .background(rankColor.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("CURRENT RANK")
                    .font(.caption2.weight(.black))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.48))

                Text(player.rank.displayName)
                    .font(.title3.weight(.black))
                    .foregroundStyle(.white)

                if player.rank.score > 0 {
                    Text("\(player.rank.score.formatted()) RP")
                        .font(.subheadline.monospacedDigit().weight(.bold))
                        .foregroundStyle(rankColor)
                        .contentTransition(.numericText())
                }
            }

            Spacer()

            if let legend = player.selectedLegend {
                VStack(alignment: .trailing, spacing: 5) {
                    PlayerRemoteArtwork(url: player.legendIconURL, fallbackSymbol: "person.fill")
                        .scaledToFit()
                        .frame(width: 38, height: 38)

                    Text(legend.uppercased())
                        .font(.caption2.weight(.black))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.66))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .background(
            LinearGradient(
                colors: [rankColor.opacity(0.2), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .overlay(alignment: .top) {
            Divider().overlay(.white.opacity(0.08))
        }
        .overlay(alignment: .bottom) {
            Divider().overlay(.white.opacity(0.08))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rankAccessibilityLabel)
    }

    @ViewBuilder
    private var trackerBoard: some View {
        let trackers = player.featuredTrackers
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("TRACKER READOUT")
                    .font(.caption2.weight(.black))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.46))

                Spacer()

                if player.totals.count > 3 {
                    Button(showsAllTrackers ? "Show less" : "All stats") {
                        withAnimation(.snappy(duration: 0.3)) {
                            showsAllTrackers.toggle()
                        }
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.apexRed)
                }
            }

            if trackers.isEmpty {
                Text("No public trackers are equipped for this player.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.56))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                LazyVGrid(columns: trackerColumns, spacing: 10) {
                    ForEach(showsAllTrackers ? Array(player.totals.prefix(12)) : trackers) { tracker in
                        PlayerTrackerCell(tracker: tracker)
                    }
                }
            }
        }
        .padding(18)
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("CHECKED")
                    .font(.caption2.weight(.black))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.38))

                Text(player.fetchedAt, style: .relative)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.66))
            }

            Spacer()

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(
                    0,
                    Int(ceil((refreshAvailableAt ?? .distantPast).timeIntervalSince(context.date)))
                )

                Button(action: refresh) {
                    HStack(spacing: 7) {
                        if isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: remaining > 0 ? "clock" : "arrow.clockwise")
                        }
                        Text(remaining > 0 ? "Refresh in \(remaining)s" : "Refresh")
                    }
                    .font(.caption.weight(.black))
                    .frame(minWidth: 96, minHeight: 42)
                }
                .buttonStyle(.bordered)
                .tint(.white)
                .disabled(remaining > 0 || isLoading)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(.black.opacity(0.24))
    }

    private var trackerColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 92), spacing: 10)]
    }

    private var rankColor: Color {
        let normalized = player.rank.name.lowercased()
        if normalized.contains("predator") { return .red }
        if normalized.contains("master") { return .purple }
        if normalized.contains("diamond") { return .cyan }
        if normalized.contains("platinum") { return .teal }
        if normalized.contains("gold") { return .yellow }
        if normalized.contains("silver") { return Color(white: 0.75) }
        if normalized.contains("bronze") { return .orange }
        return Color.apexRed
    }

    private var rankAccessibilityLabel: String {
        var parts = ["Current rank \(player.rank.displayName)"]
        if player.rank.score > 0 { parts.append("\(player.rank.score) ranked points") }
        if let legend = player.selectedLegend { parts.append("selected legend \(legend)") }
        return parts.joined(separator: ", ")
    }
}

private struct PlayerTrackerCell: View {
    let tracker: PlayerTracker

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tracker.value, format: .number.precision(.fractionLength(tracker.value.rounded() == tracker.value ? 0 : 2)))
                .font(.system(.title3, design: .rounded, weight: .black))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(tracker.name.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.35)
                .foregroundStyle(.white.opacity(0.48))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .padding(11)
        .background(.white.opacity(0.055))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.apexRed.opacity(0.75))
                .frame(width: 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tracker.name), \(tracker.value.formatted())")
    }
}

private struct SavedSquadSection: View {
    let players: [PlayerSnapshot]
    let selectedID: String?
    let select: (PlayerSnapshot) -> Void
    let remove: (PlayerSnapshot) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SAVED SQUAD")
                        .font(.caption.weight(.black))
                        .tracking(1.3)
                        .foregroundStyle(.white.opacity(0.52))

                    Text("Your quick-select roster")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.38))
                }

                Spacer()

                Text("\(players.count) \(players.count == 1 ? "PLAYER" : "PLAYERS")")
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundStyle(.white.opacity(0.38))
            }

            ScrollView(.horizontal) {
                LazyHStack(spacing: 11) {
                    ForEach(players) { player in
                        SavedPlayerTag(
                            player: player,
                            isSelected: selectedID == player.id,
                            select: {
                                withAnimation(.snappy(duration: 0.28)) {
                                    select(player)
                                }
                            },
                            remove: { remove(player) }
                        )
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, 1, for: .scrollContent)
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

private struct SavedPlayerTag: View {
    let player: PlayerSnapshot
    let isSelected: Bool
    let select: () -> Void
    let remove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: select) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Label(player.platform.compactTitle, systemImage: player.platform.symbolName)
                            .font(.caption2.weight(.black))
                            .tracking(0.6)
                            .foregroundStyle(.white.opacity(0.62))

                        Spacer()
                    }

                    HStack(spacing: 11) {
                        PlayerAvatar(player: player, size: 48)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(player.name)
                                .font(.headline.weight(.black))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)

                            Text(player.rank.displayName.uppercased())
                                .font(.caption2.weight(.black))
                                .tracking(0.45)
                                .foregroundStyle(tagColor)
                                .lineLimit(1)
                        }
                    }

                    HStack(spacing: 6) {
                        if let legend = player.selectedLegend {
                            Image(systemName: "person.fill")
                                .accessibilityHidden(true)
                            Text(legend)
                                .lineLimit(1)
                        }

                        Spacer()

                        Text("LV \(player.displayLevel.formatted())")
                            .monospacedDigit()
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.44))
                }
                .padding(14)
                .frame(width: 190, height: 142, alignment: .topLeading)
                .background(
                    LinearGradient(
                        colors: [tagColor.opacity(isSelected ? 0.22 : 0.11), .white.opacity(0.035)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .contentShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 3,
                        bottomLeadingRadius: 20,
                        bottomTrailingRadius: 3,
                        topTrailingRadius: 20,
                        style: .continuous
                    )
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                "\(player.name), \(player.platform.title), \(player.rank.displayName)"
            )
            .accessibilityHint("Shows this player’s saved stats")
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            Button(action: remove) {
                Image(systemName: "star.fill")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.yellow)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(player.name) from saved players")
        }
        .background(Color(red: 0.055, green: 0.06, blue: 0.075))
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 3,
                bottomLeadingRadius: 20,
                bottomTrailingRadius: 3,
                topTrailingRadius: 20,
                style: .continuous
            )
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(isSelected ? Color.apexRed : tagColor.opacity(0.68))
                .frame(width: 3)
        }
        .overlay {
            UnevenRoundedRectangle(
                topLeadingRadius: 3,
                bottomLeadingRadius: 20,
                bottomTrailingRadius: 3,
                topTrailingRadius: 20,
                style: .continuous
            )
            .stroke(isSelected ? Color.apexRed.opacity(0.62) : .white.opacity(0.08), lineWidth: 1)
        }
    }

    private var tagColor: Color {
        let normalized = player.rank.name.lowercased()
        if normalized.contains("predator") { return .red }
        if normalized.contains("master") { return .purple }
        if normalized.contains("diamond") { return .cyan }
        if normalized.contains("platinum") { return .teal }
        if normalized.contains("gold") { return .yellow }
        if normalized.contains("silver") { return Color(white: 0.75) }
        if normalized.contains("bronze") { return .orange }
        return Color.apexRed
    }
}

private struct PlayerAvatar: View {
    let player: PlayerSnapshot
    let size: CGFloat

    var body: some View {
        PlayerRemoteArtwork(url: player.avatarURL, fallbackSymbol: player.platform.symbolName)
            .scaledToFill()
            .frame(width: size, height: size)
            .background(.black.opacity(0.35))
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 3,
                    bottomLeadingRadius: size * 0.3,
                    bottomTrailingRadius: 3,
                    topTrailingRadius: size * 0.3,
                    style: .continuous
                )
            )
            .overlay {
                UnevenRoundedRectangle(
                    topLeadingRadius: 3,
                    bottomLeadingRadius: size * 0.3,
                    bottomTrailingRadius: 3,
                    topTrailingRadius: size * 0.3,
                    style: .continuous
                )
                .stroke(.white.opacity(0.18), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}

private struct PlayerRemoteArtwork: View {
    let url: URL?
    let fallbackSymbol: String

    var body: some View {
        if let url {
            AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                switch phase {
                case .success(let image):
                    image.resizable()
                default:
                    fallback
                }
            }
        } else {
            fallback
        }
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(
                colors: [Color.apexRed.opacity(0.4), Color(red: 0.06, green: 0.065, blue: 0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: fallbackSymbol)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white.opacity(0.3))
        }
    }
}

private struct TacticalGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let spacing: CGFloat = 32
        var x = rect.minX - rect.height
        while x < rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += spacing
        }
        return path
    }
}

private struct PlayerMessageBanner: View {
    let message: String
    let symbol: String
    let color: Color

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .accessibilityHidden(true)

            Text(message)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.78))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(13)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct PlayerEmptyState: View {
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Image(systemName: "scope")
                    .font(.system(size: 74, weight: .ultraLight))
                    .foregroundStyle(Color.apexRed.opacity(0.72))

                Image(systemName: "person.fill")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white.opacity(0.84))
            }
            .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("Assemble your squad")
                    .font(.title2.weight(.black))
                    .foregroundStyle(.white)

                Text("Find a player, check their current rank and public trackers, then star them for one-tap access.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.56))
                    .frame(maxWidth: 340)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 270)
        .padding(.horizontal, 24)
    }
}

private struct PlayerProviderFooter: View {
    var body: some View {
        VStack(spacing: 8) {
            Link(
                "Data provided by Apex Legends Status",
                destination: URL(string: "https://apexlegendsstatus.com")!
            )
            .font(.caption.weight(.medium))
            .foregroundStyle(.white.opacity(0.7))
            .accessibilityHint("Opens the data provider website")

            Text("Public tracker availability varies by player. Exact match history requires separate provider access.")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.38))
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }
}

#Preview("Players") {
    PlayersScreen(apiKey: "preview-key")
}
