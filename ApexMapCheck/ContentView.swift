import SwiftUI

private enum AppSection: String, CaseIterable, Identifiable {
    case rotations
    case players
    case legends
    case weapons
    case intel
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rotations: "Rotations"
        case .players: "Players"
        case .legends: "Legends"
        case .weapons: "Weapons"
        case .intel: "Intel"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .rotations: "map.fill"
        case .players: "person.crop.circle.fill"
        case .legends: "person.3.fill"
        case .weapons: "scope"
        case .intel: "newspaper.fill"
        case .settings: "gearshape.fill"
        }
    }
}

struct ContentView: View {
    @State private var model = RotationViewModel()
    @State private var selection: AppSection = .rotations

    init() {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--show-players") {
            _selection = State(initialValue: .players)
        } else if ProcessInfo.processInfo.arguments.contains("--show-legends") {
            _selection = State(initialValue: .legends)
        } else if ProcessInfo.processInfo.arguments.contains("--show-weapons")
            || ProcessInfo.processInfo.arguments.contains("--show-weapon-simulator") {
            _selection = State(initialValue: .weapons)
        }
#endif
    }

    var body: some View {
        ApexTabBarLayout(selection: $selection) {
            sectionView(selection)
        }
        .preferredColorScheme(.dark)
        .task {
            await model.loadIfNeeded()
        }
    }

    @ViewBuilder
    private func sectionView(_ section: AppSection) -> some View {
        switch section {
        case .rotations:
            RotationScreen(model: model)
        case .players:
            PlayersScreen(apiKey: model.apiKey)
        case .legends:
            LegendsScreen()
        case .weapons:
            WeaponMetaScreen()
        case .intel:
            IntelScreen(model: model)
        case .settings:
            SettingsView(
                currentKey: model.usesBundledAPIKey ? "" : model.apiKey,
                usesBundledKey: model.usesBundledAPIKey,
                onSave: { key in await model.saveAPIKey(key) },
                onRemove: { model.removeAPIKey() }
            )
        }
    }
}

private struct ApexTabBarLayout<Content: View>: View {
    @Binding var selection: AppSection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false

    let content: () -> Content

    init(
        selection: Binding<AppSection>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        _selection = selection
        self.content = content
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--show-tab-menu") {
            _isExpanded = State(initialValue: true)
        }
#endif
    }

    var body: some View {
        GeometryReader { proxy in
            let chromeWidth = min(430, max(0, proxy.size.width - 24))
            let menuHeight = min(396, max(220, proxy.size.height - 116))

            ZStack(alignment: .bottom) {
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if isExpanded {
                    Color.black
                        .opacity(0.34)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture(perform: collapse)
                        .transition(.opacity)
                        .accessibilityHidden(true)
                }

                Group {
                    if isExpanded {
                        ApexExpandedTabMenu(
                            selection: selection,
                            select: select,
                            collapse: collapse
                        )
                        .frame(height: menuHeight)
                        .transition(expandedTransition)
                    } else {
                        ApexCompactTabBar(
                            selection: selection,
                            select: select,
                            toggleExpanded: toggleExpanded
                        )
                        .frame(height: 64)
                        .transition(expandedTransition)
                    }
                }
                .frame(width: chromeWidth)
                .padding(.bottom, 8)
                .zIndex(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: isExpanded)
    }

    private func select(_ section: AppSection) {
        selection = section

        if isExpanded {
            collapse()
        }
    }

    private func toggleExpanded() {
        withAnimation(navigationAnimation) {
            isExpanded.toggle()
        }
    }

    private func collapse() {
        withAnimation(navigationAnimation) {
            isExpanded = false
        }
    }

    private var navigationAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.16)
            : .spring(response: 0.32, dampingFraction: 0.9)
    }

    private var expandedTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .move(edge: .bottom).combined(with: .opacity)
            )
    }
}

