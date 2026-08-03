import SwiftUI

private enum AppSection: String, CaseIterable, Identifiable {
    case rotations
    case players
    case legends
    case intel
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rotations: "Rotations"
        case .players: "Players"
        case .legends: "Legends"
        case .intel: "Intel"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .rotations: "map.fill"
        case .players: "person.crop.circle.badge.magnifyingglass"
        case .legends: "person.3.fill"
        case .intel: "newspaper.fill"
        case .settings: "gearshape.fill"
        }
    }
}

struct ContentView: View {
    @StateObject private var model = RotationViewModel()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selection: AppSection = .rotations

    init() {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--show-players") {
            _selection = State(initialValue: .players)
        } else if ProcessInfo.processInfo.arguments.contains("--show-legends") {
            _selection = State(initialValue: .legends)
        }
#endif
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                NavigationSplitView {
                    List(
                        AppSection.allCases,
                        selection: Binding<AppSection?>(
                            get: { selection },
                            set: { newValue in
                                if let newValue {
                                    selection = newValue
                                }
                            }
                        )
                    ) { section in
                        Label(section.title, systemImage: section.symbol)
                            .tag(section)
                    }
                    .navigationTitle("APEX")
                    .tint(.apexRed)
                } detail: {
                    sectionView(selection)
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                ApexSidebarLayout(selection: $selection) {
                    sectionView(selection)
                }
            }
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

private struct SidebarActionKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

private extension EnvironmentValues {
    var apexSidebarAction: (() -> Void)? {
        get { self[SidebarActionKey.self] }
        set { self[SidebarActionKey.self] = newValue }
    }
}

private struct ApexSidebarLayout<Content: View>: View {
    private enum DragIntent {
        case undecided
        case horizontal
        case ignored
    }

    @Binding var selection: AppSection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sidebarProgress: CGFloat = 0
    @State private var dragStartProgress: CGFloat?
    @State private var dragIntent: DragIntent = .undecided

    let content: () -> Content

    init(
        selection: Binding<AppSection>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        _selection = selection
        self.content = content
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--show-sidebar") {
            _sidebarProgress = State(initialValue: 1)
        }
#endif
    }

    var body: some View {
        GeometryReader { proxy in
            let drawerWidth = min(308, proxy.size.width * 0.84)

            ZStack(alignment: .leading) {
                AppBackground()

                content()
                    .environment(\.apexSidebarAction, { openSidebar() })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scaleEffect(1 - 0.035 * sidebarProgress, anchor: .leading)
                    .rotation3DEffect(
                        .degrees(-3.5 * sidebarProgress),
                        axis: (x: 0, y: 1, z: 0),
                        anchor: .leading,
                        perspective: 0.8
                    )
                    .offset(x: (drawerWidth - 18) * sidebarProgress)
                    .overlay {
                        if sidebarProgress > 0.01 {
                            Color.black
                                .opacity(0.46 * sidebarProgress)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    closeSidebar()
                                }
                        }
                    }

                ApexSidebar(
                    selection: $selection,
                    select: select
                )
                .frame(width: drawerWidth)
                .offset(x: -drawerWidth + drawerWidth * sidebarProgress)
                .shadow(color: .black.opacity(0.46), radius: 28, x: 12, y: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .leading) {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: 88)
                        .allowsHitTesting(false)

                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(sidebarDrag(width: drawerWidth))
                        .allowsHitTesting(
                            sidebarProgress < 0.01 || dragStartProgress == 0
                        )
                }
                .frame(width: 28)
                .accessibilityHidden(true)
            }
            .overlay(alignment: .leading) {
                HStack(spacing: 0) {
                    Color.clear
                        .frame(width: drawerWidth - 44)
                        .allowsHitTesting(false)

                    Color.clear
                        .frame(width: 44)
                        .contentShape(Rectangle())
                        .gesture(sidebarDrag(width: drawerWidth))
                        .allowsHitTesting(
                            sidebarProgress > 0.99 || dragStartProgress == 1
                        )
                }
                .frame(maxHeight: .infinity)
                .accessibilityHidden(true)
            }
        }
    }

    private func select(_ section: AppSection) {
        selection = section
        closeSidebar()
    }

    private func openSidebar() {
        withAnimation(sidebarAnimation) {
            sidebarProgress = 1
        }
    }

    private func closeSidebar() {
        withAnimation(sidebarAnimation) {
            sidebarProgress = 0
        }
    }

    private func sidebarDrag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                guard dragIntent != .ignored else { return }

                if dragIntent == .undecided {
                    let horizontalDistance = abs(value.translation.width)
                    let verticalDistance = abs(value.translation.height)
                    let startedAtClosedEdge = sidebarProgress > 0.01
                        || value.startLocation.x <= 28
                    let movesTowardDrawer = sidebarProgress > 0.01
                        || value.translation.width > 0

                    if verticalDistance > horizontalDistance * 1.15
                        || !startedAtClosedEdge
                        || !movesTowardDrawer {
                        dragIntent = .ignored
                        return
                    }

                    guard horizontalDistance > verticalDistance * 1.15 else {
                        return
                    }

                    dragIntent = .horizontal
                    dragStartProgress = sidebarProgress
                }

                guard dragIntent == .horizontal else { return }

                let start = dragStartProgress ?? sidebarProgress
                sidebarProgress = min(
                    1,
                    max(0, start + value.translation.width / width)
                )
            }
            .onEnded { value in
                guard dragIntent == .horizontal else {
                    resetDrag()
                    return
                }

                let projectedMomentum = (value.predictedEndTranslation.width
                    - value.translation.width) / width
                let limitedMomentum = min(0.22, max(-0.22, projectedMomentum))
                let projectedProgress = sidebarProgress + limitedMomentum
                let target: CGFloat = projectedProgress >= 0.5 ? 1 : 0

                resetDrag()
                withAnimation(sidebarAnimation) {
                    sidebarProgress = target
                }
            }
    }

    private func resetDrag() {
        dragStartProgress = nil
        dragIntent = .undecided
    }

    private var sidebarAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.18)
            : .interactiveSpring(response: 0.32, dampingFraction: 0.86)
    }
}