private struct ApexCompactTabBar: View {
    let selection: AppSection
    let select: (AppSection) -> Void
    let toggleExpanded: () -> Void

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                tabItems
                    .glassEffect(
                        .regular
                            .tint(Color.black.opacity(0.5))
                            .interactive(),
                        in: .rect(cornerRadius: 24)
                    )
            } else {
                tabItems
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                    )
                    .background(
                        Color(red: 0.045, green: 0.049, blue: 0.06).opacity(0.78),
                        in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(.white.opacity(0.12), lineWidth: 1)
                    }
            }
        }
        .shadow(color: .black.opacity(0.46), radius: 24, y: 12)
        .animation(.easeOut(duration: 0.16), value: selection)
    }

    private var tabItems: some View {
        HStack(spacing: 2) {
            ForEach(AppSection.allCases) { section in
                Button {
                    select(section)
                } label: {
                    Image(systemName: section.symbol)
                        .font(.system(size: 17, weight: .bold))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(selection == section ? .white : .white.opacity(0.55))
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .contentShape(Rectangle())
                        .background {
                            if selection == section {
                                RoundedRectangle(cornerRadius: 15, style: .continuous)
                                    .fill(Color.apexRed.opacity(0.2))
                                    .overlay(alignment: .top) {
                                        Capsule()
                                            .fill(Color.apexRed)
                                            .frame(width: 18, height: 2)
                                            .padding(.top, 5)
                                    }
                            }
                        }
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(Rectangle())
                .buttonStyle(ApexNavigationButtonStyle())
                .accessibilityLabel(section.title)
                .accessibilityHint("Shows \(section.title)")
                .accessibilityAddTraits(selection == section ? .isSelected : [])
            }

            Button(action: toggleExpanded) {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .contentShape(Rectangle())
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(Rectangle())
            .buttonStyle(ApexNavigationButtonStyle())
            .accessibilityLabel("Expand navigation")
            .accessibilityHint("Shows every tab with its name")
            .accessibilityValue("Collapsed")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
    }
}

private struct ApexExpandedTabMenu: View {
    let selection: AppSection
    let select: (AppSection) -> Void
    let collapse: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if reduceTransparency {
                menuContent
                    .background(
                        Color(red: 0.035, green: 0.039, blue: 0.05),
                        in: RoundedRectangle(cornerRadius: 28, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(.white.opacity(0.18), lineWidth: 1)
                    }
            } else if #available(iOS 26.0, *) {
                menuContent
                    .glassEffect(
                        .regular
                            .tint(Color.black.opacity(0.4))
                            .interactive(),
                        in: .rect(cornerRadius: 28)
                    )
            } else {
                menuContent
                    .background(
                        Color(red: 0.035, green: 0.039, blue: 0.05).opacity(0.48),
                        in: RoundedRectangle(cornerRadius: 28, style: .continuous)
                    )
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: 28, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(.white.opacity(0.14), lineWidth: 1)
                    }
            }
        }
        .shadow(color: .black.opacity(0.5), radius: 28, y: 16)
        .accessibilityElement(children: .contain)
    }

    private var menuContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 4) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("APEX MAP CHECK")
                            .font(.system(size: 17, weight: .black))
                            .tracking(1.1)
                            .foregroundStyle(.white)

                        Button(action: collapse) {
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white.opacity(0.48))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(ApexNavigationButtonStyle())
                        .accessibilityLabel("Collapse navigation")
                        .accessibilityHint("Returns to the compact tab bar")
                    }

                    Text("NAVIGATION")
                        .font(.system(size: 11, weight: .black))
                        .tracking(1.8)
                        .foregroundStyle(Color.apexRed)
                }

                Spacer(minLength: 12)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 14)

            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(height: 1)
                .padding(.horizontal, 14)
                .accessibilityHidden(true)

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(AppSection.allCases) { section in
                        Button {
                            select(section)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: section.symbol)
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(selection == section ? Color.apexRed : .white.opacity(0.62))
                                    .frame(width: 28)

                                Text(section.title)
                                    .font(.body.weight(selection == section ? .bold : .semibold))
                                    .foregroundStyle(.white.opacity(selection == section ? 1 : 0.78))
                                    .lineLimit(1)

                                Spacer(minLength: 8)

                                if selection == section, !dynamicTypeSize.isAccessibilitySize {
                                    Text("CURRENT")
                                        .font(.caption2.weight(.black))
                                        .tracking(1.1)
                                        .foregroundStyle(Color.apexRed)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.horizontal, 14)
                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                            .contentShape(Rectangle())
                            .background(
                                selection == section ? Color.apexRed.opacity(0.12) : .clear,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                            .overlay(alignment: .leading) {
                                if selection == section {
                                    Capsule()
                                        .fill(Color.apexRed)
                                        .frame(width: 3, height: 24)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .contentShape(Rectangle())
                        .buttonStyle(ApexNavigationButtonStyle())
                        .accessibilityHint(selection == section ? "Currently selected" : "Shows \(section.title)")
                        .accessibilityAddTraits(selection == section ? .isSelected : [])
                    }
                }
                .padding(8)
            }
        }
    }
}

private struct ApexNavigationButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

private struct RotationScreen: View {
    var model: RotationViewModel

    var body: some View {
        ZStack {
            AppBackground()

            if model.hasAPIKey {
                rotationContent
            } else {
                APIKeySetupView { key in
                    await model.saveAPIKey(key)
                }
            }
        }
    }

    private var rotationContent: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                ScreenHeader(eyebrow: "LIVE NOW", title: "Map Rotation")

                if model.isLoading && model.rotations.isEmpty {
                    LoadingView()
                } else if model.rotations.isEmpty, let message = model.errorMessage {
                    RotationFailureView(
                        message: message,
                        actionURL: model.errorActionURL,
                        prepareForAction: model.prepareForAccountVerification
                    ) {
                        Task { await model.refresh() }
                    }
                } else if model.rotations.isEmpty {
                    EmptyRotationView {
                        Task { await model.refresh() }
                    }
                } else {
                    if let message = model.errorMessage {
                        ErrorBanner(message: message) {
                            Task { await model.refresh() }
                        }
                    }

                    ForEach(model.rotations) { rotation in
                        RotationCard(rotation: rotation)
                    }

                    statusFooter
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 28)
        }
        .refreshable {
            await model.refresh()
        }
        .scrollIndicators(.hidden)
        .apexNavigationScrollClearance()
    }

    private var statusFooter: some View {
        VStack(spacing: 10) {
            if let date = model.lastUpdated {
                Text("Updated \(date, style: .relative)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.56))
            }

            Link(destination: URL(string: "https://apexlegendsstatus.com")!) {
                HStack(spacing: 5) {
                    Text("Data provided by Apex Legends Status")
                    Image(systemName: "arrow.up.right")
                        .font(.caption2.weight(.bold))
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.72))
            }
            .accessibilityHint("Opens the data provider website")
        }
        .padding(.top, 6)
    }
}

private struct IntelScreen: View {
    var model: RotationViewModel

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ScreenHeader(eyebrow: "FROM EA", title: "Intel")

                    Text("Updates from the Outlands")
                        .font(.title2.weight(.black))
                        .foregroundStyle(.white)

                    PatchNotesCard(
                        note: model.latestPatchNote,
                        isLoading: model.isLoadingPatchNotes
                    )

                    if model.latestPatchNote == nil, !model.isLoadingPatchNotes {
                        ContentUnavailableView {
                            Label("No intel available", systemImage: "antenna.radiowaves.left.and.right.slash")
                        } description: {
                            Text("Pull to refresh and check again.")
                        }
                        .frame(minHeight: 280)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
            .refreshable {
                await model.loadPatchNotes(force: true)
            }
            .scrollIndicators(.hidden)
            .apexNavigationScrollClearance()
        }
    }
}

struct ScreenHeader: View {
    let eyebrow: String
    let title: String

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrow)
                    .font(.caption.weight(.black))
                    .tracking(2.6)
                    .foregroundStyle(Color.apexRed)

                Text(title)
                    .font(.largeTitle.weight(.black))
                    .tracking(-1.1)
                    .foregroundStyle(.white)
            }

            Spacer()
        }
        .padding(.top, 18)
    }
}

private struct PatchNotesCard: View {
    let note: PatchNote?
    let isLoading: Bool