private struct ApexSidebar: View {
    @Binding var selection: AppSection
    let select: (AppSection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("APEX MAP CHECK")
                    .font(.headline.weight(.black))
                    .tracking(1.5)
                    .foregroundStyle(.white)

                Text("NAVIGATION")
                    .font(.caption2.weight(.bold))
                    .tracking(1.6)
                    .foregroundStyle(.white.opacity(0.44))
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 28)

            Text("DROP IN")
                .font(.caption2.weight(.black))
                .tracking(1.8)
                .foregroundStyle(Color.apexRed)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(AppSection.allCases) { section in
                        SidebarRow(
                            section: section,
                            isSelected: selection == section,
                            action: { select(section) }
                        )
                    }
                }
                .padding(.horizontal, 12)
            }

            Spacer(minLength: 20)

            VStack(alignment: .leading, spacing: 5) {
                Rectangle()
                    .fill(Color.apexRed.opacity(0.72))
                    .frame(width: 34, height: 3)

                Text("NOT AFFILIATED WITH EA OR RESPAWN")
                    .font(.caption2.weight(.bold))
                    .tracking(0.75)
                    .foregroundStyle(.white.opacity(0.34))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 22)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            ZStack {
                Color(red: 0.025, green: 0.029, blue: 0.04)

                LinearGradient(
                    colors: [Color.apexRed.opacity(0.18), .clear],
                    startPoint: .topLeading,
                    endPoint: .center
                )
            }
            .ignoresSafeArea()
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(.white.opacity(0.12))
                .frame(width: 1)
                .ignoresSafeArea(.container, edges: .vertical)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct SidebarRow: View {
    let section: AppSection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: section.symbol)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isSelected ? Color.apexRed : .white.opacity(0.56))
                    .frame(width: 24)

                Text(section.title)
                    .font(.subheadline.weight(isSelected ? .bold : .medium))
                    .foregroundStyle(.white.opacity(isSelected ? 1 : 0.72))

                Spacer()

                if isSelected {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(Color.apexRed)
                }
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                isSelected ? Color.apexRed.opacity(0.13) : .clear,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.apexRed)
                        .frame(width: 3, height: 24)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isSelected ? "Currently selected" : "Shows \(section.title)")
    }
}

private struct RotationScreen: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject var model: RotationViewModel

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
            .padding(.bottom, horizontalSizeClass == .compact ? 110 : 28)
        }
        .refreshable {
            await model.refresh()
        }
        .scrollIndicators(.hidden)
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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject var model: RotationViewModel

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
                .padding(.bottom, horizontalSizeClass == .compact ? 110 : 28)
            }
            .refreshable {
                await model.loadPatchNotes(force: true)
            }
            .scrollIndicators(.hidden)
        }
    }
}

struct ScreenHeader: View {
    @Environment(\.apexSidebarAction) private var openSidebar

    let eyebrow: String
    let title: String

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if let openSidebar {
                SidebarMenuButton(action: openSidebar)
            }

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

private struct SidebarMenuButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "line.3.horizontal")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .contentShape(Rectangle())
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                }
        }
        .frame(width: 52, height: 52)
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .accessibilityLabel("Open navigation")
        .accessibilityHint("Shows the app sections")
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
    @Environment(\.apexSidebarAction) private var openSidebar
    @State private var key = ""
    @State private var isSaving = false
    @FocusState private var keyFocused: Bool

    let onSave: (String) async -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let openSidebar {
                    SidebarMenuButton(action: openSidebar)
                }

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
    }
}

private struct SettingsView: View {
    @Environment(\.apexSidebarAction) private var openSidebar
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
            .navigationTitle("Settings")
            .toolbar {
                if let openSidebar {
                    ToolbarItem(placement: .topBarLeading) {
                        SidebarMenuButton(action: openSidebar)
                    }
                }
            }
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