    var body: some View {
        Group {
            if let note {
                Link(destination: note.url) {
                    HStack(spacing: 14) {
                        Image(systemName: "newspaper.fill")
                            .font(.title3)
                            .foregroundStyle(Color.apexRed)
                            .frame(width: 38, height: 38)
                            .background(Color.apexRed.opacity(0.13), in: Circle())

                        VStack(alignment: .leading, spacing: 4) {
                            Text("LATEST PATCH NOTES")
                                .font(.caption2.weight(.black))
                                .tracking(1.1)
                                .foregroundStyle(.white.opacity(0.55))

                            Text(note.title)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)

                            if let date = note.publishedAt {
                                Text(date, format: .dateTime.month(.abbreviated).day().year())
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                        }

                        Spacer(minLength: 4)

                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(.white.opacity(0.1), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the official Electronic Arts patch notes")
            } else if isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(.white)
                    Text("Checking for patch notes…")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            }
        }
    }
}

struct AppBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.039, blue: 0.05)
                .ignoresSafeArea()

            RadialGradient(
                colors: [Color.apexRed.opacity(0.18), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 430
            )
            .ignoresSafeArea()
        }
    }
}

private struct RotationCard: View {
    let rotation: GameModeRotation

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                mapArtwork
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.22), .black.opacity(0.94)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label(rotation.displayName.uppercased(), systemImage: rotation.symbolName)
                            .font(.caption.weight(.black))
                            .tracking(1.1)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(.black.opacity(0.58), in: Capsule())
                            .overlay {
                                Capsule()
                                    .stroke(.white.opacity(0.16), lineWidth: 1)
                            }

                        Spacer()

                        Text("LIVE")
                            .font(.caption2.weight(.black))
                            .tracking(1.2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.apexRed, in: Capsule())
                    }

                    Spacer(minLength: 36)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(rotation.current.map)
                            .font(.system(.title, design: .rounded, weight: .black))
                            .tracking(-0.7)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)

                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(rotation.current.countdown(at: context.date))
                                .font(.system(.title3, design: .monospaced, weight: .bold))
                                .foregroundStyle(.white.opacity(0.78))
                                .contentTransition(.numericText())
                                .accessibilityLabel("\(rotation.current.accessibleTimeRemaining(at: context.date)) remaining")
                        }
                    }

                    if let next = rotation.next {
                        Divider()
                            .overlay(.white.opacity(0.18))

                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) {
                                nextLabel
                                nextMap(next)
                                Spacer()
                                duration(next)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                nextLabel
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    nextMap(next)
                                    Spacer()
                                    duration(next)
                                }
                            }
                        }
                    }
                }
                .padding(20)
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 286)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.32), radius: 22, y: 12)
        .accessibilityElement(children: .contain)
    }

    private var nextLabel: some View {
        Text("NEXT")
            .font(.caption2.weight(.black))
            .tracking(1.1)
            .foregroundStyle(.white.opacity(0.5))
    }

    private func nextMap(_ window: MapWindow) -> some View {
        Text(window.map)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white.opacity(0.86))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func duration(_ window: MapWindow) -> some View {
        Text(window.durationLabel)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.58))
            .fixedSize()
    }

    @ViewBuilder
    private var mapArtwork: some View {
        if let assetURL = rotation.current.assetURL {
            AsyncImage(url: assetURL, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    MapFallback(mapName: rotation.current.map)
                }
            }
        } else {
            MapFallback(mapName: rotation.current.map)
        }
    }
}

private struct MapFallback: View {
    let mapName: String

    var body: some View {
        ZStack {
            LinearGradient(
                colors: palette,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: "mountain.2.fill")
                .font(.system(size: 112, weight: .black))
                .foregroundStyle(.white.opacity(0.08))
                .offset(x: 82, y: -38)
        }
    }

    private var palette: [Color] {
        let seed = mapName.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        let choices: [[Color]] = [
            [Color(red: 0.33, green: 0.10, blue: 0.10), Color(red: 0.06, green: 0.06, blue: 0.08)],
            [Color(red: 0.08, green: 0.25, blue: 0.28), Color(red: 0.04, green: 0.06, blue: 0.09)],
            [Color(red: 0.28, green: 0.18, blue: 0.08), Color(red: 0.06, green: 0.05, blue: 0.07)]
        ]
        return choices[seed % choices.count]
    }
}

private struct APIKeySetupView: View {
    @State private var key = ""
    @State private var isSaving = false
    @FocusState private var keyFocused: Bool

    let onSave: (String) async -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Spacer(minLength: 64)

                Image(systemName: "map.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(Color.apexRed, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: Color.apexRed.opacity(0.35), radius: 24, y: 12)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Know the map\nbefore you queue.")
                        .font(.system(.largeTitle, design: .rounded, weight: .black))
                        .tracking(-1.2)
                        .foregroundStyle(.white)

                    Text("See the live pubs and ranked rotations, the next map, and exactly when each switch happens.")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("APEX LEGENDS STATUS API KEY")
                        .font(.caption2.weight(.black))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.52))

                    SecureField("Paste your API key", text: $key)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($keyFocused)
                        .padding(16)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Button {
                        isSaving = true
                        Task {
                            await onSave(key.trimmingCharacters(in: .whitespacesAndNewlines))
                            isSaving = false
                        }
                    } label: {
                        Group {
                            if isSaving {
                                ProgressView().tint(.white)
                            } else {
                                Text("Check rotations")
                                    .fontWeight(.bold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.apexRed)
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)

                    Link("Get a free API key ↗", destination: URL(string: "https://apexlegendsapi.com/#my-api-access")!)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))
                }

                Text("Your key is stored securely in this device’s Keychain.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.44))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .apexNavigationScrollClearance()
    }
}

private struct SettingsView: View {
    @State private var key: String
    @State private var isSaving = false

    let usesBundledKey: Bool
    let onSave: (String) async -> Void
    let onRemove: () -> Void

    init(
        currentKey: String,
        usesBundledKey: Bool,
        onSave: @escaping (String) async -> Void,
        onRemove: @escaping () -> Void
    ) {
        _key = State(initialValue: currentKey)
        self.usesBundledKey = usesBundledKey
        self.onSave = onSave
        self.onRemove = onRemove
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("API access") {
                    if usesBundledKey {
                        Label("Included in this build", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)

                        Text("This build is configured for you and your friends. The key is not stored in the public Git repository.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        SecureField("API key", text: $key)
                            .textContentType(.password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    Link("Manage API access", destination: URL(string: "https://apexlegendsapi.com/#my-api-access")!)
                }

                if !usesBundledKey {
                    Section {
                        Button("Save and refresh") {
                            isSaving = true
                            Task {
                                await onSave(key.trimmingCharacters(in: .whitespacesAndNewlines))
                                isSaving = false
                            }
                        }
                        .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)

                        Button("Remove API key", role: .destructive) {
                            onRemove()
                        }
                    }
                }

                Section {
                    Link("Data provided by Apex Legends Status", destination: URL(string: "https://apexlegendsstatus.com")!)
                } footer: {
                    Text("This app is not affiliated with EA or Respawn Entertainment.")
                }
            }
            .apexNavigationScrollClearance()
            .navigationTitle("Settings")
        }
    }
}

struct ErrorBanner: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)

            Text(message)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white.opacity(0.82))
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("Retry", action: retry)
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
        }
        .padding(14)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct LoadingView: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(.white)
            Text("Finding the live maps…")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.62))
        }
        .frame(maxWidth: .infinity, minHeight: 360)
    }
}

private struct RotationFailureView: View {
    @Environment(\.openURL) private var openURL

    let message: String
    let actionURL: URL?
    let prepareForAction: () -> Void
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: actionURL == nil ? "exclamationmark.triangle.fill" : "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(actionURL == nil ? Color.yellow : Color.apexRed)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(actionURL == nil ? "Couldn’t load rotations" : "Verify API account")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)

                Text(message)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.62))
                    .frame(maxWidth: 320)
            }

            if let actionURL {
                Button("Verify API account") {
                    prepareForAction()
                    openURL(actionURL)
                }
                    .buttonStyle(.borderedProminent)
                    .tint(.apexRed)
            }

            Button("Try again", action: retry)
                .buttonStyle(.bordered)
                .tint(.white)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .padding(.horizontal, 24)
    }
}

private struct EmptyRotationView: View {
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No rotations found", systemImage: "map")
        } description: {
            Text("The service returned no active map rotations.")
        } actions: {
            Button("Try again", action: retry)
                .buttonStyle(.borderedProminent)
                .tint(.apexRed)
        }
        .frame(minHeight: 360)
    }
}

extension Color {
    static let apexRed = Color(red: 0.84, green: 0.12, blue: 0.13)
}

#Preview("Rotations") {
    ContentView()
}
